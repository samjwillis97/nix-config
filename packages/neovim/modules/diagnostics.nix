{
  diagnostic.settings = {
    underline = true;
    virtual_text = false;
    float = {
      border = "rounded";
    };
  };

  # TODO: Only with nerdfonts installed
  # extraConfigLuaPre = ''
  #   vim.diagnostic.config {
  #     signs = {
  #       text = {
  #         [vim.diagnostic.severity.ERROR] = '',
  #         [vim.diagnostic.severity.WARN] = '',
  #         [vim.diagnostic.severity.INFO] = '',
  #         [vim.diagnostic.severity.HINT] = '',
  #       },
  #     },
  #   }
  # '';
}
