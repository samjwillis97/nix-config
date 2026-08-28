{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];

    desktop.enable = true;
    work.enable = true;
  };

  system.stateVersion = 5;
}
