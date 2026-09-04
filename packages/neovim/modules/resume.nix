{ config, lib, ... }:
{
  options.my.resume = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable resume cursor position on file open";
    };
  };

  config = lib.mkIf config.my.resume.enable {
    plugins.lastplace = {
      enable = true;

      # Load before reading a buffer to restore cursor position
      lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
        event = "BufReadPre";
      };
    };
  };
}
