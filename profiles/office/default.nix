{ config, lib, pkgs, self, ... }: {
  environment = {
    systemPackages = with pkgs; [
      libreoffice
    ];
  };
}
