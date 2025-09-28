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
        ddctoolbox-src = ./.;
        ddctoolbox-qt6 = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox-qt6";
          version = "2024-09-26.2";
          src = ddctoolbox-src;

          # Fix locale issues during build (use C.UTF-8 which Qt expects in many build environments)
          env = {
            LANG = "C.UTF-8";
            LC_ALL = "C.UTF-8";
          };
          # Enable standard Qt wrapping behavior so GUI apps are wrapped correctly.
          # We intentionally do not set `dontWrapQtApps` here so the `wrapQtAppsHook`
          # from nixpkgs (added below in nativeBuildInputs) can perform the proper
          # wrapping for GUI applications.

          # Use the canonical qt6 qmake and wrap hook from nixpkgs and keep standard native tools.
          # This ensures qmake and the wrapHook are provided by the qt6 namespace (recommended pattern).
          nativeBuildInputs =
            (with pkgs.qt6; [
              qmake
              wrapQtAppsHook
            ])
            ++ [
              pkgs.pkg-config
              pkgs.utf8cpp
              pkgs.perl
              pkgs.gnumake
              pkgs.kdePackages.qtsvg
            ];

          # Include explicit qmake in buildInputs so we can invoke it deterministically in configurePhase,
          # and include the Qt6 runtimes/modules needed.
          buildInputs = with pkgs; [
            qt6.qmake
            qt6.qtbase
            qt6.qttools
            qt6.qtsvg
            qt6.qtdeclarative
            qt6.qtshadertools
            libGL
            pipewire
          ];

          # Use the default qmake pre-phase behavior provided by the Qt hook from nixpkgs.
          # We rely on the canonical qmake / wrapQtAppsHook combination to prepare the build
          # environment for GUI wrapping and qmake invocation.

          # Patch sources by applying committed .patch files located in the flake's patches directory.
          # We apply patches from ${toString ./patches/qt6-patches} (expanded to a store path at evaluation time)
          # so they will be available during the build even when the source is fetched.
          # We also optionally run a helper script if included in the flake.
          patchPhase = ''
            runHook prePatch
            # patchPhase removed - we are editing the source directly under src/ for the Qt6 port.
            # No automatic sed/patch operations performed here; source changes are committed into git.
            runHook postPatch
          '';

          # Configure phase to set up proper qmake flags and point qmake at the upstream project file.
          configurePhase = ''
            runHook preConfigure

            # Set up Qt environment (prefer Qt6)
            export QT_SELECT=6

            # Choose the correct .pro file depending on how the source tree is laid out.
            # This makes the configure step robust when building from:
            # - a repository root (DDCToolbox.pro),
            # - a repository that vendors the project files under src/ (src.pro), or
            # - a source root that contains src/src.pro.
            #
            # We test for the files in that order and invoke qmake on the first match.
            #
            # Note: `qmake` is expected to be available in the build environment via the qmake wrapper/hook.
            if [ -f "$PWD/DDCToolbox.pro" ]; then
              echo "Using project file: $PWD/DDCToolbox.pro"
              qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 "$PWD/DDCToolbox.pro"
            elif [ -f "$PWD/src.pro" ]; then
              echo "Using project file: $PWD/src.pro"
              qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 "$PWD/src.pro"
            elif [ -f "$PWD/src/src.pro" ]; then
              echo "Using project file: $PWD/src/src.pro"
              qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 "$PWD/src/src.pro"
            else
              echo "Error: could not find a .pro file to run qmake on. Searched:"
              echo "  $PWD/DDCToolbox.pro"
              echo "  $PWD/src.pro"
              echo "  $PWD/src/src.pro"
              exit 1
            fi

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

            # Install the desktop file provided by the flake and the icon to standard places
            mkdir -p $out/share/applications
            if [ -e "${desktopFile}" ]; then
              cp -v "${desktopFile}" $out/share/applications/ddc_toolbox.desktop || true
            fi

            mkdir -p $out/share/pixmaps
            if [ -f res/img/icon.png ]; then
              cp -v res/img/icon.png $out/share/pixmaps/ddc-toolbox.png || true
            fi

            # Install any additional resources
            if [ -d resources ]; then
              mkdir -p $out/share/ddctoolbox
              cp -r resources/* $out/share/ddctoolbox/
            fi

            # Optionally install other runtime assets (icons, qrc, html docs)
            if [ -d res/html ]; then
              mkdir -p $out/share/ddctoolbox/html
              cp -r res/html/* $out/share/ddctoolbox/html/ || true
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
            mainProgram = "ddctoolbox-qt6";
          };
        };
      in
      {
        packages = {
          default = ddctoolbox-qt6;
          ddctoolbox = ddctoolbox-qt6;
        };

        apps.default = {
          type = "app";
          program = "${ddctoolbox-qt6}/bin/ddctoolbox";
        };

        devShells.default = pkgs.mkShell {
          #inputsFrom = [ ddctoolbox ];
          buildInputs = with pkgs; [
            # Development tools
            ddctoolbox-qt6
          ];
          shellHook = ''
            echo Welcome to "${pkgs.git}/bin/git branch --show-current" git branch DDCToolbox development environment
          '';
        };
      }
    );
}
