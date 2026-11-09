# Manual restore drill. Run it through restore-drill.sh: the test driver must
# run outside the Nix build sandbox so QEMU can read the credential directory.
{
  pkgs,
  inputs,
  self,
  ...
}:
let
  websites = builtins.getEnv "RESTORE_DRILL_WEBSITES" != "";
  keep = builtins.getEnv "RESTORE_DRILL_KEEP" != "";
  system = pkgs.stdenv.hostPlatform.system;

  unstable = import inputs.unstable {
    inherit (pkgs) system config;
  };

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
    { config, lib, ... }:
    {
      imports = [
        ./default.nix
        inputs.nixflix.nixosModules.default
      ]
      ++ pkgs.lib.optionals websites [
        ../../nixos-modules/media
        ../../nixos-modules/ingress.nix
        ../../nixos-modules/sops.nix
        ../../secrets/media/default.nix
        inputs.sops-nix.nixosModules.sops
      ];

      _module.args = {
        inherit inputs unstable;
      };

      # The repository overlay supplies the Decypharr package; apply only the
      # part the media stack needs so the test does not pull in unrelated
      # host packages.
      nixpkgs.pkgs = lib.mkForce (
        pkgs.extend (
          _final: _prev: {
            decypharr = self.packages.${system}.decypharr;
          }
        )
      );

      environment.systemPackages = with pkgs; [
        curl
        jq
        postgresql
        restic
        sqlite
      ];

      # The non-websites drill is a minimal restore target. The full media
      # stack mode gets the same users and PostgreSQL databases from nixflix.
      users = lib.mkIf (!websites) {
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
        ensureDatabases = lib.mkIf (!websites) [
          "radarr"
          "sonarr"
          "prowlarr"
          "seerr"
        ];
        ensureUsers = lib.mkIf (!websites) [
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

      my.media = {
        backup = {
          enable = true;
          inherit repository;
          b2AccountIdFile = "${secretsDir}/b2-account-id";
          b2AccountKeyFile = "${secretsDir}/b2-application-key";
          passwordFile = "${secretsDir}/restic-password";
        };
      }
      // lib.optionalAttrs websites {
        enable = true;

        jellyfin = {
          enable = true;
          apiKeyFile = config.sops.secrets."jellyfin/api-key".path;
          adminPasswordFile = config.sops.secrets."jellyfin/admin-password".path;
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
          };
          openFirewall = true;
          ingress.enable = false;
        };

        arr = {
          enable = true;
          radarr.apiKeyFile = config.sops.secrets."radarr/api-key".path;
          sonarr.apiKeyFile = config.sops.secrets."sonarr/api-key".path;
          prowlarr.apiKeyFile = config.sops.secrets."prowlarr/api-key".path;
          seerr.apiKeyFile = config.sops.secrets."seerr/api-key".path;
          adminPasswordFile = config.sops.secrets."arr/admin-password".path;
          openFirewall = true;
          ingress.enable = false;
        };

        decypharr = {
          enable = true;
          apiTokenFile = config.sops.secrets."decypharr/api-token".path;
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
      };

      nixflix = lib.mkIf websites {
        radarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";
        sonarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";
        prowlarr.config.hostConfig.bindAddress = lib.mkForce "0.0.0.0";
      };

      systemd = {
        services = lib.mkIf websites {
          seerr.environment.HOST = lib.mkForce "0.0.0.0";
        };

        timers.media-backup.wantedBy = lib.mkForce [ ];
      };

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
  globalTimeout = 2 * 60 * 60;

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
  ''
  + pkgs.lib.optionalString websites ''
    restore.wait_for_unit("jellyfin.service")
    restore.wait_for_unit("radarr.service")
    restore.wait_for_unit("sonarr.service")
    restore.wait_for_unit("prowlarr.service")
    restore.wait_for_unit("seerr.service")
    restore.wait_for_unit("decypharr.service")
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:8096/", timeout=300)
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:7878/", timeout=300)
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:8989/", timeout=300)
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:9696/", timeout=300)
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:5055/", timeout=300)
    restore.wait_until_succeeds("curl -fsSL -o /dev/null http://127.0.0.1:8282/", timeout=300)
  ''
  + pkgs.lib.optionalString keep ''
    restore.forward_port(18096, 8096)
    restore.forward_port(17878, 7878)
    restore.forward_port(18989, 8989)
    restore.forward_port(19696, 9696)
    restore.forward_port(15055, 5055)
    restore.forward_port(18282, 8282)

    print("Restore drill VM is still running.")
    print("  Jellyfin:  http://127.0.0.1:18096")
    print("  Radarr:    http://127.0.0.1:17878")
    print("  Sonarr:    http://127.0.0.1:18989")
    print("  Prowlarr:  http://127.0.0.1:19696")
    print("  Seerr:     http://127.0.0.1:15055")
    print("  Decypharr: http://127.0.0.1:18282")
    print("Press Ctrl-D in this terminal when finished; the VM will be deleted.")
    restore.shell_interact()
  ''
  + ''
    print("RESTORE_DRILL_OK")
  '';
}
