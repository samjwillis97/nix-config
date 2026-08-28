{ config
, pkgs
, lib
, ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  desktopEnabled = config.my.desktop.enable;
in
{
  config = lib.mkMerge [
    (lib.mkIf desktopEnabled {
      programs.ghostty = {
        enable = true;
        enableZshIntegration = false;

        settings = {
          title = "Ghostty";
          macos-titlebar-style = "hidden";
          cursor-style = "block";
          font-feature = "-calt";
          font-thicken = true;
          shell-integration-features = "no-cursor, title";
        };
      };
    })

    (lib.mkIf (desktopEnabled && !isDarwin) {
      programs.ghostty = {
        systemd.enable = true;
      };
    })

    (lib.mkIf (desktopEnabled && isDarwin) {
      programs.ghostty = {
        systemd.enable = false;
        package = pkgs.ghostty-bin;
        settings = {
          window-colorspace = "display-p3";
        };
      };
    })
  ];
}
