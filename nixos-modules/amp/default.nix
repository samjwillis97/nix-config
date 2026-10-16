{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.my.amp;
  inherit (cfg) runner;
  ampPackage = lib.attrByPath [
    "packages"
    pkgs.stdenv.hostPlatform.system
    "amp"
  ] null inputs.llm-agents;
  ampRunnerSettings = pkgs.writeText "amp-runner-settings.json" (
    builtins.toJSON {
      "amp.runner.autoUpdate.enabled" = false;
      "amp.runner.env.enabled" = false;
      "amp.remoteThreadCreation.enabled" = false;
      "amp.updates.mode" = "disabled";
    }
  );
  ampGitConfig = pkgs.writeText "amp-gitconfig" ''
    [user]
      name = ${runner.gitName}
      email = ${runner.gitEmail}
    [credential "https://github.com"]
      helper = !${lib.getExe pkgs.gh} auth git-credential
    [url "https://github.com/"]
      insteadOf = git@github.com:
      insteadOf = ssh://git@github.com/
  '';
  runnerStart = pkgs.writeShellScript "amp-runner-start" ''
    set -euo pipefail

    : "''${CREDENTIALS_DIRECTORY:?systemd credentials directory is required}"
    AMP_API_KEY="$(< "$CREDENTIALS_DIRECTORY/amp-api-key")"
    GH_TOKEN="$(< "$CREDENTIALS_DIRECTORY/github-token")"
    if [[ -z "$AMP_API_KEY" || -z "$GH_TOKEN" ]]; then
      printf '%s\n' "Amp runner credentials must not be empty" >&2
      exit 1
    fi
    export AMP_API_KEY GH_TOKEN

    exec ${lib.getExe runner.package} \
      --settings-file ${lib.escapeShellArg (toString ampRunnerSettings)} \
      --no-tui \
      --runner-id ${lib.escapeShellArg runner.runnerId} \
      --remote-control-terminal \
      ${lib.optionalString runner.desktop.enable "--desktop"} \
      --discover-dirs \
      --discover-depth ${toString runner.discoverDepth}
  '';
  paths = with pkgs; [
    bashInteractive
    coreutils
    curl
    direnv
    findutils
    gawk
    gnugrep
    gnused
    git
    gh
    jq
    nix
    unzip
    zip
    tmux
  ];
  protectedPaths = [
    "/run/secrets"
    "/run/secrets.d"
    "/var/lib/sops-nix"
    "/var/lib/deploy"
    "/data"
    "/var/lib/supernote"
    "/var/lib/actual"
    "/var/lib/postgresql"
    "/var/lib/jellyfin"
  ];
in
{
  options.my.amp = {
    enable = lib.mkEnableOption "amp coding agent";

    runner = {
      enable = lib.mkEnableOption "the Amp remote runner";

      desktop.enable = lib.mkEnableOption "a private virtual desktop for runner threads (x86_64 Linux)";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = ampPackage;
        description = "Amp CLI package used by the remote runner.";
      };

      runnerId = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "Stable hostname-like identifier exposed to Amp clients.";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.path
            lib.types.str
          ]
        );
        default = null;
        description = "Runtime file containing the Amp access token.";
      };

      githubTokenFile = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.path
            lib.types.str
          ]
        );
        default = null;
        description = "Runtime file containing a repository-scoped GitHub token.";
      };

      gitName = lib.mkOption {
        type = lib.types.str;
        default = "samjwillis97";
        description = "Git author name for commits made by the Amp runner.";
      };

      gitEmail = lib.mkOption {
        type = lib.types.str;
        default = "sam@williscloud.org";
        description = "Git author email for commits made by the Amp runner.";
      };

      discoverDepth = lib.mkOption {
        type = lib.types.ints.between 1 10;
        default = 4;
        description = "Maximum directory depth used to discover Git checkouts.";
      };

      memoryMax = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional systemd MemoryMax limit for the Amp runner service.";
      };

      tasksMax = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Optional systemd TasksMax limit for the Amp runner service.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || runner.package != null;
          message = "my.amp.enable requires the pinned Amp CLI package to be available for the system.";
        }
        {
          assertion = !runner.enable || cfg.enable;
          message = "my.amp.runner.enable requires my.amp.enable";
        }
        {
          assertion = !runner.enable || runner.apiKeyFile != null;
          message = "my.amp.runner.apiKeyFile must be set when the runner is enabled.";
        }
        {
          assertion = !runner.enable || runner.githubTokenFile != null;
          message = "my.amp.runner.githubTokenFile must be set when the runner is enabled.";
        }
        {
          assertion = !runner.enable || builtins.match "[A-Za-z0-9][A-Za-z0-9-]*" runner.runnerId != null;
          message = "my.amp.runner.runnerId must be a valid hostname-like identifier.";
        }
        {
          assertion =
            !runner.desktop.enable || (runner.enable && pkgs.stdenv.hostPlatform.system == "x86_64-linux");
          message = "my.amp.runner.desktop.enable requires an enabled x86_64-linux runner.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      environment.systemPackages = [ runner.package ];
    })

    (lib.mkIf runner.enable {
      users.groups.amp = { };

      users.users.amp = {
        isSystemUser = true;
        group = "amp";
        home = "/var/lib/amp";
        createHome = true;
        homeMode = "0700";
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
      };

      environment.etc."ampcode/AGENTS.md".source = ./AGENTS.md;

      systemd.services.amp-runner = {
        description = "Amp remote coding agent runner";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        requires = [ "sops-install-secrets.service" ];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];

        path =
          paths
          ++ [ runner.package ]
          ++ lib.optionals runner.desktop.enable [
            pkgs.labwc
            pkgs.wlr-randr
            pkgs.ffmpeg
            pkgs.dbus
            (pkgs.callPackage ./waymote.nix { })
          ];

        environment = {
          HOME = "/var/lib/amp";
          SHELL = "${pkgs.bashInteractive}/bin/bash";
          XDG_CACHE_HOME = "/var/lib/amp/.cache";
          XDG_CONFIG_HOME = "/var/lib/amp/.config";
          XDG_DATA_HOME = "/var/lib/amp/.local/share";
          XDG_RUNTIME_DIR = lib.mkIf runner.desktop.enable "/run/amp-runner";
          GH_CONFIG_DIR = "/var/lib/amp/.config/gh";
          GIT_CONFIG_GLOBAL = toString ampGitConfig;
          NIX_REMOTE = "daemon";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };

        serviceConfig = {
          User = "amp";
          Group = "amp";
          WorkingDirectory = "/var/lib/amp/code";
          StateDirectory = [
            "amp"
            "amp/code"
          ];
          StateDirectoryMode = "0700";
          LoadCredential = [
            "amp-api-key:${runner.apiKeyFile}"
            "github-token:${runner.githubTokenFile}"
          ];
          ExecStart = runnerStart;
          Restart = "always";
          RestartSec = "5s";
          TimeoutStopSec = "30s";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          InaccessiblePaths = map (path: "-${path}") protectedPaths;
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
          CPUWeight = 20;
          IOWeight = 20;
        }
        // lib.optionalAttrs runner.desktop.enable {
          RuntimeDirectory = "amp-runner";
          RuntimeDirectoryMode = "0700";
        }
        // lib.optionalAttrs (runner.memoryMax != null) {
          MemoryMax = runner.memoryMax;
        }
        // lib.optionalAttrs (runner.tasksMax != null) {
          TasksMax = runner.tasksMax;
        };
      };

      systemd.services.nix-daemon.serviceConfig = {
        CPUWeight = lib.mkDefault 50;
        IOWeight = lib.mkDefault 50;
      };
    })
  ];
}
