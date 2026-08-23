{ config
, inputs
, secretModules
, ...
}:
{
  imports = [
    ./hardware-configuration.nix
    secretModules.tailscale
    (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
  ];

  config = {
    my = {
      users = [ "sam" ];
      home-manager.enable = true;

      styling.enable = true;

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
