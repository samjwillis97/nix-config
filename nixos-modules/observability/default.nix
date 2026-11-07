{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.observability;

  defaultMcpPackage = pkgs.callPackage ../../packages/mcp-victorialogs { };
  defaultProbePackage = pkgs.callPackage ../../packages/teeny-probe { };

  probeSocket = "/run/teeny-probe/probe.sock";
in
{
  options.my.observability = {
    logs = {
      enable = lib.mkEnableOption "the local VictoriaLogs store and journald upload";

      retention = lib.mkOption {
        type = lib.types.str;
        default = "14d";
        description = "How long VictoriaLogs keeps log entries.";
      };

      maxDiskUsagePercent = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 80;
        description = "Drop the oldest partitions when the VictoriaLogs filesystem reaches this usage.";
      };

      minFreeDiskSpace = lib.mkOption {
        type = lib.types.str;
        default = "1GB";
        description = "VictoriaLogs stops accepting writes below this much free disk space.";
      };

      uploadUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9428/insert/journald";
        description = "VictoriaLogs journald ingestion URL used by systemd-journal-upload.";
      };

      mcp = {
        enable = lib.mkEnableOption "the read-only VictoriaLogs MCP server";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultMcpPackage;
          description = "mcp-victorialogs package.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8081;
          description = "Loopback port for the MCP HTTP endpoint.";
        };
      };
    };

    probe = {
      enable = lib.mkEnableOption "the read-only host probe broker";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultProbePackage;
        description = "teeny-probe package containing the client and broker.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.logs.mcp.enable || cfg.logs.enable;
          message = "my.observability.logs.mcp.enable requires my.observability.logs.enable";
        }
      ];
    }

    (lib.mkIf cfg.logs.enable {
      services.victorialogs = {
        enable = true;
        listenAddress = "127.0.0.1:9428";
        stateDir = "victorialogs";
        extraOptions = [
          "-retentionPeriod=${cfg.logs.retention}"
          "-retention.maxDiskUsagePercent=${toString cfg.logs.maxDiskUsagePercent}"
          "-storage.minFreeDiskSpaceBytes=${cfg.logs.minFreeDiskSpace}"
          # Command lines routinely contain tokens and passwords; the journal
          # still keeps the unit, priority, host, and message fields.
          "-journald.ignoreFields=_CMDLINE"
        ];
      };

      services.journald.upload = {
        enable = true;
        settings.Upload.URL = cfg.logs.uploadUrl;
      };

      systemd.services = lib.optionalAttrs cfg.logs.mcp.enable {
        victorialogs-mcp = {
          description = "Read-only VictoriaLogs MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "victorialogs.service"
          ];
          requires = [ "victorialogs.service" ];

          environment = {
            VL_INSTANCE_ENTRYPOINT = "http://127.0.0.1:9428";
            MCP_SERVER_MODE = "http";
            MCP_LISTEN_ADDR = "127.0.0.1:${toString cfg.logs.mcp.port}";
            # The embedded documentation index is the largest part of the
            # server; the query tools do not need it.
            MCP_DISABLED_TOOLS = "documentation,flags";
          };

          serviceConfig = {
            ExecStart = "${lib.getExe cfg.logs.mcp.package}";
            DynamicUser = true;
            Restart = "always";
            RestartSec = "2s";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            LockPersonality = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictSUIDSGID = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
          };
        };
      };
    })

    (lib.mkIf cfg.probe.enable {
      users.groups.probe = { };

      users.users = {
        probe = {
          isSystemUser = true;
          group = "probe";
          # The broker reads the journal as this user. The Amp runner only
          # gets the probe group, which is the socket's group, not the
          # journal group.
          extraGroups = [ "systemd-journal" ];
          home = "/var/lib/probe";
          createHome = true;
          shell = pkgs.bashInteractive;
        };
      }
      // lib.optionalAttrs ((config.my ? amp) && config.my.amp.runner.enable) {
        # Let the Amp runner reach the socket without journal access.
        amp.extraGroups = [ "probe" ];
      };

      systemd.tmpfiles.rules = [
        "d /run/teeny-probe 0750 probe probe -"
      ];

      systemd.sockets.teeny-probe = {
        description = "Read-only host probe socket";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = probeSocket;
          SocketMode = "0660";
          SocketUser = "probe";
          SocketGroup = "probe";
          Accept = true;
        };
      };

      systemd.services = {
        "teeny-probe@" = {
          description = "Read-only host probe for %I";
          path = [
            pkgs.systemd
            pkgs.coreutils
            pkgs.procps
          ];
          serviceConfig = {
            ExecStart = "${lib.getExe cfg.probe.package} --broker";
            User = "probe";
            Group = "probe";
            StandardInput = "socket";
            StandardOutput = "socket";
            StandardError = "journal";
            Restart = "no";
            TimeoutStopSec = "5s";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            LockPersonality = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictSUIDSGID = true;
            RestrictAddressFamilies = [ "AF_UNIX" ];
          };
        };
      }
      // lib.optionalAttrs ((config.my ? amp) && config.my.amp.runner.enable) {
        # Make the client available to the runner's shell without putting it
        # in the runner's filesystem sandbox or giving it the journal group.
        amp-runner.path = lib.mkAfter [ cfg.probe.package ];
      };

      environment.systemPackages = [ cfg.probe.package ];
    })
  ];
}
