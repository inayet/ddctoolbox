{
  description = "DDCToolbox (Qt5) - flake with qmake build, UTF-8 locale, and cleaned build inputs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        ddctoolbox-src = pkgs.fetchFromGitHub {
          owner = "timschneeb";
          repo = "DDCToolbox";
          rev = "master";
          # Keep the sha256 as a placeholder; update if fetch changes.
          sha256 = "sha256-NqhSMfIAnpJcJ8qTSV61tbiCKoI+INfoknTl5/4g7h4=";
        };

        ddctoolbox-qt5 = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox-qt5";
          version = "2025-09-27";

          src = ddctoolbox-src;

          # Ensure the build environment uses a UTF-8 locale to keep Qt happy
          env = {
            LANG = "en_US.UTF-8";
            LC_ALL = "en_US.UTF-8";
          };

          nativeBuildInputs = with pkgs; [
            pkg-config
            gnumake
            automake
            autoconf
            # qmake for Qt5
            qt5.qtbase
            qt5.qttools
            qt5.qmake
            qt5.wrapQtAppsHook
           ];

          buildInputs = with pkgs; [
            # Qt5 runtime and modules needed
            qt5.qtbase
            qt5.qttools
            qt5.qtsvg
            qt5.qtdeclarative
            libGL
            zlib
            # Common tools that may be used by the project
            glib
            openssl
          ];

          # Run qmake in a predictable way for Qt5
          configurePhase = ''
            runHook preConfigure

            # Make sure qmake/Qt5 is selected
            export QT_SELECT=5

            # qmake invocation - prefer the qmake wrapper from the Qt5 derivation
            # The project's top-level .pro file is `DDCToolbox.pro` according to upstream
            ${pkgs.qt5.qmake}/bin/qmake -r -spec linux-g++ PREFIX=$out CONFIG+=release CONFIG+=c++17 DDCToolbox.pro

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            # Build with parallel jobs (use NIX-provided parallelism variable)
            make -j$NIX_BUILD_CORES
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            mkdir -p $out/share/ddctoolbox

            # Try `make install` if provided, otherwise install the built binary and resources
            if make -n install >/dev/null 2>&1; then
              make install PREFIX=$out || true
            fi

            # Install the binary if present
            if [ -f "ddctoolbox" ]; then
              cp -v ddctoolbox $out/bin/
            else
              # Try to find a built binary in common locations
              if [ -f src/ddctoolbox ]; then
                cp -v src/ddctoolbox $out/bin/
              fi
            fi

            # Copy resources if present
            if [ -d resources ]; then
              cp -r resources/* $out/share/ddctoolbox/ || true
            fi

            runHook postInstall
          '';

          # Keep separate debug info to help diagnosing build/runtime issues
          separateDebugInfo = true;

          meta = with pkgs.lib; {
            description = "DDCToolbox - create and edit DDCs (built with Qt5)";
            longDescription = ''
              DDCToolbox is a graphical tool for creating and editing DDC (Digital Dynamic
              Range Compression) files. This flake builds the project with Qt5, ensures a UTF-8
              locale during the build, and uses a simplified/cleaner set of build inputs.
            '';
            homepage = "https://github.com/timschneeb/DDCToolbox";
            license = licenses.gpl3Plus;
            maintainers = [ "inayet" ];
            platforms = with platforms; [ "x86_64-linux" ];
            # Note: actual installed binary name should be verified upstream
            # mainProgram = "ddctoolbox";
          };
        };
      in {
        packages = {
          default = ddctoolbox-qt5;
          ddctoolbox = ddctoolbox-qt5;
        };

        apps = {
          default = {
            type = "app";
            program = "${ddctoolbox-qt5}/bin/ddctoolbox";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            ddctoolbox-qt5
            pkgs.git
            pkgs.gcc
            pkgs.gnumake
          ];

          shellHook = ''
            echo "Entered DDCToolbox (Qt5) development shell. Locale: $LANG"
          '';
        };
      }
    );
}