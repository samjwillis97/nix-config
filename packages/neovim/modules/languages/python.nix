{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.languages.python = {
    enable = lib.mkEnableOption "Enable python language support";

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable python language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable python debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable python code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.python.enable (
    lib.mkMerge [
      (lib.mkIf config.my.languages.python.lsp {
        plugins.lsp.servers.pyright.enable = true;
      })

      (lib.mkIf config.my.languages.python.dap {
        plugins.dap-python.enable = true;
      })

      (lib.mkIf config.my.languages.python.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.python = [ "black" ];

          formatters.black.command = lib.getExe pkgs.black;
        };
      })
    ]
  );
}
