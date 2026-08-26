{ pkgs, ... }:
{
  programs = {
    dircolors = {
      enable = true;
      enableZshIntegration = false;
    };

    bat = {
      enable = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = false;
    };
  };

  home.packages = with pkgs; [
    ripgrep
    zip
    unzip
    htop
  ];
}
