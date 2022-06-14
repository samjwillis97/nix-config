{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      # Python
      python3Full

      # Node
      nodejs
      nodePackages.npm
      nodePackages.typescript

      # Go
      go
      go-outline
      go-tools
      gopls

      # IDE
      jetbrains.pycharm-community
      jetbrains.webstorm
    ];
  };
}
