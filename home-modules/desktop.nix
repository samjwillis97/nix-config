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
          noctaliaExecutable = lib.getExe pkgs.noctalia;
          ghosttyExecutable = lib.getExe config.programs.ghostty.package;
          firefoxExecutable = lib.getExe config.programs.firefox.package;
          monitorPowerOn = "${pkgs.niri}/bin/niri msg action power-on-monitors";

          workspaceBindings = lib.concatMapStringsSep "\n" (workspace: ''
            Mod+${workspace} allow-inhibiting=false repeat=false { focus-workspace "${workspace}"; }
            Mod+Shift+${workspace} allow-inhibiting=false repeat=false { move-window-to-workspace "${workspace}"; }
          '') workspaces;

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
              mode "2560x1440@180"
              scale 1
              position x=0 y=0
            }

            output "DP-2" {
              mode "2560x1440@180"
              scale 1
              position x=2560 y=0
            }

            ${lib.concatMapStringsSep "\n" (workspace: ''workspace "${workspace}"'') workspaces}

            layout {
              gaps 0
              default-column-width { proportion 0.5; }
              preset-column-widths {
                proportion 0.33333
                proportion 0.5
                proportion 0.66667
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
              Mod+Comma repeat=false { spawn "${noctaliaExecutable}" "msg" "settings-toggle"; }
              Mod+Shift+C repeat=false { spawn "${noctaliaExecutable}" "msg" "panel-toggle" "control-center"; }
              Mod+Ctrl+Escape allow-inhibiting=false repeat=false { spawn "${noctaliaExecutable}" "msg" "session" "lock"; }

              Mod+H allow-inhibiting=false { focus-column-left; }
              Mod+J allow-inhibiting=false { focus-window-down; }
              Mod+K allow-inhibiting=false { focus-window-up; }
              Mod+L allow-inhibiting=false { focus-column-right; }
              Mod+Shift+H allow-inhibiting=false { move-column-left; }
              Mod+Shift+J allow-inhibiting=false { move-window-down; }
              Mod+Shift+K allow-inhibiting=false { move-window-up; }
              Mod+Shift+L allow-inhibiting=false { move-column-right; }
              Mod+Ctrl+H allow-inhibiting=false { set-column-width "-10%"; }
              Mod+Ctrl+L allow-inhibiting=false { set-column-width "+10%"; }
              Mod+Ctrl+K allow-inhibiting=false { set-window-height "-10%"; }
              Mod+Ctrl+J allow-inhibiting=false { set-window-height "+10%"; }

              Mod+Space repeat=false { toggle-window-floating; }
              Mod+Shift+Space repeat=false { switch-focus-between-floating-and-tiling; }
              Mod+Shift+W repeat=false { toggle-column-tabbed-display; }
              Mod+S { consume-window-into-column; }
              Mod+V { expel-window-from-column; }
              Mod+Tab repeat=false { focus-workspace-previous; }

              Mod+Ctrl+Left allow-inhibiting=false { focus-monitor-left; }
              Mod+Ctrl+Right allow-inhibiting=false { focus-monitor-right; }
              Mod+Ctrl+Shift+Left allow-inhibiting=false { move-window-to-monitor-left; }
              Mod+Ctrl+Shift+Right allow-inhibiting=false { move-window-to-monitor-right; }
              Mod+O repeat=false { toggle-overview; }
              Mod+F repeat=false { maximize-column; }
              Mod+Shift+F repeat=false { fullscreen-window; }
              Mod+R repeat=false { switch-preset-column-width; }
              Mod+Shift+G allow-inhibiting=false repeat=false { toggle-keyboard-shortcuts-inhibit; }
              Mod+Shift+E repeat=false { quit; }
              Mod+Shift+Slash repeat=false { show-hotkey-overlay; }

              Print repeat=false { screenshot; }
              Ctrl+Print repeat=false { screenshot-screen; }
              Alt+Print repeat=false { screenshot-window; }

              XF86AudioRaiseVolume allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-up" "5"; }
              XF86AudioLowerVolume allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-down" "5"; }
              XF86AudioMute allow-when-locked=true repeat=false { spawn "${noctaliaExecutable}" "msg" "volume-mute"; }

              ${workspaceBindings}
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
              position = "bottom";
              background_opacity = config.stylix.opacity.desktop;
              start = [
                "launcher"
                "workspaces"
              ];
              center = [ "clock" ];
              end = [
                "media"
                "tray"
                "notifications"
                "volume"
                "control-center"
                "session"
              ];
            };
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
            };
            idle.behavior.lock.enabled = false;
            idle.behavior."screen-off".enabled = false;
          };

          noctaliaConfig = (pkgs.formats.toml { }).generate "noctalia-config.toml" noctaliaSettings;
          noctaliaConfigChecked =
            pkgs.runCommand "noctalia-config-checked"
              {
                nativeBuildInputs = [ pkgs.noctalia ];
              }
              ''
                ${noctaliaExecutable} config validate ${noctaliaConfig}
                cp ${noctaliaConfig} $out
              '';

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
          };
          noctaliaPalette = (pkgs.formats.json { }).generate "noctalia-palette.json" {
            dark = paletteColors;
          };
        in
        {
          home.packages = [ pkgs.noctalia ];
          home.sessionVariables.TERMINAL = ghosttyExecutable;

          wayland.systemd.target = "graphical-session.target";

          systemd.user.services.noctalia = {
            Unit = {
              Description = "Noctalia desktop shell";
              After = [ "graphical-session.target" ];
              PartOf = [ "graphical-session.target" ];
              "X-Restart-Triggers" = [
                "${noctaliaConfigChecked}"
                "${noctaliaPalette}"
              ];
            };
            Service = {
              ExecStart = noctaliaExecutable;
              Restart = "on-failure";
              RestartSec = 1;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

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

          xdg.configFile = {
            "niri/config.kdl".source = niriConfigChecked;
            "noctalia/config.toml".source = noctaliaConfigChecked;
            "noctalia/palettes/stylix.json".source = noctaliaPalette;
          };
        }
      ))
    ]
  );
}
