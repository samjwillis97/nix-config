{
  config,
  lib,
  ...
}:

let
  pathOrString =
    with lib.types;
    oneOf [
      path
      str
    ];
in
{
  options.my.supernote = {
    enable = lib.mkEnableOption "Supernote private cloud";

    dataDir = lib.mkOption {
      type = pathOrString;
      default = "/var/lib/supernote";
      description = "Directory for Supernote private cloud persistent data.";
    };

    environmentFile = lib.mkOption {
      type = pathOrString;
      description = ''
        Environment file containing MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD, and
        REDIS_PASSWORD. Keep this file outside the Nix store.
      '';
    };

    databaseInitScript = lib.mkOption {
      type = pathOrString;
      default = "${config.my.supernote.dataDir}/supernotedb.sql";
      description = ''
        Path to the supernotedb.sql file downloaded from Supernote. The file
        is mounted read-only into MariaDB for first-time database setup.
      '';
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "supernote";
      description = "MariaDB user used by the Supernote service.";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "supernote-net";
      description = "Container network shared by the Supernote services.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 19072;
      description = "Host port mapped to the Supernote HTTP service.";
    };

    https = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose the Supernote HTTPS service.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 19443;
        description = "Host port mapped to the Supernote HTTPS service.";
      };

      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Domain name for a custom Supernote HTTPS certificate.";
      };

      certificateDirectory = lib.mkOption {
        type = pathOrString;
        default = "${config.my.supernote.dataDir}/sndata/cert";
        description = "Directory containing the custom HTTPS certificate and key.";
      };

      certificateName = lib.mkOption {
        type = lib.types.str;
        default = "server.crt";
        description = "Public certificate filename inside certificateDirectory.";
      };

      keyName = lib.mkOption {
        type = lib.types.str;
        default = "server.key";
        description = "Private key filename inside certificateDirectory.";
      };
    };

    automaticSync.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the fixed Supernote automatic synchronization port.";
    };

    images = {
      mariadb = lib.mkOption {
        type = lib.types.str;
        default = "mariadb:10.6.24";
        description = "MariaDB image used by the Supernote private cloud.";
      };

      redis = lib.mkOption {
        type = lib.types.str;
        default = "redis:7.4.7";
        description = "Redis image used by the Supernote private cloud.";
      };

      notelib = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/supernote/notelib:latest";
        description = "Supernote note conversion image.";
      };

      service = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/supernote/supernote-service:latest";
        description = "Supernote private cloud service image.";
      };
    };
  };

  config = lib.mkIf config.my.supernote.enable (
    let
      cfg = config.my.supernote;
      backend = config.virtualisation.oci-containers.backend;
      runtimePackage =
        if backend == "docker" then
          config.virtualisation.docker.package
        else
          config.virtualisation.podman.package;
      runtime = lib.getExe runtimePackage;
      containerNames = [
        "supernote-mariadb"
        "supernote-redis"
        "supernote-notelib"
        "supernote-service"
      ];
      sndataDir = "${cfg.dataDir}/sndata";
      databaseDataDir = "${cfg.dataDir}/mariadb";
      redisDataDir = "${cfg.dataDir}/redis";
      supernoteDataDir = "${cfg.dataDir}/supernote_data";
    in
    {
      my.virtualisation.containers.enable = true;

      assertions = [
        {
          assertion = cfg.https.enable || cfg.https.domain == null;
          message = "my.supernote.https.domain requires my.supernote.https.enable.";
        }
      ];

      systemd.tmpfiles.rules = map (directory: "d ${directory} 0750 root root -") [
        cfg.dataDir
        databaseDataDir
        redisDataDir
        supernoteDataDir
        "${sndataDir}/cert"
        "${sndataDir}/convert"
        "${sndataDir}/logs/app"
        "${sndataDir}/logs/cloud"
        "${sndataDir}/logs/web"
        "${sndataDir}/recycle"
      ];

      systemd.services = lib.mkMerge [
        {
          supernote-network = {
            description = "Create the Supernote container network";
            wantedBy = [ "multi-user.target" ];
            wants = [
              "network-online.target"
              "${backend}.service"
            ];
            after = [
              "network-online.target"
              "${backend}.service"
            ];
            before = map (name: "${name}.service") containerNames;
            path = [ runtimePackage ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              if ! ${runtime} network inspect ${lib.escapeShellArg cfg.networkName} >/dev/null 2>&1; then
                ${runtime} network create ${lib.escapeShellArg cfg.networkName}
              fi
            '';
          };

          supernote-mariadb.unitConfig.ConditionPathExists = [
            cfg.environmentFile
            cfg.databaseInitScript
          ];
          supernote-redis.unitConfig.ConditionPathExists = cfg.environmentFile;
          supernote-service.unitConfig.ConditionPathExists = [
            cfg.environmentFile
          ]
          ++ lib.optionals (cfg.https.domain != null) [
            "${cfg.https.certificateDirectory}/${cfg.https.certificateName}"
            "${cfg.https.certificateDirectory}/${cfg.https.keyName}"
          ];
        }
        (lib.genAttrs containerNames (_: {
          requires = [ "supernote-network.service" ];
          after = [ "supernote-network.service" ];
        }))
      ];

      virtualisation.oci-containers.containers = {
        supernote-mariadb = {
          image = cfg.images.mariadb;
          serviceName = "supernote-mariadb";
          networks = [ cfg.networkName ];
          environmentFiles = [ cfg.environmentFile ];
          environment = {
            MYSQL_DATABASE = "supernotedb";
            MYSQL_USER = cfg.databaseUser;
          };
          volumes = [
            "${databaseDataDir}:/var/lib/mysql"
            "${cfg.databaseInitScript}:/docker-entrypoint-initdb.d/supernotedb.sql:ro"
          ];
        };

        supernote-redis = {
          image = cfg.images.redis;
          serviceName = "supernote-redis";
          networks = [ cfg.networkName ];
          environmentFiles = [ cfg.environmentFile ];
          cmd = [
            "sh"
            "-c"
            ''exec redis-server --requirepass "$REDIS_PASSWORD" --dir /data --dbfilename dump.rdb''
          ];
          volumes = [ "${redisDataDir}:/data" ];
        };

        supernote-notelib = {
          image = cfg.images.notelib;
          serviceName = "supernote-notelib";
          networks = [ cfg.networkName ];
        };

        supernote-service = {
          image = cfg.images.service;
          serviceName = "supernote-service";
          networks = [ cfg.networkName ];
          dependsOn = [
            "supernote-mariadb"
            "supernote-redis"
            "supernote-notelib"
          ];
          environmentFiles = [ cfg.environmentFile ];
          environment = {
            DB_HOSTNAME = "supernote-mariadb";
            MYSQL_DATABASE = "supernotedb";
            MYSQL_USER = cfg.databaseUser;
            REDIS_HOST = "supernote-redis";
            REDIS_PORT = "6379";
          }
          // lib.optionalAttrs (cfg.https.domain != null) {
            DOMAIN_NAME = cfg.https.domain;
            SSL_CERT_NAME = cfg.https.certificateName;
            SSL_KEY_NAME = cfg.https.keyName;
          };
          ports = [
            "${toString cfg.httpPort}:8080"
          ]
          ++ lib.optional cfg.https.enable "${toString cfg.https.port}:443"
          ++ lib.optional cfg.automaticSync.enable "18072:18072";
          volumes = [
            "${sndataDir}/recycle:/home/supernote/recycle"
            "${supernoteDataDir}:/home/supernote/data"
            "${sndataDir}/logs/cloud:/home/supernote/cloud/logs"
            "${sndataDir}/logs/app:/home/supernote/logs"
            "${sndataDir}/logs/web:/var/log/nginx"
            "${sndataDir}/convert:/home/supernote/convert"
            "/etc/localtime:/etc/localtime:ro"
          ]
          ++ lib.optional (cfg.https.domain != null) "${cfg.https.certificateDirectory}:/etc/nginx/cert";
        };
      };
    }
  );
}
