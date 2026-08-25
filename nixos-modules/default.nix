# This is the default nixos module.
# It will be included with any nixos host configuration that has `importDefault = true`, which is the default
{ inputs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
    registry = {
      nixpkgs.flake = inputs.nixpkgs;
    };

    extraOptions = "fallback = true";

    optimise.automatic = true;

    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 30d";
    };

    settings = {
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  boot = {
    loader = {
      timeout = 0;
      systemd-boot = {
        configurationLimit = 5;
      };
    };
  };
}
