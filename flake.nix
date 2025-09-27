{
  description = "DDCToolbox - simple, Qt5-based flake using nixpkgs' qt5 qmake and wrapQtAppsHook";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        ddctoolbox-src = pkgs.fetchFromGitHub {
          owner = "timschneeb";
          repo = "DDCToolbox";
          rev = "master";
          # This sha256 is the existing placeholder used in this repo; update if the source changes.
          sha256 = "sha256-NqhSMfIAnpJcJ8qTSV61tbiCKoI+INfoknTl5/4g7h4=";
        };

        ddctoolbox = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox";
          version = "unstable-qt5";

          src = ddctoolbox-src;

          # Ensure a UTF-8 locale during build so Qt tools behave predictably.
          env = {
            LANG = "en_US.UTF-8";
            LC_ALL = "en_US.UTF-8";
          };

          # Do not rely on the qmake pre-hook. Keep only standard native build tools here.
          nativeBuildInputs = with pkgs; [ pkg-config gnumake automake autoconf ];

          buildInputs = with pkgs; [
            qt5.qmake
            qt5.qtbase
            qt5.qttools
            qt5.qtsvg
            libGL
            zlib
          ];

          # Minimal, predictable qmake + make flow; rely on NIX_BUILD_CORES for parallel builds.
          configurePhase = ''
            runHook preConfigure
            export QT_SELECT=5
            # Use the qmake wrapper exposed by pkgs.qt5
            ${pkgs.qt5.qmake}/bin/qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 DDCToolbox.pro
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            make -j$NIX_BUILD_CORES
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            mkdir -p $out/share/ddctoolbox

            # Prefer upstream `make install` when available
            if make -n install >/dev/null 2>&1; then
              make install PREFIX=$out || true
            fi

            # Fall back: try to install built binary(s)
            if [ -x src/ddctoolbox ]; then
              cp -v src/ddctoolbox $out/bin/ddctoolbox
            else
              # search for likely built binary names
              for f in DDCToolbox ddctoolbox; do
                if [ -x "$f" ]; then
                  cp -v "$f" $out/bin/ddctoolbox
                  break
                fi
              done
            fi

            # Install resources if present
            if [ -d resources ]; then
              cp -r resources/* $out/share/ddctoolbox/ || true
            fi

            runHook postInstall
          '';

          # Keep debug info separate to make debugging easier.
          separateDebugInfo = true;

          meta = with pkgs.lib; {
            description = "DDCToolbox - create and edit DDC files (built with Qt5)";
            homepage = "https://github.com/timschneeb/DDCToolbox";
            license = licenses.gpl3Plus;
            maintainers = [ "inayet" ];
            platforms = platforms.linux;
          };
        };
      in {
        packages = {
          default = ddctoolbox;
          ddctoolbox = ddctoolbox;
        };

        apps = {
          default = {
            type = "app";
            program = "${ddctoolbox}/bin/ddctoolbox";
          };
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              pkg-config
              gcc
              make
            ];

            shellHook = ''
              echo "Entered DDCToolbox development shell. Locale: $LANG"
            '';
          };
        };
      }
    );
}