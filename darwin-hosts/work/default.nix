{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];

    desktop.enable = true;
    work.enable = true;
    dix.enable = true;
  };

  system.primaryUser = "samuel.willis";

  system.stateVersion = 5;
}
