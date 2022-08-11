{ configs, pkgs, lib, ... }: {
  home.packages = with pkgs; [
    jetbrains.webstorm
    jetbrains.pycharm-community
    jetbrains.goland
    jetbrains.datagrip
    jetbrains.rider
  ];

  home.file.".ideavimrc".source = ./ideavimrc;
}
