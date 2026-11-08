{
  config,
  lib,
  secretModules,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    secretModules.tailscale
    secretModules.cloudflared
    secretModules.media
    secretModules.media-backup
    secretModules.supernote
    secretModules.amp
    secretModules.buildkite
  ];

  config = {
    boot.plymouth.enable = lib.mkForce false;

    networking = {
      nameservers = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      networkmanager.enable = true;
    };
    # Keep Nix builds from monopolizing this shared media server.
    nix.settings = {
      max-jobs = 1;
      cores = 2;
    };

    systemd = {
      enableEmergencyMode = false;
      services = {
        nix-daemon.serviceConfig = {
          CPUWeight = 50;
          IOWeight = 50;
        };
        # Seerr is loopback-only by default; expose it on the LAN as well.
        seerr.environment.HOST = lib.mkForce "0.0.0.0";

        # nixflix's downloadarr also tries to add the Decypharr Usenet
        # SABnzbd client to Prowlarr. Prowlarr rejects that client with HTTP
        # 400 and does not need a download client; Radarr/Sonarr still get it.
        prowlarr-downloadclients = {
          enable = false;
          wantedBy = lib.mkForce [ ];
        };
      };
    };

    my = {
      users = [ "sam" ];
      dix.enable = true;
      actual = {
        enable = true;
        ingress.enable = true;
      };

      amp = {
        enable = true;
        runner = {
          enable = true;
          desktop.enable = true;
          apiKeyFile = config.sops.secrets."amp-api-key".path;
          githubTokenFile = config.sops.secrets."amp-github-token".path;
        };
      };

      observability = {
        logs = {
          enable = true;
          retention = "14d";
          mcp.enable = true;
        };
        probe.enable = true;
        triage = {
          enable = true;
          runnerDir = "/var/lib/amp/code/code/github.com/samjwillis97/nix-config";
        };
      };

      buildkite = {
        enable = true;
        tokenFile = config.sops.secrets."buildkite-agent-token".path;
        agents.teeny.tags = {
          queue = "linux-selfhosted";
          host = "teeny";
        };
      };

      supernote = {
        enable = true;
        ingress.enable = true;
        secrets = {
          mysqlRootPassword = "supernote/mysql-root-password";
          mysqlPassword = "supernote/mysql-password";
          redisPassword = "supernote/redis-password";
        };
      };

      media = {
        enable = true;

        jellyfin = {
          enable = true;
          apiKeyFile = config.sops.secrets."jellyfin/api-key".path;
          adminPasswordFile = config.sops.secrets."jellyfin/admin-password".path;
          openFirewall = true;
          ingress.enable = true;

          # Automatically map the users from secrets to the jellyfin configuration. The secrets are expected to be in the format "jellyfin/users/<username>/password".
          users =
            lib.mapAttrs'
              (name: _value: {
                name = builtins.elemAt (builtins.match "jellyfin/users/(.*)/password" name) 0;
                value = {
                  password = config.sops.secrets.${name}.path;
                };
              })
              (
                lib.filterAttrs (
                  _name: _value: builtins.match "jellyfin/users/(.*)/password" _name != null
                ) config.sops.secrets
              );

          xtream = {
            baseUrlFile = config.sops.secrets."xtream/base-url".path;
            usernameFile = config.sops.secrets."xtream/username".path;
            passwordFile = config.sops.secrets."xtream/password".path;

            channels = {
              "234" = [
                "441368"
                "441313"
                "441312"
                "441311"
                "441310"
                "441309"
                "441308"
                "441307"
                "441306"
                "441305"
                "441304"
                "441360"
                "441302"
                "441301"
              ];

              "303" = [
                "588072"
                "588070"
                "588067"
                "588066"
                "2043935"
                "588063"
                "707004"
                "1744758"
              ];

              "1731" = [
                "1290246"
                "1290245"
                "1290247"
                "1290248"
              ];

              "1984" = [
                "1537642"
                "1537641"
                "1537640"
                "1537637"
              ];
            };
          };
        };

        arr = {
          enable = true;
          radarr.apiKeyFile = config.sops.secrets."radarr/api-key".path;
          sonarr.apiKeyFile = config.sops.secrets."sonarr/api-key".path;
          prowlarr.apiKeyFile = config.sops.secrets."prowlarr/api-key".path;
          seerr.apiKeyFile = config.sops.secrets."seerr/api-key".path;
          adminPasswordFile = config.sops.secrets."arr/admin-password".path;
          # Seerr is the user-facing request UI. The admin UIs are exposed
          # directly on the LAN for configuration, but not through the
          # Cloudflare ingress.
          ingress.enable = true;
          openFirewall = true;
        };

        decypharr = {
          enable = true;
          apiTokenFile = config.sops.secrets."decypharr/api-token".path;
          # The web interface can delete downloads. Expose it on the LAN for
          # configuration, but not through the Cloudflare ingress.
          ingress.enable = false;
          openFirewall = true;
          bindAddress = "0.0.0.0";

          usenet = {
            enable = true;
            host = "news.newshosting.com";
            backbone = "omicron";
            maxConnections = 20;
            usernameFile = config.sops.secrets."newshosting/username".path;
            passwordFile = config.sops.secrets."newshosting/password".path;
          };
        };

        backup = {
          enable = true;
          # Replace CHANGE_ME_BUCKET with the B2 bucket name before deploying.
          repository = "b2:CHANGE_ME_BUCKET:teeny";
          b2AccountIdFile = config.sops.secrets."b2/account-id".path;
          b2AccountKeyFile = config.sops.secrets."b2/application-key".path;
          passwordFile = config.sops.secrets."restic/password".path;
        };
      };

      cloudflared = {
        enable = true;
        connector = {
          enable = true;
          tokenFile = config.sops.secrets."cloudflared-token".path;
        };
      };

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };

      deploy-rs = {
        enable = true;
        githubActions.enable = true;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2FeFN6YQEUr22lJCeuQHcDawLuAPnoizlZLJOwhch4 sam@williscloud.org"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYyMM/qTTLsXdPvvfkhdufg9gLYOI2y8d1oDpAgI0ft samjwillis97@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+XxL2uM1FT0dR3T5cOJxJd+9luPMctdZd+O2LlJsRk sam@Sams-MacBook-Air.local"
          # Deploy RS
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZUYj/cMiEqPoxH7Uut5VS9Phl2dtCWMOxKf8YyCuY/ sam@williscloud.org"
        ];
      };
    };

    nixflix = {
      radarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";
      sonarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";
      prowlarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";

      # The TRaSH 4K profiles include 1080p/720p fallbacks, so a single
      # Radarr/Sonarr instance can prefer 4K and still grab HD when needed.
      recyclarr = {
        enable = true;
        radarrQuality = "4K";
        sonarrQuality = "4K";
      };

      # Sonarr has no season-vs-episode weight. The TRaSH "Season Pack"
      # custom format scores full-season releases at +10, which also makes a
      # pack count as an upgrade for episodes already on disk. Sonarr still
      # requires every episode in the season to have aired, and quality still
      # ranks above custom-format score.
      recyclarr.config.sonarr.sonarr.custom_formats = [
        {
          trash_ids = [ "3bc5f395426614e155e585a2f056cdf1" ]; # Season Pack
          assign_scores_to = [
            {
              trash_id = "dfa5eaae7894077ad6449169b6eb03e0"; # WEB-2160p (Alternative)
              score = 10;
            }
          ];
        }
      ];

      # Keep Seerr on the combined 4K profiles. These remain the default
      # (non-4K) instances; the profiles handle the 4K-to-1080p fallback.
      seerr = {
        radarr.Radarr = {
          apiKey = config.nixflix.radarr.config.apiKey;
          activeProfileName = "[SQP] SQP-1 (2160p)";
          isDefault = true;
        };
        sonarr.Sonarr = {
          apiKey = config.nixflix.sonarr.config.apiKey;
          activeProfileName = "WEB-2160p (Alternative)";
          isDefault = true;
        };
      };

      # The Prowlarr reconciler deletes indexers that are not listed here on
      # every deploy. Keep the indexer identity out of this public repo: use
      # the generic Newznab schema and read the base URL and API key from
      # SOPS at runtime.
      prowlarr.config.indexers = [
        {
          name = "Usenet Indexer";
          schemaName = "Generic Newznab";
          baseUrl._secret = config.sops.secrets."usenet-indexer/base-url".path;
          apiKey._secret = config.sops.secrets."usenet-indexer/api-key".path;
        }
      ];
    };

  };

}
