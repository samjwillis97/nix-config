{ pkgs, ... }:
let
  common =
    { lib, ... }:
    {
      imports = [ ./default.nix ];

      environment.systemPackages = with pkgs; [
        curl
        jq
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

      environment.etc = {
        "restic-password".text = "synthetic-restic-password\n";
        "b2-account-id".text = "synthetic-b2-account-id\n";
        "b2-account-key".text = "synthetic-b2-account-key\n";
      };

      # The test uses a local restic REST server instead of B2 so it needs no
      # real credentials. The module only changes RESTIC_REPOSITORY and the B2
      # environment variables, so the snapshot/restore path is the same.
      my.media.backup = {
        enable = true;
        repository = "rest:http://server:8000/";
        passwordFile = "/etc/restic-password";
        b2AccountIdFile = "/etc/b2-account-id";
        b2AccountKeyFile = "/etc/b2-account-key";
      };

      # The test starts the backup service explicitly so the timer cannot race
      # the restore. The timer unit itself is still exercised by systemd.
      systemd.timers.media-backup.wantedBy = lib.mkForce [ ];

      virtualisation.memorySize = 1536;
    };
in
pkgs.testers.runNixOSTest {
  name = "media-backup";

  nodes = {
    server = {
      services.restic.server = {
        enable = true;
        dataDir = "/var/lib/restic";
        listenAddress = "8000";
        extraFlags = [ "--no-auth" ];
      };
      networking.firewall.allowedTCPPorts = [ 8000 ];
    };

    source = common;
    restore = common;

    disabled = {
      imports = [ ./default.nix ];
    };
  };

  testScript = ''
    server.start()
    server.wait_for_unit("restic-rest-server.socket")
    server.wait_for_unit("restic-rest-server.service")

    source.start()
    source.wait_for_unit("multi-user.target")
    source.wait_for_unit("postgresql.service")
    source.wait_for_unit("postgresql-setup.service")
    source.wait_until_succeeds("curl -s -o /dev/null http://server:8000/", timeout=30)

    # Populate a representative media state tree.
    source.succeed("mkdir -p /var/lib/jellyfin/config /var/lib/jellyfin/data /var/lib/jellyfin/metadata /var/lib/jellyfin/plugins /var/lib/jellyfin/log")
    source.succeed("echo jellyfin-system > /var/lib/jellyfin/config/system.xml")
    source.succeed("echo artwork > /var/lib/jellyfin/metadata/artwork.jpg")
    source.succeed("echo should-not-be-backed-up > /var/lib/jellyfin/log/huge.log")
    source.succeed("echo \"CREATE TABLE marker (value TEXT); INSERT INTO marker VALUES ('library');\" | sqlite3 /var/lib/jellyfin/data/library.db")
    source.succeed("echo \"CREATE TABLE marker (value TEXT); INSERT INTO marker VALUES ('jellyfin');\" | sqlite3 /var/lib/jellyfin/data/jellyfin.db")
    source.succeed("echo stale-wal > /var/lib/jellyfin/data/library.db-wal")
    source.succeed("echo stale-shm > /var/lib/jellyfin/data/library.db-shm")

    source.succeed("mkdir -p /var/lib/seerr")
    source.succeed("echo '{\"jellyfin\":\"connected\"}' > /var/lib/seerr/settings.json")

    source.succeed("mkdir -p /var/lib/decypharr/db /var/lib/decypharr/usenet/meta /var/lib/decypharr/cache")
    source.succeed("echo entries > /var/lib/decypharr/db/entries.db")
    source.succeed("echo meta > /var/lib/decypharr/usenet/meta/abc.meta")
    source.succeed("echo cache > /var/lib/decypharr/cache/huge")
    source.succeed("chown -R decypharr:media /var/lib/decypharr")

    source.succeed("mkdir -p /var/lib/radarr/logs /var/lib/radarr/MediaCover /var/lib/radarr/Backups /var/lib/sonarr /var/lib/prowlarr")
    source.succeed("echo radarr-config > /var/lib/radarr/config.xml")
    source.succeed("echo radarr-log > /var/lib/radarr/logs/huge.log")
    source.succeed("echo radarr-cover > /var/lib/radarr/MediaCover/huge.jpg")
    source.succeed("echo sonarr-config > /var/lib/sonarr/config.xml")
    source.succeed("echo prowlarr-config > /var/lib/prowlarr/config.xml")

    source.succeed("mkdir -p '/data/media/movies/Synthetic Movie (2024)'")
    source.succeed("ln -s '/mnt/decypharr/__all__/Synthetic Movie (2024)/movie.mkv' '/data/media/movies/Synthetic Movie (2024)/movie.mkv'")

    source.succeed("mkdir -p /var/lib/sops-nix")
    source.succeed("echo synthetic-age-key > /var/lib/sops-nix/key.txt")

    for db in ["radarr", "sonarr", "prowlarr", "seerr"]:
        source.succeed(f"runuser -u postgres -- psql -d {db} -c \"CREATE TABLE marker (value TEXT); INSERT INTO marker VALUES ('{db}');\"")

    source.succeed("systemctl start media-backup.service")
    source.succeed("systemctl show -p Result --value media-backup.service | grep -Fx success")
    source.succeed("systemctl cat media-backup.timer >/dev/null")
    source.succeed("! systemctl cat media-backup.service | grep -F synthetic-restic-password")
    source.succeed("RESTIC_REPOSITORY='rest:http://server:8000/' RESTIC_PASSWORD='synthetic-restic-password' restic snapshots --host media-stack --tag media-stack --json | jq -e 'length > 0'")

    # Edit the live state after the backup. A correct restore uses the
    # consistent staged copies, not these post-backup changes.
    source.succeed("sqlite3 /var/lib/jellyfin/data/library.db \"UPDATE marker SET value='modified-after-backup'\"")
    source.succeed("echo modified-after-backup > /var/lib/decypharr/db/entries.db")
    source.succeed("echo modified-after-backup > /var/lib/radarr/config.xml")

    source.shutdown()

    restore.start()
    restore.wait_for_unit("multi-user.target")
    restore.wait_for_unit("postgresql.service")
    restore.wait_for_unit("postgresql-setup.service")
    restore.succeed("systemctl stop media-backup.timer 2>/dev/null || true")
    restore.succeed("test ! -e /var/lib/jellyfin/config/system.xml")

    restore.succeed("systemctl start media-backup-restore.service")
    restore.succeed("systemctl show -p Result --value media-backup-restore.service | grep -Fx success")

    # Files restored from the live tree.
    restore.succeed("test \"$(cat /var/lib/jellyfin/config/system.xml)\" = jellyfin-system")
    restore.succeed("test \"$(cat /var/lib/jellyfin/metadata/artwork.jpg)\" = artwork")
    restore.succeed("test ! -e /var/lib/jellyfin/log/huge.log")
    restore.succeed("test \"$(cat /var/lib/seerr/settings.json)\" = '{\"jellyfin\":\"connected\"}'")
    restore.succeed("test \"$(cat /var/lib/radarr/config.xml)\" = radarr-config")
    restore.succeed("test ! -e /var/lib/radarr/logs/huge.log")
    restore.succeed("test ! -e /var/lib/radarr/MediaCover/huge.jpg")
    restore.succeed("test \"$(cat /var/lib/sonarr/config.xml)\" = sonarr-config")
    restore.succeed("test \"$(cat /var/lib/prowlarr/config.xml)\" = prowlarr-config")
    restore.succeed("test \"$(cat /var/lib/sops-nix/key.txt)\" = synthetic-age-key")

    # Symlinks must remain symlinks with the same target.
    restore.succeed("test -L '/data/media/movies/Synthetic Movie (2024)/movie.mkv'")
    restore.succeed("test \"$(readlink '/data/media/movies/Synthetic Movie (2024)/movie.mkv')\" = '/mnt/decypharr/__all__/Synthetic Movie (2024)/movie.mkv'")

    # Jellyfin databases come from the consistent .backup copies; stale live
    # WAL/SHM files must not be restored.
    restore.succeed("test ! -e /var/lib/jellyfin/data/library.db-wal")
    restore.succeed("test ! -e /var/lib/jellyfin/data/library.db-shm")
    restore.succeed("test \"$(sqlite3 /var/lib/jellyfin/data/library.db 'SELECT value FROM marker')\" = library")
    restore.succeed("test \"$(sqlite3 /var/lib/jellyfin/data/jellyfin.db 'SELECT value FROM marker')\" = jellyfin")
    restore.succeed("test \"$(stat -c %u:%g /var/lib/jellyfin/data/library.db)\" = 146:169")

    # Decypharr's release index comes from the stopped copy.
    restore.succeed("test \"$(cat /var/lib/decypharr/db/entries.db)\" = entries")
    restore.succeed("test \"$(cat /var/lib/decypharr/usenet/meta/abc.meta)\" = meta")
    restore.succeed("test \"$(stat -c %u:%g /var/lib/decypharr/db/entries.db)\" = 323:169")
    restore.succeed("test ! -e /var/lib/decypharr/cache/huge")

    # PostgreSQL databases come from the dumps.
    for db in ["radarr", "sonarr", "prowlarr", "seerr"]:
        restore.succeed(f"runuser -u postgres -- psql -d {db} -tAc 'SELECT value FROM marker' | grep -Fx '{db}'")

    disabled.start()
    disabled.succeed("! systemctl list-unit-files | grep -q '^media-backup'")
  '';
}
