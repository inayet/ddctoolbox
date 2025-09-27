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

          # Patch sources by applying committed .patch files located under the vendored upstream/ tree.
          # We apply patches from `upstream/patches/qt6-patches` so they match the upstream path layout
          # (patch files reference paths like a/src/..., and we run patch from the repository root).
          # Patch sources: run our scripted Qt6 fixes first (if present), then apply committed .patch files
          # from the repository's patches/qt6-patches directory. This ensures the helper script can make
          # best-effort mechanical edits, and the explicit patch files are applied afterwards reproducibly.
          patchPhase = ''
            runHook prePatch
            echo "Running Qt6 helper script (if present) and applying .patch files from patches/qt6-patches..."

            # 1) Run the repository helper script (idempotent, best-effort).
            if [ -x "${PWD}/patches/qt6-fix.sh" ]; then
              echo "Executing helper: ${PWD}/patches/qt6-fix.sh"
              (cd "$PWD" && ./patches/qt6-fix.sh) || true
            else
              echo "No helper script at ./patches/qt6-fix.sh (skipping)."
            fi

            # 2) Apply canonical patch files from the repo's patches/qt6-patches directory
            PATCH_DIR="$PWD/patches/qt6-patches"
            if [ -d "$PATCH_DIR" ]; then
              for p in "$PATCH_DIR"/*.patch; do
                [ -f "$p" ] || continue
                echo "Applying patch: $p"
                # Apply in repository root (strip one component to match a/... b/... diffs)
                (cd "$PWD" && patch -p1 < "$p") || true
              done
            else
              echo "No patch directory found at $PATCH_DIR; skipping patch application."
            fi

            # 3) Quick replacement pass for application attribute name mismatches (best-effort)
            #    Replace common Qt::AA_* references with a more explicit ApplicationAttribute qualified form
            #    so code that references attributes in a newer Qt layout compiles more easily.
            echo "Performing quick attribute name replacements (Qt::AA_ -> Qt::ApplicationAttribute::AA_)"
            # Only alter source files under src and 3rdparty code where present
            for f in $(grep -R --line-number -E "Qt::AA_[A-Za-z0-9_]+" src 2>/dev/null | cut -d: -f1 | sort -u); do
              echo " - patching $f"
              sed -i 's/Qt::AA_DisableWindowContextHelpButton/Qt::ApplicationAttribute::AA_DisableWindowContextHelpButton/g' "$f" || true
              sed -i 's/Qt::AA_EnableHighDpiScaling/Qt::ApplicationAttribute::AA_EnableHighDpiScaling/g' "$f" || true
              sed -i 's/Qt::AA_/Qt::ApplicationAttribute::AA_/g' "$f" || true
            done || true

            runHook postPatch
          '';

          # Configure phase to set up proper qmake flags and point qmake at the upstream project file.
          configurePhase = ''
            runHook preConfigure

            # Set up Qt environment (prefer Qt6)
            export QT_SELECT=6

            # Invoke qmake and point it at the upstream project's .pro file at repository root.
            qmake -r PREFIX=$out CONFIG+=release CONFIG+=c++17 DDCToolbox.pro

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
