{ config, lib, ... }:
{
  options.my.icons = {
    enable = lib.mkEnableOption "Icon support for Neovim";
  };

  config = lib.mkIf config.my.icons.enable {
    plugins.mini-icons = {
      enable = true;
      mockDevIcons = true;
    };
  };
}
