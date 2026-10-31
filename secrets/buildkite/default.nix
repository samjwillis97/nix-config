{ config, lib, ... }:
{
  config = lib.mkIf config.my.buildkite.enable {
    sops.secrets."buildkite-agent-token" = {
      sopsFile = ./. + "/${config.networking.hostName}.yaml";
      key = "buildkite-agent-token";
      group = "buildkite-agents";
      mode = "0440";
      restartUnits = map (name: "buildkite-agent-${name}.service") (
        builtins.attrNames config.my.buildkite.agents
      );
    };
  };
}
