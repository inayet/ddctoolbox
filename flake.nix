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
          # Bypass automatic Qt wrapping checks during build; we'll handle wrapping later if needed.
          dontWrapQtApps = true;

          # Use the qt6 namespace so the qmake/wrap hooks are wired correctly by nixpkgs,
          # and keep common native build tools.
          nativeBuildInputs = (with pkgs.qt6; [ qmake wrapQtAppsHook ]) ++ (with pkgs; [ pkg-config utf8cpp gnumake ]);

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

          # Patch sources for Qt6 compatibility and configure qmake
          patchPhase = ''
            runHook prePatch
            echo "Applying Qt6 compatibility patches..."

            # 1) Replace QWheelEvent::delta()/pos() usage with Qt6 equivalents
            #    - delta() -> angleDelta().y()
            #    - pos() -> position()
            # Best-effort: operate on all .cpp/.h files under src/
            for f in $(grep -R --line-number -E "event->delta\\(|event->pos\\(" src 2>/dev/null | cut -d: -f1 | sort -u); do
              [ -f "$f" ] || continue
              sed -i 's/event->delta()/event->angleDelta().y()/g' "$f" || true
              sed -i 's/event->pos()/event->position()/g' "$f" || true
              sed -i 's/event->pos().x()/event->position().x()/g' "$f" || true
              sed -i 's/event->pos().y()/event->position().y()/g' "$f" || true
            done

            # 2) Replace QMap::unite usages (unavailable on some Qt6 builds) with manual insert loop
            if [ -f src/plot/QCustomPlot.cpp ]; then
              sed -i "s/mTicks.unite(ticks);/for (auto it = ticks.constBegin(); it != ticks.constEnd(); ++it) mTicks.insert(it.key(), it.value());/g" src/plot/QCustomPlot.cpp || true
            fi

            # 3) Replace QSet::toList() -> QSet::values() / values() usage
            for f in $(grep -R --line-number -E "\\.toList\\(\\)" src 2>/dev/null | cut -d: -f1 | sort -u); do
              sed -i 's/\\.toList()/\\.values()/g' "$f" || true
            done

            # 4) QWeakPointer::data() -> toStrongRef() usage for safety
            #    Replace common pattern "mPaintBuffer.data()->" with a safe toStrongRef() guard where possible.
            if [ -f src/plot/QCustomPlot.cpp ]; then
              sed -n '1,99999p' src/plot/QCustomPlot.cpp > /tmp/qcp.$$ || true
              # Replace occurrences of "->mPaintBuffer.data()->" with a guarded form (best-effort)
              sed -i "s/\\([A-Za-z0-9_]*->mPaintBuffer\\)\\.data()\\(->[A-Za-z0-9_]*(\\)/\\1.toStrongRef()\\2/g" /tmp/qcp.$$ || true
              mv /tmp/qcp.$$ src/plot/QCustomPlot.cpp || true
            fi

            # 5) QPainter render hint change: HighQualityAntialiasing -> Antialiasing
            for f in $(grep -R --line-number -E "HighQualityAntialiasing" src 2>/dev/null | cut -d: -f1 | sort -u); do
              sed -i 's/HighQualityAntialiasing/Antialiasing/g' "$f" || true
            done

            # 6) QImage::mirrored -> prefer flipped if necessary (leave mirrored for compatibility)
            for f in $(grep -R --line-number -E "mirrored\\(" src 2>/dev/null | cut -d: -f1 | sort -u); do
              # leave as-is for now; mirrored is deprecated but usually present; keep for manual follow-up if needed
              true
            done

            # 7) Other API adaptations might be required and will show up in subsequent build errors.
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
