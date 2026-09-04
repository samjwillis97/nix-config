{ config, lib, ... }:
{
  options.my.statusline = {
    enable = lib.mkEnableOption "enhanced statusline";
  };

  config = lib.mkIf config.my.statusline.enable {
    plugins.mini-statusline = {
      enable = true;

      lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
        event = "DeferredUIEnter";
      };

      settings = {
        use_icons = config.my.icons.enable;
      };
    };
  };
}
