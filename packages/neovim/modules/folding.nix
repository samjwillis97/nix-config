{ config, lib, ... }:
{
  options.my.folding = {
    engine = lib.mkOption {
      type = lib.types.enum [
        "treesitter"
        "ufo"
      ];
      default = "treesitter";
      description = "Folding engine to use";
    };
  };

  config = lib.mkMerge [
    {
      opts = {
        foldenable = true;
        foldlevel = 99;
        foldlevelstart = 99;
        foldcolumn = "0";
      };
    }

    (lib.mkIf (config.my.folding.engine == "treesitter") {

      plugins.treesitter.folding.enable = true;

      # nvim-treesitter's current rewrite leaves folding setup to Neovim.
      extraConfigLua = ''
        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("nixvim_treesitter_folding", { clear = true }),
          pattern = "*",
          callback = function()
            vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.wo[0][0].foldmethod = "expr"
          end,
        })
      '';
    })

    (lib.mkIf (config.my.folding.engine == "ufo") {
      keymaps = [
        {
          key = "zR";
          action = "<CMD>lua require('ufo').openAllFolds()<CR>";
        }
        {
          key = "zM";
          action = "<CMD>lua require('ufo').closeAllFolds()<CR>";
        }
      ];

      plugins.nvim-ufo = {
        enable = true;

        settings.provider_selector = lib.nixvim.utils.mkRaw ''
          function(bufnr)
            -- Diffview virtual buffers have non-file URIs that clangd rejects.
            if vim.api.nvim_buf_get_name(bufnr):match("^diffview://") then
              return ""
            end

            return { "lsp", "indent" }
          end
        '';

        # Load when reading a buffer or using fold operations
        lazyLoad.settings = lib.mkIf config.my.lazyLoading.enable {
          event = "BufReadPost";
        };
      };
    })
  ];
}
