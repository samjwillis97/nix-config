{ config, lib, ... }:
{
  options.my.git = {
    enable = lib.mkEnableOption "rich git integration";
  };

  config = lib.mkIf config.my.git.enable {
    keymaps = [
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

    opts.signcolumn = "yes";

    plugins.gitsigns = {
      enable = true;

      settings = { };

      lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
        event = "BufReadPost";
        keys = [
          "[g"
          "]g"
          "<leader>gb"
        ];
      };
    };
  };
}
