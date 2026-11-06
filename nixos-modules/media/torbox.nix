{
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

  cfg = config.my.media.torbox;
  stateDir = "/var/lib/decypharr";
  mediaGid = config.nixflix.globals.gids.media;

  renderConfig = pkgs.writeShellScript "decypharr-render-config" ''
    set -eu

    install -d -m 0750 -o decypharr -g media ${lib.escapeShellArg stateDir}
    install -d -m 0750 -o decypharr -g media ${lib.escapeShellArg "${stateDir}/cache"}
    install -d -m 0755 -o root -g root ${lib.escapeShellArg cfg.mountPath}

    ${pkgs.jq}/bin/jq -n \
      --arg port ${lib.escapeShellArg (toString cfg.port)} \
      --arg downloadFolder ${lib.escapeShellArg cfg.downloadFolder} \
      --arg mountPath ${lib.escapeShellArg cfg.mountPath} \
      --arg cacheDir ${lib.escapeShellArg "${stateDir}/cache"} \
      --arg diskCacheSize ${lib.escapeShellArg cfg.diskCacheSize} \
      --arg apiKey "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.apiKeyFile})" \
      --arg radarrHost "http://${config.nixflix.radarr.connectionAddress}:${toString config.nixflix.radarr.config.hostConfig.port}${config.nixflix.radarr.config.hostConfig.urlBase}" \
      --arg radarrToken "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.my.media.arr.radarr.apiKeyFile})" \
      --arg sonarrHost "http://${config.nixflix.sonarr.connectionAddress}:${toString config.nixflix.sonarr.config.hostConfig.port}${config.nixflix.sonarr.config.hostConfig.urlBase}" \
      --arg sonarrToken "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.my.media.arr.sonarr.apiKeyFile})" \
      --argjson downloadUncached ${if cfg.cachedOnly then "false" else "true"} \
      --argjson mediaGid ${toString mediaGid} \
      --argjson repairEnabled ${if cfg.repair.enable then "true" else "false"} \
      --arg repairSchedule ${lib.escapeShellArg cfg.repair.schedule} \
      --argjson autoRepair ${if cfg.repair.autoRepair then "true" else "false"} \
      --argjson repairWorkers ${toString cfg.repair.workers} \
      --arg repairStopSchedule ${lib.escapeShellArg cfg.repair.stopSchedule} \
      '{
        port: $port,
        bind_address: "127.0.0.1",
        use_auth: true,
        download_folder: $downloadFolder,
        debrids: [
          {
            provider: "torbox",
            name: "TorBox",
            api_key: $apiKey,
            download_uncached: $downloadUncached
          }
        ],
        mount: {
          type: "dfs",
          mount_path: $mountPath,
          dfs: {
            cache_dir: $cacheDir,
            disk_cache_size: $diskCacheSize,
            cache_expiry: "24h",
            uid: 0,
            gid: $mediaGid,
            umask: "002"
          }
        },
        arrs: [
          {
            name: "radarr",
            host: $radarrHost,
            token: $radarrToken,
            download_action: "symlink"
          },
          {
            name: "sonarr",
            host: $sonarrHost,
            token: $sonarrToken,
            download_action: "symlink"
          }
        ],
        default_download_action: "symlink",
        # Do not join the Decypharr peer-to-peer availability network; this host
        # only needs the local qBittorrent API and mount.
        hearsay: {
          disabled: true
        },
        repair: {
          enabled: $repairEnabled,
          source: "arr",
          schedule: $repairSchedule,
          workers: $repairWorkers,
          strategy: "per_entry",
          recheck_interval: "168h",
          auto_repair: $autoRepair,
          arrs: [ "radarr", "sonarr" ],
          verify_content: false,
          stop_schedule: $repairStopSchedule
        }
      }' > ${lib.escapeShellArg "${stateDir}/config.json"}

    ${pkgs.jq}/bin/jq -n \
      --arg token "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.apiTokenFile})" \
      '{ api_token: $token, token_only: true }' > ${lib.escapeShellArg "${stateDir}/auth.json"}

    ${pkgs.coreutils}/bin/chown decypharr:media \
      ${lib.escapeShellArg "${stateDir}/config.json"} \
      ${lib.escapeShellArg "${stateDir}/auth.json"}
    ${pkgs.coreutils}/bin/chmod 0600 \
      ${lib.escapeShellArg "${stateDir}/config.json"} \
      ${lib.escapeShellArg "${stateDir}/auth.json"}
  '';

  checkMount = pkgs.writeShellScript "decypharr-check-mount" ''
    set -eu

    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.gnugrep}/bin/grep -qF " ${cfg.mountPath} " /proc/mounts; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done

    echo "decypharr did not mount ${cfg.mountPath}" >&2
    exit 1
  '';
in
{
  options.my.media.torbox = {
    enable = lib.mkEnableOption "TorBox media cache via Decypharr";

    apiKeyFile = secretFileOption "TorBox API key";
    apiTokenFile = secretFileOption "Decypharr API token";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8282;
      description = "Port for Decypharr's qBittorrent API and web interface";
    };

    mountPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/decypharr";
      description = "FUSE mount point for Decypharr's TorBox files";
    };

    downloadFolder = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixflix.downloadsDir}/torrent";
      defaultText = lib.literalExpression ''"''${config.nixflix.downloadsDir}/torrent"'';
      description = "Directory where Decypharr creates per-release symlink directories";
    };

    cachedOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only submit releases that TorBox already has cached";
    };

    diskCacheSize = lib.mkOption {
      type = lib.types.str;
      default = "10GB";
      description = "Maximum size of Decypharr's on-disk read cache";
    };

    repair = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Probe the Radarr/Sonarr libraries for files whose TorBox link no
          longer resolves and re-search them.

          TorBox expires cached items after 30 days without a download, so a
          library built from it will develop broken files. This is the
          automatic re-fetch path.
        '';
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "0 4 * * 0";
        description = "Cron expression for the repair sweep (default: weekly, Sunday 04:00).";
      };

      autoRepair = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Delete broken files through the Arr and trigger a new search.

          With `cachedOnly = true`, the new search can only re-add a release
          that TorBox has cached again; otherwise the Arr falls back to another
          release.
        '';
      };

      workers = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = ''
          Concurrent repair probes. Keep this low for TorBox: each probe spends
          from the account-wide `requestdl` budget, which is much tighter than
          the documented API rate limit.
        '';
      };

      stopSchedule = lib.mkOption {
        type = lib.types.str;
        default = "06:00";
        description = "Clock time, cron expression or duration at which an in-progress sweep is stopped.";
      };
    };

    openFirewall = lib.mkEnableOption "open the Decypharr port, independent of ingress";

    ingress.enable = lib.mkEnableOption "ingress route for the Decypharr web interface";
  };

  config = lib.mkIf (config.my.media.enable && cfg.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.my.media.arr.enable;
            message = "my.media.torbox requires my.media.arr.enable: Decypharr is the download client for Radarr and Sonarr.";
          }
          {
            assertion = config.my.media.jellyfin.enable;
            message = "my.media.torbox requires my.media.jellyfin.enable: the symlinks are consumed by Jellyfin.";
          }
        ];

        # Decypharr mounts DFS with allow_other so the jellyfin, radarr and
        # sonarr users can read it. Without user_allow_other, fusermount3 refuses
        # the mount and Decypharr continues without storage.
        programs.fuse.userAllowOther = true;

        users.users.decypharr = {
          isSystemUser = true;
          uid = 323;
          group = "media";
          home = stateDir;
          createHome = false;
          description = "Decypharr media gateway";
        };

        systemd.tmpfiles.settings."10-decypharr" = {
          "${stateDir}".d = {
            user = "decypharr";
            group = "media";
            mode = "0750";
          };
          "${stateDir}/cache".d = {
            user = "decypharr";
            group = "media";
            mode = "0750";
          };
          "${cfg.mountPath}".d = {
            user = "root";
            group = "root";
            mode = "0755";
          };
        };

        systemd.services.decypharr = {
          description = "Decypharr TorBox media gateway";
          after = [
            "network-online.target"
            "nixflix-setup-dirs.service"
            "sops-install-secrets.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "nixflix-setup-dirs.service" ];
          wantedBy = [ "multi-user.target" ];

          # fusermount3 comes from fuse3; jq and coreutils render the config.
          path = [
            pkgs.bash
            pkgs.coreutils
            pkgs.fuse3
            pkgs.gnugrep
            pkgs.jq
          ];

          environment.HOME = stateDir;

          serviceConfig = {
            Type = "simple";
            User = "decypharr";
            Group = "media";
            WorkingDirectory = stateDir;

            # `+` runs the renderer as root so it can read the SOPS files and
            # write root-owned secrets with decypharr ownership.
            ExecStartPre = "+${renderConfig}";
            ExecStart = "${pkgs.decypharr}/bin/decypharr -config ${stateDir}";
            ExecStartPost = "${checkMount}";
            # `-` ignores the failure when the mount is already gone.
            ExecStopPost = "-${pkgs.fuse3}/bin/fusermount3 -uz ${cfg.mountPath}";

            Restart = "on-failure";
            RestartSec = 10;
            TimeoutStartSec = 120;
            TimeoutStopSec = 90;
            UMask = "0002";
            LimitNOFILE = 65536;

            # NoNewPrivileges is deliberately not set: fusermount3 is setuid root
            # and the service needs it to create the FUSE mount.
          };
        };

        nixflix = {
          # Decypharr replaces qBittorrent as the download client.
          torrentClients.qbittorrent.enable = lib.mkDefault false;
          downloadarr.qbittorrent.enable = lib.mkDefault false;

          downloadarr.extraClients = [
            {
              enable = true;
              name = "Decypharr";
              implementationName = "qBittorrent";
              host = "127.0.0.1";
              inherit (cfg) port;
              username = "decypharr";
              password = {
                _secret = cfg.apiTokenFile;
              };
              dependencies = [ "decypharr.service" ];
              categories = {
                radarr = "radarr";
                sonarr = "sonarr";
                sonarr-anime = "sonarr-anime";
                lidarr = "lidarr";
                prowlarr = "prowlarr";
              };
            }
          ];
        };
      }

      (lib.mkIf cfg.openFirewall {
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      })

      (lib.mkIf cfg.ingress.enable {
        my.ingress.routes.decypharr = {
          upstream = "http://127.0.0.1:${toString cfg.port}";
          websockets = true;
        };
      })
    ]
  );
}
