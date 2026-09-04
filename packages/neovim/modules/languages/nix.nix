{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.languages.nix = {
    enable = lib.mkEnableOption "Enable nix language support";

    lsp = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.lsp;
      description = "Enable nix language server protocol support";
    };

    dap = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.dap;
      description = "Enable nix debug adapter protocol support";
    };

    formatter = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.formatter;
      description = "Enable nix code formatter support";
    };
  };

  config = lib.mkIf config.my.languages.nix.enable (
    lib.mkMerge [
      (lib.mkIf config.my.languages.nix.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.nix = [ "nixfmt" ];

          formatters = {
            nixfmt = {
              command = lib.getExe pkgs.nixfmt;
            };
          };
        };
      })
    ]
  );
}
