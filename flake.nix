{
  description = "DDCToolbox built with Qt6 and qmake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    inputs@{
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        desktopFile = pkgs.writeText "ddc_toolbox.desktop" ''
          [Desktop Entry]
          Name=DDC Toolbox
          GenericName=DDC Editor
          Comment=Create and edit DDCs on Linux
          Keywords=editor;audio;ddc
          Categories=AudioVideo;Audio;Editor;
          Exec=ddctoolbox
          Icon=ddc-toolbox
          StartupNotify=false
          Terminal=false
          Type=Application
          MimeType=application/x-ddc;
        '';
        ddctoolbox-src = pkgs.fetchFromGitHub {
          owner = "timschneeb";
          repo = "DDCToolbox";
          rev = "master";
          sha256 = "sha256-NqhSMfIAnpJcJ8qTSV61tbiCKoI+INfoknTl5/4g7h4=";
        };
        ddctoolbox = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox";
          version = "2024-09-26";
          src = ddctoolbox-src;

          # Fix locale issues during build
          env = {
            LANG = "UTF-8";
            LC_ALL = "UTF-8";
          };

          nativeBuildInputs = [
            pkgs.qt6.wrapQtAppsHook
            pkgs.pkg-configUpstream
            pkgs.utf8cpp
            pkgs.qt6.qmake
            pkgs.gnumake

          ];

          buildInputs = [

            pkgs.qt6.qtbase
            pkgs.qt6.qttools
            pkgs.qt6.qt5compat
            pkgs.qt6.qtdeclarative
            pkgs.qt6.qttools
            pkgs.qt6.qtshadertools
            pkgs.qt6.full
            pkgs.qt6.qmake
            pkgs.qt6.qtsvg
            pkgs.libGL
            pkgs.qt6.full
            #utf8cpp
            # Additional dependencies that might be needed
            pkgs.pipewire
            pkgs.qt6.qtbase
          ];

          # Configure phase to set up proper qmake flags
          configurePhase = ''
            runHook preConfigure

            # Set up Qt environment
            export QT_SELECT=6

            # Run qmake with proper flags
            qmake PREFIX=$out \
                  CONFIG+=release \
                  CONFIG+=c++17 \
                  DDCToolbox.pro

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            # Build with parallel jobs
            make -j$NIX_BUILD_CORES

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            # Install the binary
            mkdir -p $out/bin

            # Ensure we have an executable
            if [ ! -f "$out/bin/ddctoolbox" ]; then
              echo "Error: DDCToolbox executable not found!"
              find . -name "*DDC*" -type f
              exit 1
            fi

            # Install desktop file
            mkdir -p $out/share/applications
            cp ${desktopFile} $out/share/applications/ddc_toolbox.desktop

            # Install icon if available
            mkdir -p $out/share/pixmaps
            if [ -f img/icon.png ]; then
              cp img/icon.png $out/share/pixmaps/ddc-toolbox.png
            elif [ -f src/img/icon.png ]; then
              cp src/img/icon.png $out/share/pixmaps/ddc-toolbox.png
            elif [ -f assets/icon.png ]; then
              cp assets/icon.png $out/share/pixmaps/ddc-toolbox.png
            fi

            # Install any additional resources
            if [ -d resources ]; then
              mkdir -p $out/share/ddctoolbox
              cp -r resources/* $out/share/ddctoolbox/
            fi

            runHook postInstall
          '';

          # Enable debug symbols for troubleshooting if needed
          separateDebugInfo = true;

          meta = with pkgs.lib; {
            description = "Create and edit DDCs (Digital Dynamic Range Compression) files on Linux";
            longDescription = ''
              DDCToolbox is a tool for creating and editing DDC (Digital Dynamic Range Compression) 
              files on Linux. It provides a graphical interface for managing audio processing parameters.
            '';
            homepage = "https://github.com/timschneeb/DDCToolbox";
            license = licenses.gpl3Plus;
            maintainers = with maintainers; [
              "timschneeb"
              "inayet"
            ];
            platforms = with platforms.linux; [ "x86_64-linux" ];
            mainProgram = "ddctoolbox";
          };
        };
      in
      {
        packages = {
          default = ddctoolbox;
          ddctoolbox = ddctoolbox;
        };

        apps.default = {
          type = "app";
          program = "${ddctoolbox}/bin/ddctoolbox";
        };

        devShells.default = pkgs.mkShell {
          #inputsFrom = [ ddctoolbox ];
          buildInputs = with pkgs; [
            # Development tools
          ];
          shellHook = ''
            # echo "Welcome to "${pkgs.git}/bin/git branch --show-current" git branch DDCToolbox development environment"
          '';
        };
      }
    );
}
