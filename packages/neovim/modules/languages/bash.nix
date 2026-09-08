{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.languages.bash = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.all;
      description = "Enable bash language support";
    };

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable bash language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable bash debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable bash code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.bash.enable (
    lib.mkMerge [
      (lib.mkIf config.my.languages.bash.lsp {
        plugins.lsp.servers.bashls.enable = true;
      })

      (lib.mkIf config.my.languages.bash.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.bash = [ "shfmt" ];

          formatters.shfmt.command = lib.getExe pkgs.shfmt;
        };
      })
    ]
  );
}
