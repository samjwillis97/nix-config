{
  inputs,
  ...
}:
{
  system = {
    defaults.CustomSystemPreferences = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };

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
      options = "--delete-older-than 30d";
    };

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "admin"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  documentation = {
    enable = true;
    man.enable = true;
  };
}
