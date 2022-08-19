{ config, lib, pkgs, self, ... }: {
  imports = [
    ./home.nix
  ];

  programs.autorandr = {
    enable = true;
    hooks = {
      postswitch = {
        "notify-i3" = "${pkgs.i3}/bin/i3-msg restart";
        "change-background" = "${pkgs.feh}/bin/feh --bg-scale ${config.home.homeDirectory}/.wallpaper.png";
      };
    };
  };
}
