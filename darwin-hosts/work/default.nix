{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  my = {
    users = [ "samuel.willis" ];
    home-manager.enable = true;
    styling.enable = true;
    desktop.enable = true;
    work.enable = true;
    dix.enable = true;

    microvms = {
      enable = true;

      guests.shell = {
        autostart = false;
        sshPort = 2222;
      };
    };
  };

  system.primaryUser = "samuel.willis";

  system.stateVersion = 5;
}
