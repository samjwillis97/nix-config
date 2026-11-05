{
  inputs,
  ...
}:
{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  nixpkgs.hostPlatform = {
    system = "x86_64-linux";
  };

  wsl = {
    enable = true;
    defaultUser = "sam";
  };

  system.stateVersion = "26.05";

  my = {
    users = [ "sam" ];
    home-manager.enable = true;
    styling.enable = true;
    work.enable = true;
  };
}
