{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
  ];

  config.my.users = [ "sam" ];
  config.my.home-manager.enable = true;
}
