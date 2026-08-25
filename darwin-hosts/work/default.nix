{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];
  };

  system.stateVersion = 5;
}
