{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.languages.golang = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.all;
      description = "Enable Go language support";
    };

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable golang language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable golang debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable golang code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.golang.enable (
    lib.mkMerge [
      (lib.mkIf config.my.languages.golang.lsp {
        plugins.lsp.servers.gopls.enable = true;
      })

      (lib.mkIf config.my.languages.golang.dap {
        plugins.dap-go = {
          enable = true;

          settings.delve.path = lib.getExe pkgs.delve;
        };
      })

      (lib.mkIf config.my.languages.golang.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.go = [ "gofmt" ];

          formatters.gofmt.command = lib.getExe' pkgs.go "gofmt";
        };
      })
    ]
  );
}
