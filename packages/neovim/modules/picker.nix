{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.picker = {
    enable = lib.mkEnableOption "Enable fuzzy finder for Neovim";

    engine = lib.mkOption {
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
      (lib.mkIf (config.my.picker.engine == "minipick") {
        extraPackages = with pkgs; [
          fd
          ripgrep
        ];

        keymaps = [
          {
            key = "<leader>ff";
            action = "<CMD>lua MiniPick.builtin.files()<CR>";
            options.desc = "Open file search";
          }
          {
            key = "<leader>sf";
            action = "<CMD>lua MiniPick.builtin.grep({ tool = 'git' })<CR>";
            options.desc = "Open grep over git files";
          }
        ];

        plugins.mini-pick = {
          enable = true;

          settings = {

          };
        };
      })

      (lib.mkIf (config.my.picker.engine == "snacks") {
        extraPackages = with pkgs; [
          fd
          ripgrep
        ];

        keymaps = [
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
              layout = "default";

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
              };
            };
          };
        };
      })

      {
        keymaps = [
          {
            key = "<leader>ca";
            action = "<CMD>require(`actions-preview`).code_actions<CR>";
            options.desc = "Open code actions";
          }
        ];

        plugins.actions-preview = {
          enable = true;

          lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
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
