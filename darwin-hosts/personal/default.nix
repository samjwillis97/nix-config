{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];

    desktop.enable = true;
  };

  services.tailscale.enable = true;

  system.stateVersion = 5;
}
