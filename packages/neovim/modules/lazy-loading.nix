{ config, lib, ... }:
{
  options.my.lazyLoading = {
    enable = lib.mkEnableOption "Enable lazy loading for Neovim plugins";
  };

  config = lib.mkIf config.my.lazyLoading.enable {
    plugins.lz-n.enable = true;
  };
}
