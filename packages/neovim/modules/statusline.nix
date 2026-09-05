{ config, lib, ... }:
{
  options.my.statusline = {
    engine = lib.mkOption {
      type = lib.types.enum [
        "mini"
        "native"
      ];
      default = "native";
      description = "The statusline engine to use.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.statusline.engine == "mini") {
      plugins.mini-statusline = {
        enable = true;

        lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
          event = "DeferredUIEnter";
        };

        settings = {
          use_icons = config.my.icons.enable;
        };
      };
    })
  ];
}
