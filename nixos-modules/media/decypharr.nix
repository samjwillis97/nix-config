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

  cfg = config.my.media.decypharr;
  stateDir = "/var/lib/decypharr";
  mediaGid = config.nixflix.globals.gids.media;

  usenetArgs = lib.optionalString cfg.usenet.enable ''
    --arg usenetHost ${lib.escapeShellArg cfg.usenet.host} \
    --arg usenetPort ${lib.escapeShellArg (toString cfg.usenet.port)} \
    --arg usenetUsername "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.usenet.usernameFile})" \
    --arg usenetPassword "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.usenet.passwordFile})" \
    --arg usenetBackbone ${lib.escapeShellArg cfg.usenet.backbone} \
    --argjson usenetSSL ${if cfg.usenet.ssl then "true" else "false"} \
    --argjson usenetMaxConnections ${toString cfg.usenet.maxConnections} \
  '';

  usenetJson =
    if cfg.usenet.enable then
      ''
        {
          providers: [
            {
              host: $usenetHost,
              port: ($usenetPort | tonumber),
              username: $usenetUsername,
              password: $usenetPassword,
              backbone: $usenetBackbone,
              ssl: $usenetSSL,
              max_connections: $usenetMaxConnections,
              priority: 1
            }
          ],
          max_connections: $usenetMaxConnections,
          processing_max_connections: $usenetMaxConnections
        }
      ''
    else
      "null";

  renderConfig = pkgs.writeShellScript "decypharr-render-config" ''
    set -eu

    install -d -m 0750 -o decypharr -g media ${lib.escapeShellArg stateDir}
    install -d -m 0750 -o decypharr -g media ${lib.escapeShellArg "${stateDir}/cache"}
    # Decypharr creates its log directory itself, so a restored or
    # root-created logs tree makes lumberjack fail to rotate the log with
    # EACCES and floods the journal. Take ownership before every start,
    # including of files created by an earlier run.
    install -d -m 0750 -o decypharr -g media ${lib.escapeShellArg "${stateDir}/logs"}
    ${pkgs.coreutils}/bin/chown -R decypharr:media ${lib.escapeShellArg "${stateDir}/logs"}
    ${pkgs.coreutils}/bin/chmod -R u+rwX ${lib.escapeShellArg "${stateDir}/logs"}
    # The DFS cleanup only removes cache metadata when the recorded size is
    # non-zero, so metadata orphaned by an older provider layout is warned
    # about every few minutes forever. Reap metadata without a data file
    # before startup; the read cache is rebuildable.
    ${pkgs.findutils}/bin/find ${lib.escapeShellArg "${stateDir}/cache"} -type f -name '*.json' -print0 |
      while IFS= read -r -d "" meta; do
        if [ ! -e "''${meta%.json}" ]; then
          ${pkgs.coreutils}/bin/rm -f "$meta"
        fi
      done
    ${pkgs.findutils}/bin/find ${lib.escapeShellArg "${stateDir}/cache"} -mindepth 1 -type d -empty -delete
    # fusermount3 refuses to mount on a directory the service user cannot
    # write to, so the mountpoint must belong to decypharr:media.
    install -d -m 0770 -o decypharr -g media ${lib.escapeShellArg cfg.mountPath}

    ${pkgs.jq}/bin/jq -n \
      --arg port ${lib.escapeShellArg (toString cfg.port)} \
      --arg bindAddress ${lib.escapeShellArg cfg.bindAddress} \
      ${usenetArgs}      --arg downloadFolder ${lib.escapeShellArg cfg.downloadFolder} \
      --arg mountPath ${lib.escapeShellArg cfg.mountPath} \
      --arg cacheDir ${lib.escapeShellArg "${stateDir}/cache"} \
      --arg diskCacheSize ${lib.escapeShellArg cfg.diskCacheSize} \
      --arg radarrHost "http://${config.nixflix.radarr.connectionAddress}:${toString config.nixflix.radarr.config.hostConfig.port}${config.nixflix.radarr.config.hostConfig.urlBase}" \
      --arg radarrToken "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.my.media.arr.radarr.apiKeyFile})" \
      --arg sonarrHost "http://${config.nixflix.sonarr.connectionAddress}:${toString config.nixflix.sonarr.config.hostConfig.port}${config.nixflix.sonarr.config.hostConfig.urlBase}" \
      --arg sonarrToken "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.my.media.arr.sonarr.apiKeyFile})" \
      --argjson mediaGid ${toString mediaGid} \
      --argjson repairEnabled ${if cfg.repair.enable then "true" else "false"} \
      --arg repairSchedule ${lib.escapeShellArg cfg.repair.schedule} \
      --argjson autoRepair ${if cfg.repair.autoRepair then "true" else "false"} \
      --argjson repairWorkers ${toString cfg.repair.workers} \
      --arg repairStopSchedule ${lib.escapeShellArg cfg.repair.stopSchedule} \
      '{
        port: $port,
        bind_address: $bindAddress,
        use_auth: true,
        download_folder: $downloadFolder,
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
        usenet: ${usenetJson},
        # Do not join the Decypharr peer-to-peer availability network; this
        # host only needs the local SABnzbd API and mount.
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
  options.my.media.decypharr = {
    enable = lib.mkEnableOption "usenet streaming via Decypharr";

    apiTokenFile = secretFileOption "Decypharr API token";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8282;
      description = "Port for Decypharr's SABnzbd API and web interface";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for Decypharr's SABnzbd API and web interface";
    };

    mountPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/decypharr";
      description = "FUSE mount point for Decypharr's usenet files";
    };

    downloadFolder = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixflix.downloadsDir}/usenet";
      defaultText = lib.literalExpression ''"''${config.nixflix.downloadsDir}/usenet"'';
      description = "Directory where Decypharr creates per-release symlink directories";
    };

    diskCacheSize = lib.mkOption {
      type = lib.types.str;
      default = "10GB";
      description = "Maximum size of Decypharr's on-disk read cache";
    };

    usenet = {
      enable = lib.mkEnableOption "Usenet streaming through Decypharr";

      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "NNTP server hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 563;
        description = "NNTP server port (563 for TLS)";
      };

      ssl = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use TLS for the NNTP connection";
      };

      backbone = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Shared article backbone identifier for provider failover";
      };

      maxConnections = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Maximum NNTP connections; use the limit allowed by the provider plan";
      };

      usernameFile = secretFileOption "Usenet provider username";
      passwordFile = secretFileOption "Usenet provider password";
    };

    repair = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Probe the Radarr/Sonarr libraries for usenet files whose articles are
          missing or whose content no longer verifies, and re-search them.
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
        '';
      };

      workers = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = ''
          Concurrent repair probes. Each probe consumes an NNTP connection from
          the same pool as streaming, so keep this low.
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
            message = "my.media.decypharr requires my.media.arr.enable: Decypharr is the download client for Radarr and Sonarr.";
          }
          {
            assertion = config.my.media.jellyfin.enable;
            message = "my.media.decypharr requires my.media.jellyfin.enable: the symlinks are consumed by Jellyfin.";
          }
          {
            assertion = cfg.usenet.enable;
            message = "my.media.decypharr requires my.media.decypharr.usenet.enable.";
          }
          {
            assertion =
              !cfg.usenet.enable
              || (
                cfg.usenet.host != ""
                && toString cfg.usenet.usernameFile != ""
                && toString cfg.usenet.passwordFile != ""
              );
            message = "my.media.decypharr.usenet requires host, usernameFile and passwordFile when enabled.";
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
          description = "Decypharr usenet gateway";
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
            user = "decypharr";
            group = "media";
            mode = "0770";
          };
        };

        systemd.services.decypharr = {
          description = "Decypharr usenet gateway";
          after = [
            "network-online.target"
            "nixflix-setup-dirs.service"
            "sops-install-secrets.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "nixflix-setup-dirs.service" ];
          wantedBy = [ "multi-user.target" ];

          # fusermount3 comes from fuse3; jq and coreutils render the config.
          # The setuid wrapper must come before the fuse3 store bin: the store
          # copy is not setuid, so fusermount3 would fail to mount. NixOS's
          # `path` option appends /bin to each entry, so pass /run/wrappers
          # rather than config.security.wrapperDir (/run/wrappers/bin).
          path = [
            "/run/wrappers"
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
            # write config with decypharr ownership.
            ExecStartPre = "+${renderConfig}";
            ExecStart = "${pkgs.decypharr}/bin/decypharr -config ${stateDir}";
            ExecStartPost = "${checkMount}";
            # `-` ignores the failure when the mount is already gone.
            ExecStopPost = "-${config.security.wrapperDir}/fusermount3 -uz ${cfg.mountPath}";

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
          torrentClients.qbittorrent.enable = lib.mkDefault false;
          downloadarr.qbittorrent.enable = lib.mkDefault false;

          downloadarr.extraClients = [
            {
              enable = true;
              name = "Decypharr Usenet";
              implementationName = "SABnzbd";
              host = "127.0.0.1";
              inherit (cfg) port;
              urlBase = "sabnzbd";
              apiKey._secret = cfg.apiTokenFile;
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
