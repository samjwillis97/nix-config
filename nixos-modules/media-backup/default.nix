{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media.backup;

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

  nixflix = config.nixflix or { };
  sops = config.sops or { };

  jellyfinDataDir = "${nixflix.jellyfin.dataDir or "/var/lib/jellyfin"}/data";
  jellyfinUser = nixflix.jellyfin.user or "jellyfin";
  jellyfinGroup = nixflix.jellyfin.group or "media";

  defaultPaths = [
    (nixflix.jellyfin.dataDir or "/var/lib/jellyfin")
    (nixflix.seerr.dataDir or "/var/lib/seerr")
    (nixflix.radarr.dataDir or "/var/lib/radarr")
    (nixflix.sonarr.dataDir or "/var/lib/sonarr")
    (nixflix.prowlarr.dataDir or "/var/lib/prowlarr")
    (nixflix.mediaDir or "/data/media")
    (nixflix.downloadsDir or "/data/downloads")
  ];

  sopsPath = lib.optional (cfg.sopsKeyFile != null) cfg.sopsKeyFile;

  stagingDir = "/run/media-backup";
  postgresStaging = "${stagingDir}/postgres";
  jellyfinStaging = "${stagingDir}/jellyfin";
  decypharrStaging = "${stagingDir}/decypharr";

  postgres = config.services.postgresql.finalPackage;

  excludePaths = [
    "${jellyfinDataDir}/*.db"
    "${jellyfinDataDir}/*.db-*"
    "${nixflix.jellyfin.dataDir or "/var/lib/jellyfin"}/log"
    "${nixflix.radarr.dataDir or "/var/lib/radarr"}/logs"
    "${nixflix.radarr.dataDir or "/var/lib/radarr"}/MediaCover"
    "${nixflix.radarr.dataDir or "/var/lib/radarr"}/Backups"
    "${nixflix.sonarr.dataDir or "/var/lib/sonarr"}/logs"
    "${nixflix.sonarr.dataDir or "/var/lib/sonarr"}/MediaCover"
    "${nixflix.sonarr.dataDir or "/var/lib/sonarr"}/Backups"
    "${nixflix.prowlarr.dataDir or "/var/lib/prowlarr"}/logs"
    "${nixflix.prowlarr.dataDir or "/var/lib/prowlarr"}/MediaCover"
    "${nixflix.prowlarr.dataDir or "/var/lib/prowlarr"}/Backups"
  ];

  backupPaths = [
    postgresStaging
    jellyfinStaging
    decypharrStaging
  ]
  ++ cfg.paths
  ++ sopsPath;

  backupPathLines = lib.concatMapStrings (path: "  ${lib.escapeShellArg path}\n") backupPaths;

  excludeFlags = lib.concatMapStrings (path: " --exclude ${lib.escapeShellArg path}") excludePaths;

  credentials = ''
    export B2_ACCOUNT_ID="$(cat "$CREDENTIALS_DIRECTORY/b2-account-id")"
    export B2_ACCOUNT_KEY="$(cat "$CREDENTIALS_DIRECTORY/b2-account-key")"
    export RESTIC_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/restic-password")"
    export RESTIC_CACHE_DIR=/var/cache/restic-media
    export RESTIC_REPOSITORY=${lib.escapeShellArg cfg.repository}
  '';

  backupScript = pkgs.writeShellScript "media-backup" ''
    set -euo pipefail
    ${credentials}

    install -d -m 0700 ${stagingDir} ${postgresStaging} ${jellyfinStaging} ${decypharrStaging}
    rm -f ${postgresStaging}/*.dump
    rm -f ${jellyfinStaging}/*.db

    ${lib.concatMapStrings (db: ''
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${postgres}/bin/pg_dump \
        --format=custom \
        --dbname=${lib.escapeShellArg db} \
        > ${lib.escapeShellArg "${postgresStaging}/${db}.dump"}
    '') cfg.postgresDatabases}

    # SQLite's online backup API produces a consistent copy while Jellyfin is
    # running. The live database files are excluded from the restic backup.
    for db in ${lib.escapeShellArg jellyfinDataDir}/*.db; do
      [ -e "$db" ] || continue
      ${pkgs.sqlite}/bin/sqlite3 -cmd ".timeout 30000" "$db" ".backup '${jellyfinStaging}/$(basename "$db")'"
    done

    # Decypharr's append-only stores have no online backup API. Stop it only
    # while copying the small release index, then start it again.
    restart_decypharr=false
    if ${pkgs.systemd}/bin/systemctl is-active --quiet decypharr.service; then
      ${pkgs.systemd}/bin/systemctl stop decypharr.service
      restart_decypharr=true
    fi
    cleanup_decypharr() {
      if [ "$restart_decypharr" = true ]; then
        ${pkgs.systemd}/bin/systemctl start decypharr.service || true
      fi
    }
    trap cleanup_decypharr EXIT

    rm -rf ${decypharrStaging}/db ${decypharrStaging}/usenet
    if [ -d ${lib.escapeShellArg cfg.decypharrStateDir}/db ]; then
      cp -a ${lib.escapeShellArg cfg.decypharrStateDir}/db ${decypharrStaging}/
    fi
    if [ -d ${lib.escapeShellArg cfg.decypharrStateDir}/usenet ]; then
      cp -a ${lib.escapeShellArg cfg.decypharrStateDir}/usenet ${decypharrStaging}/
    fi

    cleanup_decypharr
    trap - EXIT

    all_paths=(
    ${backupPathLines}
    )

    existing_paths=()
    for path in "''${all_paths[@]}"; do
      if [ -e "$path" ]; then
        existing_paths+=("$path")
      else
        echo "Skipping missing backup path: $path" >&2
      fi
    done

    if [ "''${#existing_paths[@]}" -eq 0 ]; then
      echo "No backup paths exist" >&2
      exit 1
    fi

    if ! ${pkgs.restic}/bin/restic snapshots --host ${lib.escapeShellArg cfg.hostLabel} --tag media-stack >/dev/null 2>&1; then
      ${pkgs.restic}/bin/restic init
    fi

    ${pkgs.restic}/bin/restic backup \
      --host ${lib.escapeShellArg cfg.hostLabel} \
      --tag media-stack \
      ${excludeFlags} \
      "''${existing_paths[@]}"

    ${pkgs.restic}/bin/restic forget \
      --host ${lib.escapeShellArg cfg.hostLabel} \
      --tag media-stack \
      --keep-daily ${toString cfg.retention.daily} \
      --keep-weekly ${toString cfg.retention.weekly} \
      --keep-monthly ${toString cfg.retention.monthly} \
      --prune
  '';

  restoreScript = pkgs.writeShellScript "media-restore" ''
    set -euo pipefail
    ${credentials}

    install -d -m 0700 ${stagingDir} ${postgresStaging} ${jellyfinStaging} ${decypharrStaging}

    for unit in jellyfin radarr sonarr prowlarr seerr decypharr; do
      ${pkgs.systemd}/bin/systemctl stop "$unit" 2>/dev/null || true
    done

    ${pkgs.restic}/bin/restic snapshots \
      --host ${lib.escapeShellArg cfg.hostLabel} \
      --tag media-stack \
      --latest 1 >/dev/null

    ${pkgs.restic}/bin/restic restore latest \
      --host ${lib.escapeShellArg cfg.hostLabel} \
      --tag media-stack \
      --target / \
      ${lib.concatMapStrings (path: "--include ${lib.escapeShellArg path} ") backupPaths}

    ${lib.concatMapStrings (db: ''
      test -f ${lib.escapeShellArg "${postgresStaging}/${db}.dump"}
    '') cfg.postgresDatabases}

    install -d -m 0755 -o ${jellyfinUser} -g ${jellyfinGroup} ${lib.escapeShellArg jellyfinDataDir}
    for db in ${lib.escapeShellArg jellyfinStaging}/*.db; do
      [ -e "$db" ] || continue
      install -m 0640 -o ${jellyfinUser} -g ${jellyfinGroup} \
        "$db" ${lib.escapeShellArg jellyfinDataDir}/"$(basename "$db")"
    done

    install -d -m 0750 -o ${cfg.decypharrUser} -g ${cfg.decypharrGroup} ${lib.escapeShellArg cfg.decypharrStateDir}
    for sub in db usenet; do
      if [ -d ${lib.escapeShellArg decypharrStaging}/"$sub" ]; then
        rm -rf ${lib.escapeShellArg cfg.decypharrStateDir}/"$sub"
        cp -a ${lib.escapeShellArg decypharrStaging}/"$sub" ${lib.escapeShellArg cfg.decypharrStateDir}/
        chown -R ${cfg.decypharrUser}:${cfg.decypharrGroup} ${lib.escapeShellArg cfg.decypharrStateDir}/"$sub"
      fi
    done

    ${lib.concatMapStrings (db: ''
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${postgres}/bin/dropdb --force --if-exists ${lib.escapeShellArg db}
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${postgres}/bin/createdb --owner=${lib.escapeShellArg db} ${lib.escapeShellArg db}
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${postgres}/bin/pg_restore \
        --dbname=${lib.escapeShellArg db} \
        --no-owner \
        --role=${lib.escapeShellArg db} \
        --exit-on-error \
        < ${lib.escapeShellArg "${postgresStaging}/${db}.dump"}
    '') cfg.postgresDatabases}

    # The restored host key unlocks the SOPS secrets, so reinstall them before
    # starting services. Skip the unit on hosts without sops-nix, but do not
    # hide a real failure to install the secrets.
    if ${pkgs.systemd}/bin/systemctl cat sops-install-secrets.service >/dev/null 2>&1; then
      ${pkgs.systemd}/bin/systemctl start sops-install-secrets.service
    fi

    for unit in radarr sonarr prowlarr decypharr seerr jellyfin; do
      ${pkgs.systemd}/bin/systemctl start "$unit" 2>/dev/null || true
    done

    for unit in jellyfin-api-key jellyfin-setup-wizard jellyfin-libraries jellyfin-plugins seerr-setup; do
      ${pkgs.systemd}/bin/systemctl start "$unit" 2>/dev/null || true
    done

    echo "Media restore complete. Reboot the host to let nixflix reconcile its remaining setup units."
  '';
in
{
  options.my.media.backup = {
    enable = lib.mkEnableOption "encrypted restic backups of the media stack state";

    repository = lib.mkOption {
      type = lib.types.str;
      example = "b2:my-media-backups:teeny";
      description = ''
        restic repository URL. The module sets B2_ACCOUNT_ID and
        B2_ACCOUNT_KEY, so a Backblaze B2 repository uses the
        `b2:<bucket>:<path>` form. The bucket itself must already exist.
      '';
    };

    passwordFile = secretFileOption "restic repository password";
    b2AccountIdFile = secretFileOption "Backblaze B2 account ID";
    b2AccountKeyFile = secretFileOption "Backblaze B2 application key";

    hostLabel = lib.mkOption {
      type = lib.types.str;
      default = "media-stack";
      description = "restic --host label used for snapshots, retention and restore.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:30:00";
      description = "systemd OnCalendar expression for the nightly backup.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = "Random delay added to the nightly backup start time.";
    };

    retention = {
      daily = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Daily snapshots to keep.";
      };
      weekly = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Weekly snapshots to keep.";
      };
      monthly = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Monthly snapshots to keep.";
      };
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultPaths;
      defaultText = lib.literalExpression "the nixflix media state paths";
      description = ''
        Live files and directories to back up. The Jellyfin SQLite databases
        and Decypharr's release index are staged separately for consistency;
        do not add them here.
      '';
    };

    sopsKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = sops.age.keyFile or "/var/lib/sops-nix/key.txt";
      defaultText = lib.literalExpression "config.sops.age.keyFile";
      description = ''
        Host age identity to include in the backup. Set to null to omit it.
        Restore this key before starting services on a replacement host, or
        rekey the repository secrets for the new host instead.
      '';
    };

    jellyfinDataDir = lib.mkOption {
      type = lib.types.str;
      default = jellyfinDataDir;
      defaultText = lib.literalExpression ''"''${config.nixflix.jellyfin.dataDir}/data"'';
      description = "Directory containing Jellyfin's SQLite databases.";
    };

    jellyfinUser = lib.mkOption {
      type = lib.types.str;
      default = jellyfinUser;
      description = "User that owns the restored Jellyfin databases.";
    };

    jellyfinGroup = lib.mkOption {
      type = lib.types.str;
      default = jellyfinGroup;
      description = "Group that owns the restored Jellyfin databases.";
    };

    decypharrStateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/decypharr";
      description = "Decypharr state directory containing db/ and usenet/.";
    };

    decypharrUser = lib.mkOption {
      type = lib.types.str;
      default = "decypharr";
      description = "User that owns the restored Decypharr state.";
    };

    decypharrGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Group that owns the restored Decypharr state.";
    };

    postgresDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "radarr"
        "sonarr"
        "prowlarr"
        "seerr"
      ];
      description = "PostgreSQL databases dumped into every snapshot.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "my.media.backup requires services.postgresql.enable = true: the *arr and Seerr databases live in PostgreSQL.";
      }
      {
        assertion = cfg.paths != [ ];
        message = "my.media.backup.paths must not be empty.";
      }
      {
        assertion = cfg.postgresDatabases != [ ];
        message = "my.media.backup.postgresDatabases must not be empty.";
      }
    ];

    systemd = {
      services.media-backup = {
        description = "Back up media stack state to restic";
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [ "postgresql.service" ];

        path = [
          pkgs.coreutils
          pkgs.restic
          pkgs.sqlite
          pkgs.systemd
          pkgs.util-linux
          postgres
        ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";

          LoadCredential = [
            "b2-account-id:${toString cfg.b2AccountIdFile}"
            "b2-account-key:${toString cfg.b2AccountKeyFile}"
            "restic-password:${toString cfg.passwordFile}"
          ];

          RuntimeDirectory = "media-backup";
          RuntimeDirectoryMode = "0700";
          CacheDirectory = "restic-media";
          CacheDirectoryMode = "0700";

          ExecStart = backupScript;
          TimeoutStartSec = "6h";
          UMask = "0077";

          # NoNewPrivileges is deliberately not set: the service runs as root and
          # uses runuser to dump PostgreSQL as the postgres user.
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/run/media-backup" ];
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        };
      };

      timers.media-backup = {
        description = "Nightly media stack backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = cfg.randomizedDelaySec;
          Unit = "media-backup.service";
        };
      };

      services.media-backup-restore = {
        description = "Restore media stack state from restic";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [ "postgresql.service" ];
        conflicts = [ "media-backup.service" ];

        path = [
          pkgs.coreutils
          pkgs.restic
          pkgs.systemd
          pkgs.util-linux
          postgres
        ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";

          LoadCredential = [
            "b2-account-id:${toString cfg.b2AccountIdFile}"
            "b2-account-key:${toString cfg.b2AccountKeyFile}"
            "restic-password:${toString cfg.passwordFile}"
          ];

          RuntimeDirectory = "media-backup";
          RuntimeDirectoryMode = "0700";
          CacheDirectory = "restic-media";
          CacheDirectoryMode = "0700";

          ExecStart = restoreScript;
          TimeoutStartSec = "6h";
          UMask = "0077";

          PrivateTmp = true;
          ProtectHome = true;
        };
      };
    };
  };
}
