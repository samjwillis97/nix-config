{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      plexamp
      plex-media-player
    ];
  };
}
