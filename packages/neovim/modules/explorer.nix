{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.explorer = {
    engine = lib.mkOption {
      type = lib.types.enum [
        "snacks"
        "vinegar"
        "native"
      ];
      default = "vinegar";
      description = "The file explorer engine to use.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.explorer.engine == "snacks") {
      keymaps = [
        {
          key = "<C-n>";
          action = "<CMD>lua Snacks.explorer.open()<CR>";
          options.desc = "Toggle file explorer";
        }
        {
          key = ",n";
          action = "<CMD>lua Snacks.explorer.open()<CR>";
          options.desc = "Toggle file explorer";
        }
      ];

      plugins.snacks = {
        enable = true;

        settings.picker.sources.explorer = {
          auto_close = true;
          hidden = true;
          layout = {
            hidden = [ "preview" ];
            layout = {
              height = 0.8;
              width = 0.35;
              backdrop = false;
              min_width = 40;
              max_width = 100;
              min_height = 2;
              box = "vertical";
              border = config.my.theme.windowBorders;
              title = "{title}";
              title_pos = "center";
              __unkeyed-1 = {
                win = "input";
                height = 1;
                border = "bottom";
              };
              __unkeyed-2 = {
                win = "list";
                border = "none";
              };
              __unkeyed-3 = {
                win = "preview";
                title = "{preview}";
                height = 0.4;
                border = "top";
              };
            };
          };

          win = {
            list = {
              keys = {
                "<C-n>" = "cancel";
                "h" = "explorer_close";
                "o" = "confirm";
                "O" = "explorer_open";
              };
            };
          };
        };
      };
    })

    (lib.mkIf (config.my.explorer.engine == "vinegar") {
      keymaps = [
        {
          key = "<C-n>";
          mode = "n";
          action = "-";
          options = {
            remap = true;
            desc = "Toggle file explorer";
          };
        }
      ];

      extraPlugins = with pkgs.vimPlugins; [ vim-vinegar ];

      extraConfigLua = ''
        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("nixvim_vinegar", { clear = true }),
          pattern = "netrw",
          callback = function(args)
            vim.keymap.set("n", "<C-n>", "<C-^>", {
              buffer = args.buf,
              desc = "Return to previous buffer",
            })
          end,
        })
      '';
    })
  ];
}
