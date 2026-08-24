{ config, ... }:
{
  sops.secrets = {
    "cloudflared-token" = {
      sopsFile = ./. + "/${config.networking.hostName}.yaml";
    };
  };
}
