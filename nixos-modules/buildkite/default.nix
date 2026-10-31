{ config, lib, ... }:
let
  cfg = config.my.buildkite;
in
{
  options.my.buildkite = {
    enable = lib.mkEnableOption "Buildkite agents";

    tokenFile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.path
          lib.types.str
        ]
      );
      default = null;
      description = "Runtime file containing the Buildkite agent token shared by the configured agents.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.tags = lib.mkOption {
            type = lib.types.attrsOf (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
            default = { };
            example = {
              queue = "default";
              os = "linux";
            };
            description = "Buildkite tags used to route jobs to this agent.";
          };
        }
      );
      default = { };
      description = "Buildkite agent processes, keyed by the service-name suffix.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || cfg.tokenFile != null;
          message = "my.buildkite.tokenFile must be set when Buildkite agents are enabled.";
        }
        {
          assertion = !cfg.enable || cfg.agents != { };
          message = "my.buildkite.agents must define at least one agent when Buildkite agents are enabled.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      # All agents read one token file, so they share a group instead of
      # granting the token to every local account.
      users.groups.buildkite-agents = { };

      services.buildkite-agents = lib.mapAttrs (_: agent: {
        enable = true;
        tokenPath = cfg.tokenFile;
        inherit (agent) tags;
        extraGroups = [ "buildkite-agents" ];
      }) cfg.agents;

      users.users = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "buildkite-agent-${name}" {
          homeMode = "0700";
        }
      ) cfg.agents;

      # Keep the generated agent configuration, which contains the token, private.
      systemd.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "buildkite-agent-${name}" {
          serviceConfig.UMask = "0077";
        }
      ) cfg.agents;
    })

    (lib.mkIf (cfg.enable && config ? sops && config.sops.secrets != { }) {
      systemd.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "buildkite-agent-${name}" {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];
        }
      ) cfg.agents;
    })
  ];
}
