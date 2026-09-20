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

            systemdTarget = "sway-session.target";

            profiles = {
              study = {
                outputs = [
                  {
                    criteria = "DP-2";
                    position = "2560,0";
                    mode = "2560x1440@180Hz";
                  }
                  {
                    criteria = "DP-3";
                    position = "0,0";
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

              startup = [
                {
                  command = "${pkgs.kanshi}/bin/kanshictl reload";
                  always = true;
                }
              ];

              focus = {
                followMouse = false;
              };

              window = {
                border = 2;
                hideEdgeBorders = "smart";
                titlebar = false;
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
                      }
                    );
                in
                {
                  # Gaming mode only keeps workspace bindings and nothing else
                  "${gameModeName}" = createMode workspaceBindings;
                };

              bars = [
                (
                  {
                    mode = "dock";
                    hiddenState = "hide";
                    position = "bottom";
                    workspaceButtons = true;
                    workspaceNumbers = true;
                    statusCommand = "${pkgs.i3status}/bin/i3status";
                    trayOutput = "primary";
                  }
                  // config.stylix.targets.sway.exportedBarConfig
                )
              ];

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

                "${modifier}+control+${up}" = "resize shrink height 10px or 10ppt";
                "${modifier}+control+${down}" = "resize grow height 10px or 10ppt";
                "${modifier}+control+${left}" = "resize shrink width 10px or 10ppt";
                "${modifier}+control+${right}" = "resize grow width 10px or 10ppt";

                "${modifier}+space" = "floating toggle";
                "${modifier}+Control+space" = "sticky toggle";

                "${modifier}+Shift+w" = "layout toggle tabbed split";

                "${modifier}+Shift+g" = ''mode "${gameModeName}"'';
              }
              // workspaceBindings;
            };

          extraConfig = ''
            # app specific fixes
            # https://github.com/ValveSoftware/steam-for-linux/issues/1040
            for_window [class="^Steam$" title="^Friends$"] floating enable
            for_window [class="^Steam$" title="Steam - News"] floating enable
            for_window [class="^Steam$" title=".* - Chat"] floating enable
            for_window [class="^Steam$" title="^Settings$"] floating enable
            for_window [class="^Steam$" title=".* - event started"] floating enable
            for_window [class="^Steam$" title=".* CD key"] floating enable
            for_window [class="^Steam$" title="^Steam - Self Updater$"] floating enable
            for_window [class="^Steam$" title="^Screenshot Uploader$"] floating enable
            for_window [class="^Steam$" title="^Steam Guard - Computer Authorization Required$"] floating enable
            for_window [title="^Steam Keyboard$"] floating enable

            for_window [window_role="pop-up"] floating enable
            for_window [window_role="task_dialog"] floating enable
            for_window [title="Settings"] floating enable
            for_window [window_role="PictureInPicture"] floating enable
            for_window [window_role="PictureInPicture"] sticky enable
            for_window [class="Plexamp"] floating enable
            for_window [class="Plexamp"] sticky enable
            for_window [title="splash"] floating enable
            for_window [title="searcher"] floating enable
          '';
        };
      })
    ]
  );
}
