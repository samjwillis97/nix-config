{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      silver-searcher
      vim
      # nnn
      tmux
      zsh
      unzip
      htop
      wget
      bitwarden-cli
      jless
    ];
  };
}
