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

        programs = {
          swaylock.enable = true;
        };

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

          swayidle =
            let
              display = status: "${pkgs.sway}/bin/swaymsg 'output * power ${status}'";
              lock = "if ! ${pkgs.procps}/bin/pgrep --exact --uid $(${pkgs.coreutils}/bin/id -u) swaylock >/dev/null; then ${config.programs.swaylock.package}/bin/swaylock --daemonize; fi";
            in
            {
              enable = true;

              timeouts = [
                {
                  timeout = 300; # in seconds
                  command = "${pkgs.libnotify}/bin/notify-send 'Locking in 5 seconds' -t 5000";
                }
                {
                  timeout = 305;
                  command = lock;
                }
                {
                  timeout = 360;
                  command = display "off";
                  resumeCommand = display "on";
                }
                {
                  timeout = 900;
                  command = "${pkgs.systemd}/bin/systemctl suspend";
                }
              ];

              events = [
                {
                  event = "before-sleep";
                  # Avoid trying to lock again when suspend follows the idle lock.
                  command = (display "off") + "; " + lock;
                }
                {
                  event = "after-resume";
                  command = display "on";
                }
                {
                  event = "lock";
                  command = (display "off") + "; " + lock;
                }
                {
                  event = "unlock";
                  command = display "on";
                }
              ];
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
              powerManagementMode = " : Screen [l]ock, [e]xit, [s]uspend, [h]ibernate, [R]eboot, [S]hutdown";
            in
            rec {
              modifier = "Mod1";

              up = "k";
              down = "j";
              left = "h";
              right = "l";

              terminal = "ghostty";
              menu = "${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop --dmenu='${pkgs.wmenu}/bin/wmenu -i' --term=${terminal}";

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
                  "${gameModeName}" = workspaceBindings // {
                    "${modifier}+Shift+g" = "floating_modifier ${modifier}, mode default";
                  };

                  "${powerManagementMode}" = createMode {
                    "l" = "mode default, exec ${config.programs.swaylock.package}/bin/swaylock";
                    "e" = "exit";
                    "s" = "mode default, exec ${pkgs.systemd}/bin/systemctl suspend";
                    "h" = "mode default, exec ${pkgs.systemd}/bin/systemctl hibernate";
                    "R" = "mode default, exec ${pkgs.systemd}/bin/systemctl reboot";
                    "S" = "mode default, exec ${pkgs.systemd}/bin/systemctl poweroff";
                  };
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

                "${modifier}+Shift+g" = ''floating_modifier none, mode "${gameModeName}"'';
                "${modifier}+Escape" = ''mode "${powerManagementMode}"'';

                # Multimedia keys
                "XF86AudioRaiseVolume" =
                  "exec ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
                "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
                "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
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
