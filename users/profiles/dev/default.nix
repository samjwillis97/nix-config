{ configs, pkgs, lib, ... }: {
  home.packages = with pkgs; [
    jetbrains.webstorm
    jetbrains.pycharm-community
    mongodb-compass
  ];

  # TODO: Add Goland

  home.file.".ideavimrc".source = ./ideavimrc;
}
