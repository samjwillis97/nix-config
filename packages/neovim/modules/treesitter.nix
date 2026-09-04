{ config, lib, ... }:
{
  plugins.treesitter = {
    enable = true;

    # Load when reading a buffer for syntax highlighting
    lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
      event = "BufReadPost";
    };

    nixvimInjections = true;
    nixGrammars = true;

    settings = {
      highlight.enable = true;
      indent.enable = true;
    };
  };
}
