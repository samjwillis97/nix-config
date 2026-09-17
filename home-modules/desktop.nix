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
        # auto mounting of external storage devices
        services.udiskie.enable = true;

        wayland.windowManager.sway = {
          enable = true;
          wrapperFeatures.gtk = true;
          package = pkgs.swayfx;

          # required false for swayfx
          checkConfig = false;

          config = rec {
            modifier = "Mod4";
            terminal = "ghostty";

            workspaceAutoBackAndForth = true;
            workspaceLayout = "default";

            focus = {
              followMouse = false;
            };

            keybindings = {
              "${modifier}+Return" = "exec ${terminal}";
              "${modifier}+Shift+q" = "kill";

              "${modifier}+n" = "exec ${lib.getExe config.programs.firefox.package}";
              "${modifier}+d" = "exec ${lib.getExe pkgs.wmenu}";
            };
          };

          extraConfig = ''
            shadows enable
            corner_radius 11
            blur_radius 7
            blur_passes 2
          '';
        };
      })
    ]
  );
}
