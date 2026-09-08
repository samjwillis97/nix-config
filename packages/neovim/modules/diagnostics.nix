{ config, lib, ... }:
{
  config = lib.mkMerge [
    {
      diagnostic.settings = {
        underline = true;
        virtual_text = false;
        float = {
          border = "rounded";
        };
      };
    }

    (lib.mkIf config.my.icons.enable {
      extraConfigLuaPre = ''
        vim.diagnostic.config {
          signs = {
            text = {
              [vim.diagnostic.severity.ERROR] = '',
              [vim.diagnostic.severity.WARN] = '',
              [vim.diagnostic.severity.INFO] = '',
              [vim.diagnostic.severity.HINT] = '',
            },
          },
        }
      '';
    })
  ];

}
