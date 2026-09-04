{ config, lib, ... }:
{
  options.my.icons = {
    enable = lib.mkEnableOption "Icon support for Neovim";
  };

  config = lib.mkIf config.my.icons.enable {
    plugins.web-devicons = {
      # DO NOT LAZY LOAD
      # common dependency
      enable = true;
    };
  };
}
