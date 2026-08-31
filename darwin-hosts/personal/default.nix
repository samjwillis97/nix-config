{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];

    desktop.enable = true;
    dix.enable = true;
  };

  services.tailscale.enable = true;

  system.primaryUser = "samuel.willis";

  system.stateVersion = 5;
}
