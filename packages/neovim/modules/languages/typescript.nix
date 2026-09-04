{
  config,
  lib,
  ...
}:
{
  options.my.languages.typescript = {
    enable = lib.mkEnableOption "Enable typescript language support";

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable typescript language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable typescript debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable typescript code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.typescript.enable (
    lib.mkMerge [
      {
        plugins.ts-comments = {
          enable = true;
        };
      }
    ]
  );
}
