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

      (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) (
        let
          noctaliaExecutable = lib.getExe config.programs.noctalia.package;
          ghosttyExecutable = lib.getExe config.programs.ghostty.package;
          firefoxExecutable = lib.getExe config.programs.firefox.package;
          monitorPowerOn = "${pkgs.niri}/bin/niri msg action power-on-monitors";

          gameModeStateFile = "${config.home.homeDirectory}/.local/state/niri/game-mode.kdl";
          gameModeExit = pkgs.writeShellScript "niri-game-mode-exit" ''
            set -eu
            rm -f ${lib.escapeShellArg gameModeStateFile}
            ${pkgs.niri}/bin/niri msg action load-config-file
            ${noctaliaExecutable} msg plugin sam/game-mode:bar all set off >/dev/null 2>&1 || true
          '';
          gameModeConfig = pkgs.writeText "niri-game-mode.kdl" ''
            // Switch niri's compositor modifier to Super so Alt-based game input
            // is not consumed by the normal Mod bindings or mouse gestures.
            input {
              mod-key "Super"
              mod-key-nested "Super"
            }

            binds {
              Alt+Shift+G allow-inhibiting=false hotkey-overlay-title="Exit game mode" repeat=false { spawn "${gameModeExit}"; }
              Alt+Tab allow-inhibiting=false repeat=false { focus-workspace-previous; }
              Alt+Page_Down allow-inhibiting=false { focus-workspace-down; }
              Alt+Page_Up allow-inhibiting=false { focus-workspace-up; }
              Alt+Ctrl+Page_Down allow-inhibiting=false { move-column-to-workspace-down; }
              Alt+Ctrl+Page_Up allow-inhibiting=false { move-column-to-workspace-up; }
              Alt+U allow-inhibiting=false { focus-workspace-down; }
              Alt+I allow-inhibiting=false { focus-workspace-up; }
              Alt+Ctrl+U allow-inhibiting=false { move-column-to-workspace-down; }
              Alt+Ctrl+I allow-inhibiting=false { move-column-to-workspace-up; }
              Alt+WheelScrollDown allow-inhibiting=false cooldown-ms=150 { focus-workspace-down; }
              Alt+WheelScrollUp allow-inhibiting=false cooldown-ms=150 { focus-workspace-up; }
              Alt+Ctrl+WheelScrollDown allow-inhibiting=false cooldown-ms=150 { move-column-to-workspace-down; }
              Alt+Ctrl+WheelScrollUp allow-inhibiting=false cooldown-ms=150 { move-column-to-workspace-up; }
            }
          '';
          gameModeEnter = pkgs.writeShellScript "niri-game-mode-enter" ''
            set -eu
            state_file=${lib.escapeShellArg gameModeStateFile}
            if [ -e "$state_file" ]; then
              exit 0
            fi
            install -d -m 0755 "$(dirname "$state_file")"
            temporary_file="$(mktemp "$state_file.XXXXXX")"
            trap 'rm -f "$temporary_file"' EXIT
            cp ${lib.escapeShellArg gameModeConfig} "$temporary_file"
            chmod 0644 "$temporary_file"
            mv "$temporary_file" "$state_file"
            ${pkgs.niri}/bin/niri msg action load-config-file
            ${noctaliaExecutable} msg plugin sam/game-mode:bar all set on >/dev/null 2>&1 || true
          '';

          niriConfig = pkgs.writeText "niri-config.kdl" ''
            input {
              keyboard {
                xkb {}
                repeat-delay 250
                repeat-rate 50
              }
              touchpad {
                accel-profile "flat"
              }
              mouse {
                accel-profile "flat"
              }
              trackpoint {
                accel-profile "flat"
              }
              trackball {
                accel-profile "flat"
              }
              workspace-auto-back-and-forth
              mod-key "Alt"
              mod-key-nested "Alt"
            }

            output "DP-3" {
              mode "2560x1440@180.002"
              scale 1
              position x=0 y=0
            }

            output "DP-2" {
              mode "2560x1440@180.002"
              scale 1
              position x=2560 y=0
            }


            // Workspaces are intentionally dynamic and local to each output.
            layout {
              gaps 16
              struts {
                left 64
                right 64
                top 64
                bottom 64
              }

              center-focused-column "never"
              always-center-single-column
              default-column-display "normal"
              default-column-width { proportion 0.66667; }
              preset-column-widths {
                proportion 0.33333
                proportion 0.5
                proportion 0.66667
                proportion 1.0
              }

              focus-ring {
                width 2
                active-color "#${config.lib.stylix.colors.base0D}"
                inactive-color "#${config.lib.stylix.colors.base03}"
                urgent-color "#${config.lib.stylix.colors.base08}"
              }
              border {
                off
              }
              shadow {
                on
              }
              background-color "#${config.lib.stylix.colors.base00}"
            }

            overview {
              backdrop-color "#${config.lib.stylix.colors.base00}"
            }

            prefer-no-csd

            cursor {
              xcursor-theme "${config.stylix.cursor.name}"
              xcursor-size ${toString config.stylix.cursor.size}
            }

            debug {
              honor-xdg-activation-with-invalid-serial
            }

            binds {
              Mod+Return repeat=false { spawn "${ghosttyExecutable}"; }
              Mod+Shift+Q repeat=false { close-window; }
              Mod+N repeat=false { spawn "${firefoxExecutable}"; }
              Mod+D repeat=false { spawn "${noctaliaExecutable}" "msg" "panel-toggle" "launcher"; }
              Mod+Escape repeat=false { spawn "${noctaliaExecutable}" "msg" "panel-toggle" "session"; }
              Mod+Ctrl+Comma repeat=false { spawn "${noctaliaExecutable}" "msg" "settings-toggle"; }
              Mod+Shift+C repeat=false { spawn "${noctaliaExecutable}" "msg" "panel-toggle" "control-center"; }
              Mod+Ctrl+Escape repeat=false { spawn "${noctaliaExecutable}" "msg" "session" "lock"; }

              Mod+H { focus-column-left; }
              Mod+J { focus-window-down; }
              Mod+K { focus-window-up; }
              Mod+L { focus-column-right; }
              Mod+Shift+H { move-column-left; }
              Mod+Shift+J { move-window-down; }
              Mod+Shift+K { move-window-up; }
              Mod+Shift+L { move-column-right; }
              Mod+Ctrl+H { set-column-width "-10%"; }
              Mod+Ctrl+L { set-column-width "+10%"; }
              Mod+Ctrl+K { set-window-height "-10%"; }
              Mod+Ctrl+J { set-window-height "+10%"; }
              Mod+R { switch-preset-column-width; }
              Mod+Shift+R { switch-preset-column-width-back; }

              Mod+Space repeat=false { toggle-window-floating; }
              Mod+Shift+Space repeat=false { switch-focus-between-floating-and-tiling; }
              Mod+Shift+W repeat=false { toggle-column-tabbed-display; }
              Mod+S { consume-window-into-column; }
              Mod+V { expel-window-from-column; }
              Mod+Tab repeat=false { focus-workspace-previous; }
              Mod+Page_Down { focus-workspace-down; }
              Mod+Page_Up { focus-workspace-up; }
              Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
              Mod+Ctrl+Page_Up { move-column-to-workspace-up; }
              Mod+U { focus-workspace-down; }
              Mod+I { focus-workspace-up; }
              Mod+Ctrl+U { move-column-to-workspace-down; }
              Mod+Ctrl+I { move-column-to-workspace-up; }
              Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
              Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }
              Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
              Mod+Ctrl+WheelScrollUp cooldown-ms=150 { move-column-to-workspace-up; }

              Mod+Ctrl+Left { focus-monitor-left; }
              Mod+Ctrl+Right { focus-monitor-right; }
              Mod+Ctrl+Shift+Left { move-window-to-monitor-left; }
              Mod+Ctrl+Shift+Right { move-window-to-monitor-right; }
              Mod+Comma { focus-monitor-left; }
              Mod+Period { focus-monitor-right; }
              Mod+Shift+Comma { move-window-to-monitor-left; }
              Mod+Shift+Period { move-window-to-monitor-right; }
              Mod+O repeat=false { toggle-overview; }
              Mod+F repeat=false { maximize-column; }
              Mod+Shift+F repeat=false { fullscreen-window; }
              // Game mode dynamically disables compositor bindings while preserving workspaces.
              Mod+Shift+G hotkey-overlay-title="Enter game mode" allow-inhibiting=false repeat=false { spawn "${gameModeEnter}"; }
              Mod+Shift+E repeat=false { quit; }
              Mod+Shift+Slash repeat=false { show-hotkey-overlay; }

              Print repeat=false { screenshot; }
              Ctrl+Print repeat=false { screenshot-screen; }
              Alt+Print repeat=false { screenshot-window; }

              XF86AudioRaiseVolume allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-up" "5"; }
              XF86AudioLowerVolume allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-down" "5"; }
              XF86AudioMute allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-mute"; }

            }
            include optional=true "${gameModeStateFile}"

            window-rule {
              geometry-corner-radius 12
              clip-to-geometry true
            }

            window-rule {
              match app-id=r#"(?i)^steam$"# title="^Friends$"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title="Steam - News"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title=".* - Chat"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title="^Settings$"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title=".* - event started"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title=".* CD key"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title="^Steam - Self Updater$"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title="^Screenshot Uploader$"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^steam$"# title="^Steam Guard - Computer Authorization Required$"
              open-floating true
            }
            window-rule {
              match title="^Steam Keyboard$"
              open-floating true
            }
            window-rule {
              match title="Settings"
              open-floating true
            }
            window-rule {
              match title="splash"
              open-floating true
            }
            window-rule {
              match title="searcher"
              open-floating true
            }
            window-rule {
              match app-id=r#"(?i)^plexamp$"#
              open-floating true
            }
            window-rule {
              match app-id=r#"firefox$"# title="^Picture-in-Picture$"
              open-floating true
            }
            window-rule {
              match app-id=r#"^dev\.noctalia\.Noctalia$"#
              open-floating true
              default-column-width { fixed 1080; }
              default-window-height { fixed 920; }
            }
          '';

          niriConfigChecked =
            pkgs.runCommand "niri-config-checked"
              {
                nativeBuildInputs = [ pkgs.niri ];
              }
              ''
                niri validate --config ${niriConfig}
                cp ${niriConfig} $out
              '';

          noctaliaSettings = {
            theme = {
              mode = config.stylix.polarity;
              source = "custom";
              custom_palette = "stylix";
              templates = {
                enable_builtin_templates = false;
                builtin_ids = [ ];
                enable_community_templates = false;
                community_ids = [ ];
              };
            };
            plugins = {
              enabled = [ "sam/game-mode" ];
              auto_update = "none";
            };
            shell = {
              font_family = config.stylix.fonts.sansSerif.name;
              polkit_agent = true;
              setup_wizard_enabled = false;
              clipboard_enabled = false;
              session = {
                actions = [
                  {
                    action = "lock";
                    enabled = true;
                  }
                  {
                    action = "logout";
                    enabled = true;
                  }
                  {
                    action = "lock_and_suspend";
                    enabled = true;
                  }
                  {
                    action = "command";
                    enabled = true;
                    label = "Hibernate";
                    command = "${pkgs.systemd}/bin/systemctl hibernate";
                  }
                  {
                    action = "reboot";
                    enabled = true;
                  }
                  {
                    action = "shutdown";
                    enabled = true;
                  }
                ];
              };
            };
            bar.default = {
              position = "top";
              background_opacity = config.stylix.opacity.desktop;
              start = [
                "launcher"
                "workspaces"
              ];
              center = [ "clock" ];
              end = [
                "game-mode"
                "media"
                "tray"
                "notifications"
                "volume"
                "control-center"
                "session"
              ];
            };
            widget."game-mode".type = "sam/game-mode:bar";
            dock.enabled = false;
            notification = {
              enable_daemon = true;
              background_opacity = config.stylix.opacity.popups;
            };
            osd.background_opacity = config.stylix.opacity.popups;
            wallpaper = {
              enabled = true;
              default.path = toString config.stylix.image;
              automation.enabled = false;
            };
            backdrop.enabled = false;
            audio.enable_overdrive = false;
            lockscreen = {
              enabled = true;
              lock_before_suspend = true;
              monitors = [
                "DP-3"
                "DP-2"
              ];
            };
            lockscreen_widgets = {
              enabled = true;
              schema_version = 2;
              widget_order = [
                "lockscreen-login-box@DP-3"
                "lockscreen-login-box@DP-2"
              ];
              widget."lockscreen-login-box@DP-3" = {
                type = "login_box";
                output = "DP-3";
                cx = 1280.0;
                cy = 720.0;
                box_width = 810.0;
                box_height = 196.0;
                rotation = 0.0;
              };
              widget."lockscreen-login-box@DP-2" = {
                type = "login_box";
                output = "DP-2";
                cx = 1280.0;
                cy = 720.0;
                box_width = 810.0;
                box_height = 196.0;
                rotation = 0.0;
              };
            };
            idle.behavior.lock.enabled = false;
            idle.behavior."screen-off".enabled = false;
          };

          paletteColors = {
            mPrimary = "#${config.lib.stylix.colors.base0D}";
            mOnPrimary = "#${config.lib.stylix.colors.base00}";
            mSecondary = "#${config.lib.stylix.colors.base0E}";
            mOnSecondary = "#${config.lib.stylix.colors.base00}";
            mTertiary = "#${config.lib.stylix.colors.base0C}";
            mOnTertiary = "#${config.lib.stylix.colors.base00}";
            mError = "#${config.lib.stylix.colors.base08}";
            mOnError = "#${config.lib.stylix.colors.base00}";
            mSurface = "#${config.lib.stylix.colors.base00}";
            mOnSurface = "#${config.lib.stylix.colors.base05}";
            mSurfaceVariant = "#${config.lib.stylix.colors.base01}";
            mOnSurfaceVariant = "#${config.lib.stylix.colors.base04}";
            mOutline = "#${config.lib.stylix.colors.base03}";
            mShadow = "#${config.lib.stylix.colors.base00}";
            mHover = "#${config.lib.stylix.colors.base0C}";
            mOnHover = "#${config.lib.stylix.colors.base00}";
            terminal = {
              background = "#${config.lib.stylix.colors.base00}";
              foreground = "#${config.lib.stylix.colors.base05}";
              cursor = "#${config.lib.stylix.colors.base05}";
              cursorText = "#${config.lib.stylix.colors.base00}";
              selectionBg = "#${config.lib.stylix.colors.base02}";
              selectionFg = "#${config.lib.stylix.colors.base05}";
              normal = {
                black = "#${config.lib.stylix.colors.base00}";
                red = "#${config.lib.stylix.colors.base08}";
                green = "#${config.lib.stylix.colors.base0B}";
                yellow = "#${config.lib.stylix.colors.base0A}";
                blue = "#${config.lib.stylix.colors.base0D}";
                magenta = "#${config.lib.stylix.colors.base0E}";
                cyan = "#${config.lib.stylix.colors.base0C}";
                white = "#${config.lib.stylix.colors.base05}";
              };
              bright = {
                black = "#${config.lib.stylix.colors.base03}";
                red = "#${config.lib.stylix.colors.base08}";
                green = "#${config.lib.stylix.colors.base0B}";
                yellow = "#${config.lib.stylix.colors.base0A}";
                blue = "#${config.lib.stylix.colors.base0D}";
                magenta = "#${config.lib.stylix.colors.base0E}";
                cyan = "#${config.lib.stylix.colors.base0C}";
                white = "#${config.lib.stylix.colors.base07}";
              };
            };
          };
        in
        {
          home.sessionVariables.TERMINAL = ghosttyExecutable;
          programs.noctalia = {
            enable = true;
            systemd.enable = true;
            settings = noctaliaSettings;
            customPalettes = {
              stylix = {
                dark = paletteColors;
              };
            };
          };
          home.activation.resetNiriGameMode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            rm -f ${lib.escapeShellArg gameModeStateFile}
          '';

          wayland.systemd.target = "graphical-session.target";

          services.udiskie.enable = true;

          services.swayidle = {
            enable = true;
            systemdTargets = [ "graphical-session.target" ];
            timeouts = [
              {
                timeout = 300;
                command = "${pkgs.libnotify}/bin/notify-send -t 5000 'Locking in 5 seconds'";
              }
              {
                timeout = 305;
                command = "${noctaliaExecutable} msg session lock";
              }
              {
                timeout = 360;
                command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
                resumeCommand = monitorPowerOn;
              }
              {
                timeout = 900;
                command = "${noctaliaExecutable} msg session lock-and-suspend";
              }
            ];
            events = {
              after-resume = monitorPowerOn;
              unlock = monitorPowerOn;
            };
          };

          xdg.dataFile = {
            "noctalia/plugins/game-mode/plugin.toml".text = ''
              id = "sam/game-mode"
              name = "Game Mode"
              version = "1.0.0"
              plugin_api = 24
              author = "sam"
              license = "MIT"
              description = "Shows the active Niri game mode in the Noctalia bar."

              [[widget]]
              id = "bar"
              entry = "widget.luau"

                [widget.actions]
                middle = "none"
            '';
            "noctalia/plugins/game-mode/widget.luau".text = ''
              local stateFile = "/home/sam/.local/state/niri/game-mode.kdl"
              local enabled = false

              local function render()
                barWidget.setGlyph("device-gamepad")
                if enabled then
                  barWidget.setText("Game")
                  barWidget.setGlyphColor("primary")
                  barWidget.setTooltip("Game mode enabled")
                  barWidget.setVisible(true)
                else
                  barWidget.setVisible(false)
                end
              end

              local function refresh()
                noctalia.runAsync({ "test", "-e", stateFile }, function(result)
                  local nextEnabled = result.exitCode == 0
                  if nextEnabled ~= enabled then
                    enabled = nextEnabled
                    render()
                  end
                end)
              end

              render()
              refresh()

              function onIpc(event, payload)
                if event == "set" then
                  enabled = payload == "on"
                  render()
                end
              end
            '';
          };
          xdg.configFile = {
            "niri/config.kdl".source = niriConfigChecked;
          };
        }
      ))
    ]
  );
}
