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
  defaultDispatcherPackage = pkgs.callPackage ../../packages/triage-dispatcher { };
  defaultTriageStatePackage = pkgs.callPackage ../../packages/triage-state { };
  defaultPromptFile = pkgs.writeText "triage-prompt.md" (
    builtins.readFile ../../docs/triage-prompt.md
  );

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

    triage = {
      enable = lib.mkEnableOption "automatic Amp triage threads from VictoriaLogs";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultDispatcherPackage;
        description = "triage-dispatcher package.";
      };

      statePackage = lib.mkOption {
        type = lib.types.package;
        default = defaultTriageStatePackage;
        description = "triage-state package used to deduplicate incidents.";
      };

      ampPackage = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default =
          if config.my ? amp && config.my.amp.runner.enable then config.my.amp.runner.package else null;
        defaultText = lib.literalExpression "config.my.amp.runner.package";
        description = "Amp CLI used to create and continue threads.";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.path
            lib.types.str
          ]
        );
        default =
          if config.my ? amp && config.my.amp.runner.enable then config.my.amp.runner.apiKeyFile else null;
        defaultText = lib.literalExpression "config.my.amp.runner.apiKeyFile";
        description = "Runtime file containing the Amp access token.";
      };

      runnerId = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "Amp runner that executes the triage thread.";
      };

      runnerDir = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Absolute checkout path served by the runner.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "Journald hostname to query and put in alert labels.";
      };

      alertName = lib.mkOption {
        type = lib.types.str;
        default = "journal-errors";
        description = "Alert name used for incident fingerprints.";
      };

      window = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = "LogsQL time window evaluated on each run.";
      };

      threshold = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = "Minimum error lines per unit before an alert is created.";
      };

      limit = lib.mkOption {
        type = lib.types.ints.positive;
        default = 25;
        description = "Maximum alert rows returned by one LogsQL query.";
      };

      excludeUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "triage-dispatcher.service" ];
        description = "Systemd units that must never trigger a triage thread.";
      };

      cooldownSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 6 * 60 * 60;
        description = "Minimum seconds between new threads for one incident.";
      };

      continueCooldownSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 6 * 60 * 60;
        description = "Minimum seconds between follow-ups on an existing thread.";
      };

      maxPerHour = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Global maximum new threads per hour.";
      };

      maxPerDay = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Global maximum new threads per day.";
      };

      maxActionsPerRun = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Maximum spawn/continue actions in one dispatcher run.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "1min";
        description = "Delay after a completed run before the timer fires again.";
      };

      mode = lib.mkOption {
        type = lib.types.str;
        default = "medium";
        description = "Amp agent mode for spawned and continued threads.";
      };

      ampTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 15 * 60;
        description = "Maximum time to wait for one Amp thread turn.";
      };

      queryTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Maximum time to wait for VictoriaLogs.";
      };

      query = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional LogsQL query override; empty uses the built-in query.";
      };

      promptFile = lib.mkOption {
        type = lib.types.path;
        default = defaultPromptFile;
        description = "Prompt template rendered for each alert.";
      };

      victorialogsUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9428";
        description = "Loopback VictoriaLogs HTTP endpoint.";
      };

      stateFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/triage/state.db";
        description = "SQLite state database used by the dedupe gate.";
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
        {
          assertion = !cfg.triage.enable || cfg.logs.enable;
          message = "my.observability.triage.enable requires my.observability.logs.enable";
        }
        {
          assertion = !cfg.triage.enable || cfg.triage.ampPackage != null;
          message = "my.observability.triage.enable requires an Amp CLI package";
        }
        {
          assertion = !cfg.triage.enable || cfg.triage.apiKeyFile != null;
          message = "my.observability.triage.enable requires my.observability.triage.apiKeyFile";
        }
        {
          assertion = !cfg.triage.enable || cfg.triage.runnerDir != "";
          message = "my.observability.triage.enable requires my.observability.triage.runnerDir";
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

      systemd = {
        tmpfiles.rules = [
          "d /run/teeny-probe 0750 probe probe -"
        ];

        sockets.teeny-probe = {
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

        services = {
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
      };

      environment.systemPackages = [ cfg.probe.package ];
    })

    (lib.mkIf cfg.triage.enable (
      let
        dispatcherArgs = [
          "--victorialogs-url"
          cfg.triage.victorialogsUrl
          "--host"
          cfg.triage.host
          "--window"
          cfg.triage.window
          "--threshold"
          (toString cfg.triage.threshold)
          "--limit"
          (toString cfg.triage.limit)
          "--alert-name"
          cfg.triage.alertName
          "--state"
          cfg.triage.stateFile
          "--state-bin"
          (lib.getExe cfg.triage.statePackage)
          "--cooldown"
          (toString cfg.triage.cooldownSeconds)
          "--continue-cooldown"
          (toString cfg.triage.continueCooldownSeconds)
          "--max-per-hour"
          (toString cfg.triage.maxPerHour)
          "--max-per-day"
          (toString cfg.triage.maxPerDay)
          "--max-actions-per-run"
          (toString cfg.triage.maxActionsPerRun)
          "--amp"
          (lib.getExe cfg.triage.ampPackage)
          "--runner-id"
          cfg.triage.runnerId
          "--runner-dir"
          cfg.triage.runnerDir
          "--mode"
          cfg.triage.mode
          "--amp-timeout"
          (toString cfg.triage.ampTimeoutSeconds)
          "--amp-home"
          "/var/lib/triage"
          "--amp-cwd"
          "/var/lib/triage"
          "--query-timeout"
          (toString cfg.triage.queryTimeoutSeconds)
          "--prompt-file"
          (toString cfg.triage.promptFile)
        ]
        ++ lib.optionals (cfg.triage.query != "") [
          "--query"
          cfg.triage.query
        ]
        ++ lib.concatMap (unit: [
          "--exclude-unit"
          unit
        ]) cfg.triage.excludeUnits;

        dispatcherStart = pkgs.writeShellScript "triage-dispatcher-start" ''
          set -euo pipefail
          : "''${CREDENTIALS_DIRECTORY:?systemd credentials directory is required}"
          exec ${lib.getExe cfg.triage.package} \
            ${lib.escapeShellArgs dispatcherArgs} \
            --api-key-file "$CREDENTIALS_DIRECTORY/amp-api-key"
        '';
      in
      {
        users.groups.triage = { };

        users.users.triage = {
          isSystemUser = true;
          group = "triage";
          home = "/var/lib/triage";
          createHome = true;
          homeMode = "0700";
          shell = pkgs.bashInteractive;
        };

        systemd.services.triage-dispatcher = {
          description = "Automatic Amp triage thread dispatcher";
          wants = [
            "network-online.target"
            "victorialogs.service"
          ];
          after = [
            "network-online.target"
            "victorialogs.service"
            "sops-install-secrets.service"
          ];
          requires = [ "victorialogs.service" ];
          path = [
            cfg.triage.ampPackage
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.git
            pkgs.gh
          ];
          environment = {
            HOME = "/var/lib/triage";
            XDG_CACHE_HOME = "/var/lib/triage/.cache";
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
          serviceConfig = {
            Type = "oneshot";
            User = "triage";
            Group = "triage";
            StateDirectory = "triage";
            StateDirectoryMode = "0700";
            LoadCredential = [
              "amp-api-key:${cfg.triage.apiKeyFile}"
            ];
            ExecStart = dispatcherStart;
            TimeoutStartSec = "${toString (cfg.triage.ampTimeoutSeconds + 120)}s";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            InaccessiblePaths = [
              "-/run/secrets"
              "-/var/lib/sops-nix"
              "-/var/lib/deploy"
              "-/data"
            ];
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

        systemd.timers.triage-dispatcher = {
          description = "Poll logs for automatic Amp triage";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitInactiveSec = cfg.triage.interval;
            AccuracySec = "15s";
            Persistent = false;
          };
        };
      }
    ))
  ];
}
