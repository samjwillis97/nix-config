{ config, lib, ... }:
{
  options.my.treesitter = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable treesitter support";
    };

    grammars = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with config.plugins.treesitter.package.builtGrammars; [
        json
        toml
        yaml
        markdown
        bash
        nix
      ];
      description = "Install these treesitter grammars, for all use `config.plugins.treesitter.package.allGrammars
`";
    };

    showContext = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show treesitter context";
    };
  };

  config = lib.mkIf config.my.treesitter.enable (
    lib.mkMerge [
      {
        plugins.treesitter = {
          enable = true;

          # Load when reading a buffer for syntax highlighting
          lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
            event = "BufReadPost";
          };

          grammarPackages = config.my.treesitter.grammars;

          nixvimInjections = true;
          nixGrammars = true;

          settings = {
            highlight.enable = true;
            indent.enable = true;
          };
        };
      }

      (lib.mkIf config.my.treesitter.showContext {
        highlightOverride = {
          "TreesitterContextBottom" = {
            underline = false;
          };
          "TreesitterContextLineNumberBottom" = {
            underline = false;
          };
        };

        plugins.treesitter-context = {
          enable = true;

          # Load after buffer is read (after treesitter)
          lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
            event = "BufReadPost";
          };

          settings = {
            line_numbers = true;
            max_lines = 10;
            multiline_threshold = 5;
          };
        };
      })
    ]
  );
}
