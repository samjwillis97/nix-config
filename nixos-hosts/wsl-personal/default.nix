{ inputs, ... }:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  config = {
    nixpkgs.hostPlatform = {
      system = "x86_64-linux";
    };

    wsl.enable = true;
    wsl.defaultUser = "sam";

    system.stateVersion = "26.05";

    my = {
      users = [ "sam" ];
      dix.enable = true;
    };
  };
}
