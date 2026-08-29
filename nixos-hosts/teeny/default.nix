{ config
, lib
, secretModules
, ...
}:
{
  imports = [
    ./hardware-configuration.nix
    secretModules.tailscale
    secretModules.cloudflared
    secretModules.media
  ];

  config = {
    boot.plymouth.enable = lib.mkForce false;

    networking = {
      nameservers = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      networkmanager.enable = true;
    };
    systemd.enableEmergencyMode = false;

    my = {
      users = [ "sam" ];
      actual = {
        enable = true;
        ingress.enable = true;
      };

      media = {
        enable = true;

        jellyfin = {
          enable = true;
          apiKeyFile = config.sops.secrets."jellyfin-api-key".path;
          openFirewall = true;
          ingress.enable = true;
        };
      };

      cloudflared = {
        enable = true;
        connector = {
          enable = true;
          tokenFile = config.sops.secrets."cloudflared-token".path;
        };
      };

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };

      deploy-rs = {
        enable = true;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2FeFN6YQEUr22lJCeuQHcDawLuAPnoizlZLJOwhch4 sam@williscloud.org"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYyMM/qTTLsXdPvvfkhdufg9gLYOI2y8d1oDpAgI0ft samjwillis97@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+XxL2uM1FT0dR3T5cOJxJd+9luPMctdZd+O2LlJsRk sam@Sams-MacBook-Air.local"
        ];
      };
    };
  };

}
