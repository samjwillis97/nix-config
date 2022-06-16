{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      ag
      vim
      # nnn
      tmux
      zsh
      unzip
      htop
      wget
      bitwarden-cli
    ];
  };
}
