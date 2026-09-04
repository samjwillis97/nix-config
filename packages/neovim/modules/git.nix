{
  pkgs,
  config,
  lib,
  ...
}:
let
  fugitiveKeymaps = [
    {
      key = "<leader>gg";
      action = "<CMD>Git<CR>";
      options.desc = "Show fugitive interface";
    }
    {
      key = "<leader>go";
      action = "<CMD>GBrowse<CR>";
      mode = [
        "n"
        "v"
      ];
      options.desc = "Open in GitHub";
    }
    {
      key = "<leader>gy";
      action = "<CMD>GBrowse!<CR>";
      mode = [
        "n"
        "v"
      ];
      options.desc = "Copy GitHub URL";
    }
  ];

  gitSignsKeymaps = [
    {
      key = "[g";
      action = "<CMD>Gitsigns prev_hunk<CR>";
      options.desc = "Go to previous git change";
    }
    {
      key = "]g";
      action = "<CMD>Gitsigns next_hunk<CR>";
      options.desc = "Go to next git change";
    }
    {
      key = "<leader>gb";
      action = "<CMD>:Gitsigns blame<CR>";
      options.desc = "Show git blame for file";
    }
  ];
in
{
  options.my.git = {
    enable = lib.mkEnableOption "rich git integration";
  };

  config = lib.mkIf config.my.git.enable {
    keymaps = fugitiveKeymaps ++ gitSignsKeymaps;

    opts.signcolumn = "yes";

    plugins = {
      gitsigns = {
        enable = true;

        settings = { };

        lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
          event = "BufReadPost";
          keys = gitSignsKeymaps.map (k: k.key);
        };
      };

      fugitive = {
        enable = true;

        # Lazy load on git commands and keymaps
        lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
          cmd = [
            "Git"
            "GBrowse"
          ];
          keys = fugitiveKeymaps.map (k: k.key);
        };
      };
    };

    # vim-rhubarb provides :GBrowse GitHub integration for fugitive.
    # Loaded as a fugitive dependency via lz.n so both are available together.
    extraConfigLua = lib.mkIf config.my.lazyLoading.enable ''
      require("lz.n").load({
        {
          "vim-rhubarb",
          dep_of = { "vim-fugitive" },
        },
      })
    '';

    extraPlugins = with pkgs.vimPlugins; [ vim-rhubarb ];
  };
}
