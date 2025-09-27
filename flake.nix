{
  description = "DDCToolbox built with Qt5 and qmake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
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

        # Apply patches to fix Qt6 compatibility issues
        ddctoolbox-src = pkgs.fetchFromGitHub {
          owner = "timschneeb";
          repo = "DDCToolbox";
          rev = "master";
          sha256 = "NqhSMfIAnpJcJ8qTSV61tbiCKoI+INfoknTl5/4g7h4=";
        };

        ddctoolbox = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox";
          version = "2024.09.26.1";
          src = ddctoolbox-src;

          # # Fix locale issues during build
          # env = {
          #   LANG = "UTF-8";
          #   LC_ALL = "UTF-8";
          # };
          nativeBuildInputs = with pkgs; [
            qt5.qmake
            qt5.wrapQtAppsHook
            pkg-config
          ];
          #TODO use new versions of qt5 ie qt6
          buildInputs = with pkgs; [
            qt5.qtbase
            qt5.qttools
            qt5.qtsvg
            qt5.qtnetworkauth
            pipewire
            qt5.qmake
            gnumake
          ];

          # # Patch the source code to fix compilation issues
          # postPatch = ''
          #   # Fix deprecated Qt5 APIs that were removed in Qt6
          #   find . -name "*.cpp" -o -name "*.h" | xargs sed -i \
          #     -e 's/AA_DisableWindowContextHelpButton/AA_DisableWindowContextHelpButton/g' \
          #     -e 's/setFallbackSessionManagementEnabled/\/\/setFallbackSessionManagementEnabled/g'

          #   # The application attribute exists in Qt5, so we don't need to remove it
          #   # Just comment out the problematic setFallbackSessionManagementEnabled call
          #   sed -i 's/QGuiApplication::setFallbackSessionManagementEnabled(false);/\/\/QGuiApplication::setFallbackSessionManagementEnabled(false);/' src/VdcEditorWindow.cpp

          #   # Fix QCustomPlot Qt5 compatibility
          #   # Replace deprecated qsrand/qrand with QRandomGenerator (if Qt 5.10+) or keep as is for older Qt5
          #   find . -name "*.cpp" | xargs sed -i \
          #     -e 's/qsrand(/\/\/qsrand(/g' \
          #     -e 's/qrand()/QTime::currentTime().msec()/g'
          # '';

          configurePhase = ''
            runHook preConfigure

            # Run qmake with proper flags for Qt5
            qmake PREFIX=$out \
                  CONFIG+=release \
                  CONFIG+=c++14 \
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

            # Check if we found an executable
            if [ ! -f "$out/bin/ddctoolbox" ]; then
              echo "Searching for DDCToolbox executable..."
              find . -name "*DDC*" -type f -executable || true
              find . -name "*toolbox*" -type f -executable || true
              echo "Available files:"
              find . -type f -executable | head -20
              exit 1
            fi

            # Make sure it's executable
            chmod +x $out/bin/ddctoolbox

            # Install desktop file
            mkdir -p $out/share/applications
            cp ${desktopFile} $out/share/applications/ddc_toolbox.desktop

            # Install icon if available
            mkdir -p $out/share/pixmaps
            iconFound=false
            for iconPath in img/icon.png src/img/icon.png assets/icon.png resources/icon.png; do
              if [ -f "$iconPath" ]; then
                cp "$iconPath" $out/share/pixmaps/ddc-toolbox.png
                iconFound=true
                break
              fi
            done

            if [ "$iconFound" = false ]; then
              echo "Warning: No icon found, creating a placeholder"
              echo "DDC" > $out/share/pixmaps/ddc-toolbox.png
            fi

            # Install any additional resources
            if [ -d resources ]; then
              mkdir -p $out/share/ddctoolbox
              cp -r resources/* $out/share/ddctoolbox/ || true
            fi

            runHook postInstall
          '';

          # Enable debug symbols for troubleshooting if needed
          separateDebugInfo = true; # Disable to reduce build time

          meta = with pkgs.lib; {
            description = "Create and edit DDCs (Digital Dynamic Range Compression) files on Linux";
            longDescription = ''
              DDCToolbox is a tool for creating and editing DDC (Digital Dynamic Range Compression)
              files on Linux. It provides a graphical interface for managing audio processing parameters.

              This build uses Qt5 for compatibility with the original codebase.
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
          inputsFrom = [ ddctoolbox ];
          buildInputs = with pkgs; [

          ];
          package = [ ddctoolbox ];

          shellHook = '''';
        };
      }
    );
}
