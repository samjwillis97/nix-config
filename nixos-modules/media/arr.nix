{
  config,
  lib,
  pkgs,
  unstable,
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

  cfg = config.my.media.arr;
in
{
  options.my.media.arr = {
    enable = lib.mkEnableOption "Radarr, Sonarr, Prowlarr and Seerr";

    radarr.apiKeyFile = secretFileOption "Radarr API key";
    sonarr.apiKeyFile = secretFileOption "Sonarr API key";
    prowlarr.apiKeyFile = secretFileOption "Prowlarr API key";
    seerr.apiKeyFile = secretFileOption "Seerr API key";

    adminPasswordFile = secretFileOption "shared password for the Radarr, Sonarr and Prowlarr web interfaces";

    openFirewall = lib.mkEnableOption "open firewall ports for the arr services, independent of ingress";

    ingress = {
      enable = lib.mkEnableOption "expose Seerr over ingress";
      exposeAdmin = lib.mkEnableOption "expose Radarr, Sonarr and Prowlarr over ingress";
    };
  };

  config = lib.mkIf (config.my.media.enable && cfg.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.my.media.jellyfin.enable;
            message = "my.media.arr requires my.media.jellyfin.enable: Seerr authenticates against Jellyfin.";
          }
        ];

        nixflix = {
          radarr = {
            enable = true;
            inherit (cfg) openFirewall;
            config = {
              apiKey._secret = cfg.radarr.apiKeyFile;
              hostConfig = {
                password._secret = cfg.adminPasswordFile;
                # The repository uses my.ingress rather than nixflix's own reverse
                # proxy, so nixflix would otherwise leave these on 0.0.0.0.
                bindAddress = lib.mkDefault "127.0.0.1";
              };
            };
          };

          sonarr = {
            enable = true;
            inherit (cfg) openFirewall;
            config = {
              apiKey._secret = cfg.sonarr.apiKeyFile;
              hostConfig = {
                password._secret = cfg.adminPasswordFile;
                bindAddress = lib.mkDefault "127.0.0.1";
              };
            };
          };

          prowlarr = {
            enable = true;
            inherit (cfg) openFirewall;
            config = {
              apiKey._secret = cfg.prowlarr.apiKeyFile;
              hostConfig = {
                password._secret = cfg.adminPasswordFile;
                bindAddress = lib.mkDefault "127.0.0.1";
              };
            };
          };

          seerr = {
            enable = true;
            # The nixpkgs Seerr is older than the 3.5.0 that nixflix requires.
            package = unstable.seerr;
            inherit (cfg) openFirewall;
            apiKey._secret = cfg.seerr.apiKeyFile;
          };
        };

        # Seerr only sets HOST when nixflix's own reverse proxy is enabled.
        systemd.services = {
          seerr.environment.HOST = lib.mkDefault "127.0.0.1";

          # Seerr's first start runs database migrations and can take longer
          # than the 60 seconds nixflix's setup script waits. Wait for the API
          # first so seerr-setup does not fail on a slow host.
          seerr-wait-for-api = {
            description = "Wait for the Seerr API";
            after = [ "seerr.service" ];
            requires = [ "seerr.service" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = 360;
            };

            script = ''
              for _ in $(${pkgs.coreutils}/bin/seq 1 300); do
                if ${pkgs.curl}/bin/curl -sf "http://${config.nixflix.seerr.connectionAddress}:${toString config.nixflix.seerr.port}/api/v1/status" >/dev/null 2>&1; then
                  exit 0
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done

              echo "Seerr API did not become ready" >&2
              exit 1
            '';
          };

          seerr-setup = {
            after = [ "seerr-wait-for-api.service" ];
            requires = [ "seerr-wait-for-api.service" ];
          };
        };
      }

      (lib.mkIf cfg.ingress.enable {
        my.ingress.routes.seerr = {
          upstream = "http://127.0.0.1:${toString config.nixflix.seerr.port}";
          websockets = true;
        };
      })

      (lib.mkIf cfg.ingress.exposeAdmin {
        my.ingress.routes = {
          radarr = {
            upstream = "http://127.0.0.1:${toString config.nixflix.radarr.config.hostConfig.port}";
            websockets = true;
          };
          sonarr = {
            upstream = "http://127.0.0.1:${toString config.nixflix.sonarr.config.hostConfig.port}";
            websockets = true;
          };
          prowlarr = {
            upstream = "http://127.0.0.1:${toString config.nixflix.prowlarr.config.hostConfig.port}";
            websockets = true;
          };
        };
      })
    ]
  );
}
