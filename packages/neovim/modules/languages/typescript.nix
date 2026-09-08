{
  config,
  lib,
  ...
}:
{
  options.my.languages.typescript = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.languages.all;
      description = "Enable typescript language support";
    };

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

      (lib.mkIf config.my.languages.typescript.lsp {
        plugins.lsp.servers = {
          ts_ls.enable = true;
          eslint.enable = true;
        };
      })

      (lib.mkIf config.my.languages.typescript.formatter {
        plugins.conform-nvim.settings = {
          formatters_by_ft.typescript = [ "prettier" ];

          # Prettier with dynamic lookup
          formatters = {
            prettier.__raw = ''
              function(bufnr)
                local prettierExists = vim.fn.executable('prettier') == 1
                if prettierExists == true then
                  prettierScript = "prettier"
                else
                  prettierScript = ""
                end
                return {
                  command = prettierScript,
                }
              end
            '';
          };
        };
      })
    ]
  );
}
