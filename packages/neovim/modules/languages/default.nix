{
  config,
  lib,
  ...
}:
let
  languageModules = map (v: ./. + "/${v}") (
    lib.filter (file: file != "default.nix") (builtins.attrNames (builtins.readDir ./.))
  );

  lazyLoadingEnabled = config.my.lazyLoading.enable;
in
{
  imports = languageModules;

  options.my.languages = {
    lsp = lib.mkEnableOption "Enable language server protocol support";
    dap = lib.mkEnableOption "Enable debug adapter protocol support";
    formatter = lib.mkEnableOption "Enable code formatter support";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.languages.formatter {
      plugins.conform-nvim = {
        enable = true;

        lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
          event = "BufWritePre";
          cmd = [ "ConformInfo" ];
        };

        settings = {
          notify_no_formatters = false;

          formatters_by_ft = {
          };

          # Format on save with timeout and LSP fallback
          format_on_save.__raw = ''
            function(bufnr)
              if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
              end

              return { timeout_ms = 200, lsp_fallback = true }
            end
          '';
        };

        # Commands to enable/disable formatting
        luaConfig = {
          post = ''
            vim.api.nvim_create_user_command("FormatDisable", function(args)
              if args.bang then
                -- FormatDisable! will disable formatting just for this buffer
                vim.b.disable_autoformat = true
              else
                vim.g.disable_autoformat = true
              end
            end, {
              desc = "Disable autoformat-on-save",
              bang = true,
            })

            vim.api.nvim_create_user_command("FormatEnable", function()
              vim.b.disable_autoformat = false
              vim.g.disable_autoformat = false
            end, {
              desc = "Re-enable autoformat-on-save",
            })
          '';
        };
      };
    })

    (lib.mkIf config.my.languages.lsp {
      keymaps =
        if config.plugins.snacks.enable then
          [
            {
              key = "gd";
              action = "<CMD>lua Snacks.picker.lsp_definitions()<CR>";
              options.desc = "Go to definition";
            }
            {
              key = "gr";
              action = "<CMD>lua Snacks.picker.lsp_references()<CR>";
              options.desc = "Find references";
            }
            {
              key = "gi";
              action = "<CMD>lua Snacks.picker.lsp_implementations()<CR>";
              options.desc = "Find implementations";
            }

          ]
        else
          [
            {
              key = "gd";
              action = "<CMD>lua vim.lsp.buf.definition()<CR>";
              options.desc = "Go to definition";
            }
            {
              key = "gr";
              action = "<CMD>lua vim.lsp.buf.references()<CR>";
              options.desc = "Find references";
            }
            {
              key = "gi";
              action = "<CMD>lua vim.lsp.buf.implementation()<CR>";
              options.desc = "Find implementations";
            }
          ];

      plugins.lsp = {
        enable = true;

        lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
          event = "BufReadPre";
        };

        keymaps.lspBuf = {
          "gD" = "declaration";
          "K" = "hover";
          "<leader>k" = "signature_help";
          "<leader>t" = "type_definition";
          "<leader>r" = "rename";
        };

        luaConfig = {
          post = ''
            vim.diagnostic.config({
              underline = true,
              signs = true,
              update_in_insert = false,
            })
          '';
        };
      };
    })

  ];
}
