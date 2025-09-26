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

        desktopFile = pkgs.writeText "ddc_toolbox.desktop" ''
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
        '';

        ddctoolbox-src = pkgs.fetchFromGitHub {
          owner = "timschneeb";
          repo = "DDCToolbox";
          rev = "master";
          sha256 = "sha256-NqhSMfIAnpJcJ8qTSV61tbiCKoI+INfoknTl5/4g7h4="; # pkgs.lib.fakeHash;
        };
        ddctoolbox = pkgs.stdenv.mkDerivation {
          pname = "ddctoolbox";
          version = "unstable";
          src = ddctoolbox-src;
          nativeBuildInputs = with pkgs.qt6; [
            qmake
            wrapQtAppsHook

          ];
          buildInputs = with pkgs; [
            kdePackages.qtbase
            kdePackages.qttools # For Qt Designer, tools
            kdePackages.qtsvg
            kdePackages.qt6ct # If the app uses SVG icons
            libGL
            utf8cpp
          ];
          installPhase = ''
            mkdir -p $out/bin
            find . -type f -name DDCToolbox -exec cp {} $out/bin/ddctoolbox \;
                        
            mkdir -p $out/share/applications
            cp ${desktopFile} $out/share/applications/ddc_toolbox.desktop

            mkdir -p $out/share/pixmaps
            if [ -f img/icon.png ]; then
              cp img/icon.png $out/share/pixmaps/ddc-toolbox.png
            fi
          '';
          meta = with pkgs.lib; {
            description = "Create and edit DDCs on Linux";
            homepage = "https://github.com/ThePBone/DDCToolbox";
            license = licenses.gpl3Plus;
            maintainers = [
              "timschneeb"
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
          program = "${self.packages.ddctoolbox}/bin/ddctoolbox";
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            kdePackages.qtbase
            kdePackages.qttools # For Qt Designer, tools
            kdePackages.qtsvg
            kdePackages.qt6ct # If the app uses SVG icons
            libGL
            utf8cpp
          ];
        };
      }
    );
}
