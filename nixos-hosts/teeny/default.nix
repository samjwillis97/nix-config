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
          apiKeyFile = config.sops.secrets."jellyfin/api-key".path;
          adminPasswordFile = config.sops.secrets."jellyfin/admin-password".path;
          openFirewall = true;
          ingress.enable = true;

          xtream = {
            baseUrlFile = config.sops.secrets."xtream/base-url".path;
            usernameFile = config.sops.secrets."xtream/username".path;
            passwordFile = config.sops.secrets."xtream/password".path;

            channels = {
              "234" = [
                "441368"
                "441313"
                "441312"
                "441311"
                "441310"
                "441309"
                "441308"
                "441307"
                "441306"
                "441305"
                "441304"
                "441360"
                "441302"
                "441301"
              ];

              "303" = [
                "588072"
                "588070"
                "588067"
                "588066"
                "2043935"
                "588063"
                "707004"
                "1744758"
              ];

              "1731" = [
                "1290246"
                "1290245"
                "1290247"
                "1290248"
              ];

              "1984" = [
                "1537642"
                "1537641"
                "1537640"
                "1537637"
              ];
            };
          };
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
