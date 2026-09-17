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

        home.packages = with pkgs; [
          wmenu
        ];

        wayland.windowManager.sway = {
          enable = true;
          wrapperFeatures.gtk = true;
          package = pkgs.swayfx;

          # required false for swayfx
          checkConfig = false;

          config = {
            modifier = "Mod4";

            up = "k";
            down = "j";
            left = "h";
            right = "l";

            terminal = "ghostty";
            menu = "wmenu";

            workspaceAutoBackAndForth = true;
            workspaceLayout = "default";

            focus = {
              followMouse = false;
            };

            keybindings =
              let
                modifier = config.wayland.windowManager.sway.config.modifier;
                workspaces = [
                  1
                  2
                  3
                  4
                  5
                  6
                  7
                  8
                  9
                  0
                ];
              in
              {
                "${modifier}+Return" = "exec $terminal";
                "${modifier}+Shift+q" = "kill";

                "${modifier}+n" = "exec ${lib.getExe config.programs.firefox.package}";
                "${modifier}+d" = "exec $menu";
              };
          };

          gaps = {
            inner = 15;
            outer = 15;
          };

          extraSessionCommands = ''
            # give Sway a little time to startup before starting kanshi.
            exec sleep 5; systemctl --user start kanshi.service
          '';

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
