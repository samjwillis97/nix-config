{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
     alacritty
     bitwarden
     flameshot
     atom
    ];
  };
}
