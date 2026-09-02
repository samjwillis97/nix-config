{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "sam" ];

    home-manager.enable = true;
    desktop.enable = true;
    styling.enable = true;
    dix.enable = true;
  };

  services.tailscale.enable = true;

  system.primaryUser = "sam";

  system.stateVersion = 5;
}
