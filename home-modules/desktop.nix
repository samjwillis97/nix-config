{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.desktop.enable (
    lib.mkMerge [
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        home.packages = with pkgs.brewCasks; [
          raycast
          displaylink
          betterdisplay
        ];
      })

      (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
        wayland.windowManager.sway = {
          enable = true;
          wrapperFeatures.gtk = true;
          # package = pkgs.swayfx;

          checkConfig = true;

          config = rec {
            modifier = "Mod4";
            terminal = "ghostty";
            keybindings = {
              "${modifier}+Return" = "exec ${terminal}";
            };
          };
        };
      })
    ]
  );
}
