{ config, ... }:
{
  sops.secrets = {
    "amp-api-key" = {
      sopsFile = ./. + "/${config.networking.hostName}.yaml";
      key = "amp-api-key";
      restartUnits = [ "amp-runner.service" ];
    };

    "amp-github-token" = {
      sopsFile = ./. + "/${config.networking.hostName}.yaml";
      key = "amp-github-token";
      restartUnits = [ "amp-runner.service" ];
    };
  };
}
