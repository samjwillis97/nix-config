{ lib, ... }:
{
  nixpkgs.hostPlatform = {
    system = "aarch64-darwin";
  };

  ids.gids.nixbld = 30000;

  my = {
    users = [ "samuel.willis" ];
    home-manager.enable = true;
    styling.enable = true;
    desktop.enable = true;
    work.enable = true;
    dix.enable = true;
  };

  system = {
    primaryUser = "samuel.willis";
    defaults.dock.orientation = lib.mkForce "bottom";
    stateVersion = 5;
  };
}
