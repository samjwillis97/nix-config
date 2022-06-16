{ configs, pkgs, lib, ... }: {
  home.packages = with pkgs; [
    jetbrains.webstorm
    jetbrains.pycharm-community
    mongodb-compass
  ];

  home.file.".ideavimrc".source = ./ideavimrc;
}
