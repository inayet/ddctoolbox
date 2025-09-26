{
  description = "DDCToolbox built with Qt5 and qmake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        ddctoolbox-src = pkgs.fetchgit {
          url = "https://github.com/ThePBone/DDCToolbox.git";
          rev = "master"; # Consider pinning a commit for reproducibility
          sha256 = "sha256-00mg0hry3ysdgjrah9gsmvhlsvldrsnxnjjrbx52al30s8nkg3rf";
        };
        ddctoolbox = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox";
          version = "unstable";

          src = ddctoolbox-src;

          nativeBuildInputs = with pkgs.qt5; [
            qmake
            wrapQtAppsHook
          ];
          buildInputs = with pkgs; [
            qt5.qtbase
            libGL
          ];

          installPhase = ''

            mkdir -p $out/bin
            find . -type f -name DDCToolbox -exec cp {} $out/bin/ddctoolbox \;
                        
            mkdir -p $out/share/applications
            cat > $out/share/applications/ddc_toolbox.desktop <<EOF
            [Desktop Entry]
            Name=DDC Toolbox
            GenericName=DDC Editor
            Comment=Create and edit DDCs on Linux
            Keywords=editor
            Categories=AudioVideo;Audio;Editor
            Exec=ddctoolbox
            Icon=ddc-toolbox
            StartupNotify=false
            Terminal=false
            Type=Application
            EOF

            mkdir -p $out/share/pixmaps
            cp img/icon.png $out/share/pixmaps/ddc-toolbox.png
          '';

          meta = with pkgs.lib; {
            description = "Create and edit DDCs on Linux";
            homepage = "https://github.com/ThePBone/DDCToolbox";
            license = licenses.gpl3Plus;
            maintainers = [

              "inayet"
            ];
            platforms = platforms.linux;
          };
        };

      in
      {
        packages.default = ddctoolbox;

        apps.default = {
          type = "app";
          program = "${ddctoolbox}/bin/ddctoolbox";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            qt5.qmake
            qt5.qtbase
            libGL
          ];
        };
      }
    );
}
