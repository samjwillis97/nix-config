{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];
    home-manager.enable = true;
    desktop.enable = true;
    work.enable = true;
    dix.enable = true;
  };

  system.primaryUser = "samuel.willis";

  system.stateVersion = 5;
}
