{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
  ];

  users.users.sam = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };
}
