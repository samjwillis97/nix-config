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
        home.packages = with pkgs; [
          wmenu
        ];

        services = {
          # auto mounting of external storage devices
          udiskie.enable = true;

          # monitor setup
          kanshi = {
            enable = true;

            systemdTarget = "";

            profiles = {
              study = {
                outputs = [
                  {
                    criteria = "DP-3";
                    position = "0,0";
                    mode = "2560x1440@180Hz";
                  }
                  {
                    criteria = "DP-2";
                    position = "2560,0";
                    mode = "2560x1440@180Hz";
                  }
                ];
              };
            };
          };
        };

        wayland.windowManager.sway = {
          enable = true;
          wrapperFeatures.gtk = true;
          package = pkgs.swayfx;

          # required false for swayfx
          checkConfig = false;

          config =
            let
              modifier = config.wayland.windowManager.sway.config.modifier;

              workspaces = [
                "1"
                "2"
                "3"
                "4"
                "5"
                "6"
                "7"
                "8"
                "9"
                "0"
              ];

              workspaceBindings = lib.mergeAttrsList (
                map (workspace: {
                  "${modifier}+${workspace}" = "workspace ${workspace}";
                  "${modifier}+Shift+${workspace}" = "move container to workspace ${workspace}";
                }) workspaces
              );

              gameModeName = "Gaming B)";
            in
            rec {
              modifier = "Mod1";

              up = "k";
              down = "j";
              left = "h";
              right = "l";

              terminal = "ghostty";
              menu = "wmenu-run";

              workspaceAutoBackAndForth = true;
              workspaceLayout = "default";

              focus = {
                followMouse = false;
              };

              input = {
                "*" = {
                  accel_profile = "flat";
                  repeat_delay = "250";
                  repeat_rate = "50";
                };
              };

              modes =
                let
                  createMode =
                    bindings:
                    (
                      bindings
                      // {
                        "Escape" = "mode default";
                        "Return" = "mode default";
                      }
                    );
                in
                {
                  # Gaming mode only keeps workspace bindings and nothing else
                  "${gameModeName}" = createMode workspaceBindings;
                };

              keybindings = {
                "${modifier}+Return" = "exec ${terminal}";
                "${modifier}+Shift+q" = "kill";

                "${modifier}+n" = "exec ${lib.getExe config.programs.firefox.package}";
                "${modifier}+d" = "exec ${menu}";

                "${modifier}+s" = "split v";
                "${modifier}+v" = "split h";

                "${modifier}+Shift+minus" = "move scratchpad";
                "${modifier}+minus" = "scratchpad show";

                "${modifier}+${up}" = "focus up";
                "${modifier}+${down}" = "focus down";
                "${modifier}+${left}" = "focus left";
                "${modifier}+${right}" = "focus right";

                "${modifier}+Shift+${up}" = "move up";
                "${modifier}+Shift+${down}" = "move down";
                "${modifier}+Shift+${left}" = "move left";
                "${modifier}+Shift+${right}" = "move right";

                "${modifier}+space" = "floating toggle";
                "${modifier}+Control+space" = "sticky toggle";

                "${modifier}+Shift+g" = ''mode "${gameModeName}"'';
              }
              // workspaceBindings;
            };

          # gaps = {
          #   inner = 15;
          #   outer = 15;
          # };

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
