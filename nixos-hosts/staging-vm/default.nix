{ config
, inputs
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
    (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
  ];

  config = {
    # qemu-vm boots the kernel directly unless useBootLoader is enabled.
    boot.loader = {
      grub.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
    };

    my = {
      users = [ "sam" ];
      home-manager.enable = true;

      styling.enable = true;

      desktop.enable = true;

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
          };
        };
      };

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };

      virtualisation.containers.enable = true;

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
