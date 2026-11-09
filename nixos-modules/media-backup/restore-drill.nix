# Manual restore drill. Run it through restore-drill.sh: the test driver must
# run outside the Nix build sandbox so QEMU can read the credential directory.
{
  pkgs,
  ...
}:
let
  secretsSource =
    let
      configured = builtins.getEnv "RESTORE_DRILL_SECRETS";
    in
    if configured == "" then
      throw "Set RESTORE_DRILL_SECRETS to the directory containing b2-account-id, b2-application-key and restic-password"
    else
      configured;

  repository =
    let
      configured = builtins.getEnv "RESTORE_DRILL_REPOSITORY";
    in
    if configured == "" then "b2:swillis-media-backups:teeny" else configured;

  secretsDir = "/run/restore-drill";

  restoreNode =
    { lib, ... }:
    {
      imports = [ ./default.nix ];

      environment.systemPackages = with pkgs; [
        curl
        jq
        postgresql
        restic
        sqlite
      ];

      users = {
        groups.media.gid = 169;
        users.jellyfin = {
          isSystemUser = true;
          uid = 146;
          group = "media";
        };
        users.decypharr = {
          isSystemUser = true;
          uid = 323;
          group = "media";
          home = "/var/lib/decypharr";
          createHome = false;
        };
      };

      services.postgresql = {
        enable = true;
        ensureDatabases = [
          "radarr"
          "sonarr"
          "prowlarr"
          "seerr"
        ];
        ensureUsers = [
          {
            name = "radarr";
            ensureDBOwnership = true;
          }
          {
            name = "sonarr";
            ensureDBOwnership = true;
          }
          {
            name = "prowlarr";
            ensureDBOwnership = true;
          }
          {
            name = "seerr";
            ensureDBOwnership = true;
          }
        ];
      };

      my.media.backup = {
        enable = true;
        inherit repository;
        b2AccountIdFile = "${secretsDir}/b2-account-id";
        b2AccountKeyFile = "${secretsDir}/b2-application-key";
        passwordFile = "${secretsDir}/restic-password";
      };

      # The drill starts the restore service explicitly; the timer must not
      # race it with a backup of the empty VM.
      systemd.timers.media-backup.wantedBy = lib.mkForce [ ];

      virtualisation = {
        cores = 2;
        memorySize = 8192;
        diskSize = 20 * 1024;
        sharedDirectories.restore-secrets = {
          source = secretsSource;
          target = secretsDir;
        };
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "media-restore-drill";

  nodes.restore = restoreNode;

  testScript = ''
    restore.start()
    restore.wait_for_unit("multi-user.target")
    restore.wait_for_unit("postgresql.service")
    restore.wait_for_unit("postgresql-setup.service")

    restore.succeed("test -s ${secretsDir}/b2-account-id")
    restore.succeed("test -s ${secretsDir}/b2-application-key")
    restore.succeed("test -s ${secretsDir}/restic-password")

    restore.succeed("systemctl stop media-backup.timer 2>/dev/null || true")
    restore.succeed("systemctl start media-backup-restore.service")
    restore.succeed("systemctl show -p Result --value media-backup-restore.service | grep -Fx success")

    # Jellyfin: the consistent database copy, its schema and service ownership.
    restore.succeed("test -s /var/lib/jellyfin/data/jellyfin.db")
    restore.succeed("test \"$(sqlite3 /var/lib/jellyfin/data/jellyfin.db 'PRAGMA integrity_check')\" = ok")
    restore.succeed("test \"$(sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT count(*) FROM sqlite_master WHERE type = 'table'\")\" -gt 10")
    restore.succeed("test \"$(stat -c %u:%g /var/lib/jellyfin/data/jellyfin.db)\" = 146:169")
    restore.succeed("test -n \"$(find /var/lib/jellyfin/metadata -type f -print -quit)\"")

    # Application state and the SOPS host identity.
    restore.succeed("test -s /var/lib/radarr/config.xml")
    restore.succeed("test -s /var/lib/sonarr/config.xml")
    restore.succeed("test -s /var/lib/prowlarr/config.xml")
    restore.succeed("test -s /var/lib/seerr/settings.json")
    restore.succeed("test -s /var/lib/sops-nix/key.txt")

    # Decypharr's append-only stores.
    restore.succeed("test -s /var/lib/decypharr/db/entries.db")
    restore.succeed("test -d /var/lib/decypharr/usenet/meta")
    restore.succeed("test \"$(stat -c %u:%g /var/lib/decypharr/db/entries.db)\" = 323:169")

    # Media paths must come back as symlinks, not dereferenced files.
    restore.succeed("test -n \"$(find /data/media -type l -print -quit)\"")

    # PostgreSQL: every database has data, and the key *arr tables exist.
    for db in ["radarr", "sonarr", "prowlarr", "seerr"]:
        restore.succeed(f"runuser -u postgres -- psql -d {db} -tAc \"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'\" | grep -qE '^[1-9]'")
    restore.succeed("runuser -u postgres -- psql -d radarr -tAc 'SELECT count(*) FROM \"Movies\"' | grep -qE '^[1-9]'")
    restore.succeed("runuser -u postgres -- psql -d sonarr -tAc 'SELECT count(*) FROM \"Series\"' | grep -qE '^[1-9]'")
    restore.succeed("runuser -u postgres -- psql -d prowlarr -tAc 'SELECT count(*) FROM \"Indexers\"' | grep -qE '^[1-9]'")

    print("Restored sizes:")
    print(restore.succeed("du -sh /var/lib/jellyfin /var/lib/radarr /var/lib/sonarr /var/lib/prowlarr /var/lib/seerr /var/lib/decypharr /var/lib/sops-nix /data/media"))
    print("RESTORE_DRILL_OK")
  '';
}
