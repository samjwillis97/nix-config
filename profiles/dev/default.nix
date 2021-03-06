{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      # Python
      python3Full

      # Node
      nodejs
      nodePackages.npm
      nodePackages.typescript
      nodePackages.node2nix

      # Go
      go
      go-outline
      go-tools
      gopls
    ];
  };

  virtualisation.docker.enable = true;
}
