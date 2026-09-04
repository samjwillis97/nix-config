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

  pickerLayout = "default";
in
{
  options.my.picker = {
    enable = lib.mkEnableOption "Enable fuzzy finder for Neovim";

    backend = lib.mkOption {
      type = lib.types.enum [
        "snacks"
        "minipick"
      ];
      default = "snacks";
      description = "The fuzzy finder backend to use.";
    };
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
            key = "<leader><leader>";
            action = "<CMD>lua Snacks.picker.pickers()<CR>";
            options.desc = "List all available pickers";
          }
        ];

        plugins.snacks = {
          enable = true;

          settings = {
            picker = {
              layout = pickerLayout;

              sources = {
                files = {
                  show_empty = true;
                  hidden = true;
                  ignored = false;
                };

                git_grep = {
                  untracked = true;
                };

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

      {
        plugins.actions-preview = {
          enable = true;

          lazyLoad.settings = {
            backend = config.my.picker.backend;
            keys = [
              {
                __unkeyed-1 = "<leader>ca";
                __unkeyed-2.__raw = ''
                  function()
                    require('actions-preview').code_actions()
                  end
                '';
                desc = "Code actions preview";
              }
            ];
          };
        };
      }
    ]
  );
}
