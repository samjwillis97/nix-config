{ pkgs, ... }:
{
  programs = {
    dircolors = {
      enable = true;
      enableZshIntegration = false;
    };

    direnv = {
      enable = true;
      enableZshIntegration = false;
      nix-direnv.enable = true;
      config = {
        hide_env_diff = true;
        warn_timeout = "30s"; # Reduce timeout overhead
      };
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
