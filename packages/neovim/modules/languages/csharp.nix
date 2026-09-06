{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.languages.csharp = {
    enable = lib.mkEnableOption "Enable csharp language support";

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable csharp language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable csharp debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable csharp code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.csharp.enable (
    lib.mkMerge [
      (lib.mkIf config.my.languages.csharp.lsp {
        plugins.lsp.servers.omnisharp.enable = true;
      })

      (lib.mkIf config.my.languages.csharp.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.cs = [ "csharpier" ];

          formatters.csharpier.command = lib.getExe pkgs.csharpier;
        };
      })
    ]
  );
}
