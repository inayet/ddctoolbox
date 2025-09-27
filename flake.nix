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
        # desktopFile = pkgs.writeText "ddc_toolbox.desktop" ''
        #   [Desktop Entry]
        #   Name=DDC Toolbox
        #   GenericName=DDC Editor
        #   Comment=Create and edit DDCs on Linux
        #   Keywords=editor;audio;ddc
        #   Categories=AudioVideo;Audio;Editor;
        #   Exec=ddctoolbox
        #   Icon=ddc-toolbox
        #   StartupNotify=false
        #   Terminal=false
        #   Type=Application
        #   MimeType=application/x-ddc;
        # '';
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
          # During iterative Qt6 porting we avoid the automatic wrap/unwrapping checks so
          # the configure phase can call qmake explicitly against the repo working tree.
          # This ensures the build uses the repository `src` (with our patches) and
          # prevents the qmake pre-hook from failing due to missing helper binaries.
          dontWrapQtApps = true;


 
          # Use the canonical qt6 qmake and wrap hook from nixpkgs and keep standard native tools.
          # This ensures qmake and the wrapHook are provided by the qt6 namespace (recommended pattern).
          nativeBuildInputs = (with pkgs.qt6; [ qmake wrapQtAppsHook ]) ++ [ pkgs.pkg-config pkgs.utf8cpp pkgs.gnumake pkgs.kdePackages.qtsvg ];

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

          # No-op qmakePrePhase so the qmake hook won't run automatically; we call qmake explicitly in configurePhase.
          qmakePrePhase = ''
            runHook preQmake
            # Intentionally no-op: prevent automatic qmake hook behavior so configurePhase can call qmake deterministically
            runHook postQmake
          '';

          # Patch sources by applying committed .patch files in the flake's patches/qt6-patches directory.
          # This is cleaner and reproducible: patch files are stored in the flake and applied reliably.
          patchPhase = ''
            runHook prePatch
            echo "Applying .patch files from flake (patches/qt6-patches)..."

            PATCH_DIR=${toString ./patches/qt6-patches}
            if [ -d "$PATCH_DIR" ]; then
              for p in "$PATCH_DIR"/*.patch; do
                [ -f "$p" ] || continue
                echo "Applying patch: $p"
                patch -p1 < "$p" || true
              done
            else
              echo "No patch directory found at $PATCH_DIR; skipping patch application."
            fi

            runHook postPatch
          '';

          # Configure phase to set up proper qmake flags (use explicit qmake from pkgs.qt6)
          configurePhase = ''
            runHook preConfigure

            # Set up Qt environment (prefer Qt6)
            export QT_SELECT=6

            # Run qmake from the qt6 qmake wrapper to make the invocation deterministic
            ${pkgs.qt6.qmake}/bin/qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 DDCToolbox.pro

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
