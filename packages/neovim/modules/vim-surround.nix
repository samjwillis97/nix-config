{ config, lib, ... }:
{
  plugins.vim-surround = {
    enable = true;

    lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
      keys = [
        "ys"
        "ds"
        "cs"
        "yS"
        "cS"
      ];
    };
  };
}
