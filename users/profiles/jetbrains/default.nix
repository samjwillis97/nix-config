{ configs, pkgs, lib, ... }: {
  home.packages = [
    pkgs.jetbrains.webstorm
    pkgs.jetbrains.pycharm-community
  ];

  home.file.".ideavimrc".source = ./ideavimrc;
}
