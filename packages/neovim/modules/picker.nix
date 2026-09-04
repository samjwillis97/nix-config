{
  pkgs,
  config,
  lib,
  ...
}:
let
  bordersEnabled = config.my.theme.windowBorders != "none";

  explorerLayout = {
    hidden = [ "preview" ];
    layout = {
      height = 0.8;
      width = 0.35;
      backdrop = false;
      min_width = 40;
      max_width = 100;
      min_height = 2;
      box = "vertical";
      border = bordersEnabled;
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
in
{
  options.my.picker = {
    enable = lib.mkEnableOption "Enable fuzzy finder for Neovim";
  };

  config = lib.mkIf config.my.picker.enable (
    lib.mkMerge [
      {
        extraPackages = with pkgs; [
          fd
          ripgrep
        ];

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
          {
            key = "<leader>ff";
            action = "<CMD>lua Snacks.picker.files()<CR>";
            options.desc = "Open file search";
          }
          {
            key = "<leader>sf";
            action = "<CMD>lua Snacks.picker.git_grep()<CR>";
            options.desc = "Open grep over git files";
          }
          {
            key = "<leader>sw";
            action = "<CMD>lua Snacks.picker.grep_word()<CR>";
            options.desc = "Open grep for word under cursor";
          }
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
        ];

        plugins.snacks = {
          enable = true;

          settings = {
            picker = {
              sources = {
                files = { };

                git_grep = { };

                grep_word = { };

                lsp_definitions = { };

                lsp_references = { };

                lsp_implementations = { };

                explorer = {
                  auto_close = true;
                  hidden = true;
                  layout = explorerLayout;
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
            };
          };
        };
      }
    ]
  );
}
