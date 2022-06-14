{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      teams
      slack
      discord
    ];
  };
}
