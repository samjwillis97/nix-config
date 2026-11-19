{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  pathOrString =
    with lib.types;
    oneOf [
      path
      str
    ];

  secretFileOption =
    name:
    lib.mkOption {
      type = pathOrString;
      description = "Path to the file containing the ${name}";
    };
in
{
  options.my.media.jellyfin = {
    enable = lib.mkEnableOption "jellyfin media server";

    apiKeyFile = secretFileOption "jellyfin API key";

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.path);
      default = { };
      description = "Users to create for jellyfin, with passwords stored in files";
    };

    adminPasswordFile = secretFileOption "jellyfin admin password";

    xtream = {
      baseUrlFile = secretFileOption "Base URL for Xtream plugin";
      usernameFile = secretFileOption "Username for Xtream plugin";
      passwordFile = secretFileOption "Password for Xtream plugin";

      channels = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Channels to enable for Xtream plugin, grouped by group ID";
      };
    };

    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 8096;
      description = "Port for jellyfin to listen on";
    };

    openFirewall = lib.mkEnableOption "open firewall for jellyfin, independent of ingress route";

    ingress.enable = lib.mkEnableOption "jellyfin ingress route";
  };

  config = lib.mkIf (config.my.media.enable && config.my.media.jellyfin.enable) (
    lib.mkMerge [
      {
        nixflix.jellyfin = {
          enable = true;
          openFirewall = config.my.media.jellyfin.openFirewall;

          apiKey = {
            _secret = config.my.media.jellyfin.apiKeyFile;
          };

          users = {
            admin = {
              password = {
                _secret = config.my.media.jellyfin.adminPasswordFile;
              };
              policy = {
                isAdministrator = true;
              };
            };
          }
          // (builtins.mapAttrs (_name: user: {
            password = {
              _secret = user.password;
            };
            policy = {
              isAdministrator = false;
            };
          }) config.my.media.jellyfin.users);

          network = {
            internalHttpPort = config.my.media.jellyfin.httpPort;
          }
          // lib.optionalAttrs config.my.media.jellyfin.openFirewall {
            # nixflix 4.0 binds Jellyfin to loopback by default. Opening the
            # firewall for Jellyfin means direct LAN clients, so bind all
            # interfaces in that case.
            localNetworkAddresses = [ "0.0.0.0" ];
          };

          # nixflix disables Jellyfin real-time monitoring when the arr
          # Jellyfin notifications are enabled, leaving new imports to the
          # scheduled scan. Watch the library paths as well so a successful
          # Radarr/Sonarr import appears promptly.
          #
          # Decypharr serves files through a FUSE mount with multi-second
          # read stalls, so Jellyfin's first trickplay image takes longer
          # than its 20-second watchdog and every job is killed. Both
          # features are unused here, so disable them outright; the
          # during-scan flags stay false in case one is re-enabled.
          libraries = {
            Movies = {
              enableRealtimeMonitor = lib.mkDefault true;
              enableChapterImageExtraction = lib.mkDefault false;
              enableTrickplayImageExtraction = lib.mkDefault false;
              extractChapterImagesDuringLibraryScan = lib.mkDefault false;
              extractTrickplayImagesDuringLibraryScan = lib.mkDefault false;
            };
            Shows = {
              enableRealtimeMonitor = lib.mkDefault true;
              enableChapterImageExtraction = lib.mkDefault false;
              enableTrickplayImageExtraction = lib.mkDefault false;
              extractChapterImagesDuringLibraryScan = lib.mkDefault false;
              extractTrickplayImagesDuringLibraryScan = lib.mkDefault false;
            };
          };

          system = {
            libraryMonitorDelay = lib.mkDefault 10;

            pluginRepositories = {
              "Jellyfin.XTream" = {
                enabled = true;
                url = "https://kevinjil.github.io/Jellyfin.Xtream/repository.json";
                hash = "sha256-xneshIL76OaYLnFR0Cs3ysbAgS5jvN/4yzoFE5PE3wY=";
              };
            };
          };

          plugins = {
            "Jellyfin Xtream" = {
              package = inputs.nixflix.lib.jellyfinPlugins.fromRepo {
                version = "0.8.1.0";
                hash = "sha256-mcLeVW7nQdaqMYf2UOQSUMtn7zOBi6jOZ35TCTR35vA=";
              };
              config = {
                BaseUrl._secret = config.my.media.jellyfin.xtream.baseUrlFile;
                Username._secret = config.my.media.jellyfin.xtream.usernameFile;
                Password._secret = config.my.media.jellyfin.xtream.passwordFile;

                LiveTv = config.my.media.jellyfin.xtream.channels;

                IsCatchupVisible = false;
                IsSeriesVisible = false;
                IsVodVisible = false;
                IsTmdbVodOverride = true;
              };
            };
          };
        };
      }

      {
        # nixflix enables the Emby/Jellyfin connection and its triggers but
        # leaves Update Library to the arr schema/default. Pin it so an arr
        # import always asks Jellyfin to scan the affected path.
        nixflix.notif.jellyfin.updateLibrary = lib.mkDefault true;
      }

      # nixflix allows 5 minutes, but a switch on teeny restarts Jellyfin under
      # load and it can still be initialising (HTTP 503) at that point. Being
      # killed mid-start restarts it from scratch, so the activation never ends.
      #
      # nixflix's readiness check gives up after 240 polls, about 6.5 minutes,
      # and a cold start during a switch has taken 6.5 to 7.5 minutes. Wait in
      # jellyfin.service until the startup API answers, bounded only by
      # TimeoutStartSec. The API config units are otherwise ordered only after
      # units that a switch does not restart, so they ran their own 240-poll
      # wait alongside Jellyfin's restart and gave up; order them after it.
      #
      # When a nixpkgs bump restarts the whole media stack, a cold start has
      # run past 10 minutes on teeny's 4 CPUs, so the 600-second timeout
      # killed it and the restart from scratch outlived the deploy. Killing a
      # slow start never helps, so the bound only catches a hung Jellyfin.
      #
      # jellyfin-plugins stops and restarts Jellyfin whenever a plugin's store
      # path changes, which a nixpkgs bump does, and waits for it within its
      # own 300-second timeout. A restart takes about 6 minutes, so give it
      # the same bound.
      {
        systemd.services.jellyfin-plugins.serviceConfig.TimeoutStartSec = lib.mkForce 1800;

        systemd.services.jellyfin = {
          before = [
            "jellyfin-setup-wizard.service"
            "jellyfin-system-config.service"
            "jellyfin-metadata-config.service"
            "jellyfin-plugins.service"
            "jellyfin-branding-config.service"
            "jellyfin-libraries.service"
            "jellyfin-livetv.service"
            "jellyfin-users-config.service"
          ];

          serviceConfig = {
            TimeoutStartSec = lib.mkForce 1800;
            ExecStartPost = lib.mkBefore [
              (pkgs.writeShellScript "jellyfin-wait-for-startup" ''
                base="http://127.0.0.1:${toString config.my.media.jellyfin.httpPort}"
                status() {
                  ${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$base/$1" || true
                }
                until [ "$(status System/Info/Public)" = 200 ] &&
                  [[ "$(status Startup/Configuration)" =~ ^(200|204|401)$ ]]; do
                  ${pkgs.coreutils}/bin/sleep 2
                done
              '')
            ];
          };
        };
      }

      (lib.mkIf config.my.media.jellyfin.ingress.enable {
        my.ingress.routes.jellyfin = {
          upstream = "http://127.0.0.1:${toString config.my.media.jellyfin.httpPort}";
          websockets = true;
        };
      })
    ]
  );
}
