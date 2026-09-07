{ config, lib, ... }:
{
  options.my.statusline = {
    engine = lib.mkOption {
      type = lib.types.enum [
        "mini"
        "native"
      ];
      default = "native";
      description = "The statusline engine to use.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.statusline.engine == "mini") {
      plugins.mini-statusline = {
        enable = true;

        lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
          event = "DeferredUIEnter";
        };

        settings = {
          use_icons = config.my.icons.enable;

          content = {
            active.__raw = ''
              function()
                local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
                local git           = MiniStatusline.section_git({ trunc_width = 40 })
                local diff          = MiniStatusline.section_diff({ trunc_width = 75 })
                local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
                local lsp           = MiniStatusline.section_lsp({ trunc_width = 75 })

                local filename = vim.fn.fnamemodify(
                  vim.api.nvim_buf_get_name(0),
                  ':.'
                ) .. '%m%r'

                local fileinfo = MiniStatusline.section_fileinfo({ trunc_width = 120 })
                local location = MiniStatusline.section_location({ trunc_width = 75 })

                return MiniStatusline.combine_groups({
                  { hl = mode_hl,                 strings = { mode } },
                  { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
                  '%<',
                  { hl = 'MiniStatuslineFilename', strings = { filename } },
                  '%=',
                  { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
                  { hl = mode_hl,                 strings = { location } },
                })
              end
            '';

            inactive.__raw = ''
              function()
                local filename = vim.fn.fnamemodify(
                  vim.api.nvim_buf_get_name(0),
                  ':.'
                ) .. '%m%r'

                return MiniStatusline.combine_groups({
                  { hl = 'MiniStatuslineFilename', strings = { filename } },
                })
              end
            '';
          };
        };
      };
    })
  ];
}
