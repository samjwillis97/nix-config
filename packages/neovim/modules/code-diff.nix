{ config, lib, ... }:
{
  options.my.code-diff = {
    enable = lib.mkEnableOption "Enable code-diff module";
  };

  config = lib.mkIf config.my.code-diff.enable {
    keymaps = [
      {
        key = "<leader>dvt";
        action = "<CMD>DiffviewToggle<CR>";
        options.desc = "Toggle Diffview";
      }
      {
        key = "<leader>dvo";
        action = "<CMD>DiffviewOpen<CR>";
        options.desc = "Open Diffview";
      }
      {
        key = "<leader>dvc";
        action = "<CMD>DiffviewClose<CR>";
        options.desc = "Close Diffview";
      }
      {
        key = "<leader>dvb";
        action = "<CMD>DiffviewBranchSelect<CR>";
        options.desc = "Open Diffview to branch";
      }
      {
        key = "<leader>fh";
        action = "<CMD>DiffviewFileHistory %<CR>";
        options.desc = "Open Diffview file history";
      }
    ];

    plugins.diffview = {
      enable = true;

      lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
        cmd = [
          "DiffviewOpen"
          "DiffviewClose"
          "DiffviewToggle"
          "DiffviewBranchSelect"
        ];
        keys = [
          "<leader>dvt"
          "<leader>dvo"
          "<leader>dvc"
          "<leader>dvb"
        ];
      };

      settings = {
        view = {
          default = {
            winbar_info = true;
          };

          merge_tool = {
            winbar_info = true;
          };
        };
      };
    };

    extraConfigLuaPost = lib.mkIf (config.my.picker.engine == "snacks") ''
      -- Create a custom picker using the git_branches picker
      local function custom_git_branches_picker()
        Snacks.picker.git_branches({
          confirm = function(picker, item)
            picker:close()
            vim.cmd('DiffviewOpen ' .. item.branch)
          end,
        })
      end

      -- Create a command to call the custom picker
      vim.api.nvim_create_user_command('DiffviewBranchSelect', custom_git_branches_picker, {})
    '';
  };
}
