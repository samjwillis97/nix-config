{
  config,
  inputs,
  secretModules,
  ...
}:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    secretModules.tailscale
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
      home-manager.enable = true;
      styling.enable = true;

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };
    };
  };
}
