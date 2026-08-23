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

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };
    };
  };

}
