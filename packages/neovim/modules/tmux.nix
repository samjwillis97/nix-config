{ lib, config, ... }:
{
  plugins.tmux-navigator = {
    enable = true;

    # Load on VeryLazy for navigation
    lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
      event = "DeferredUIEnter";
    };
  };
}
