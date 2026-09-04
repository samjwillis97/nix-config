{
  globals = {
    # Leader is `\`
    mapleader = "\\";
  };

  keymaps = [
    {
      key = "jk";
      mode = "i";
      action = "<Esc>";
    }
    {
      key = "<leader><space>";
      mode = "n";
      action = "<CMD>nohlsearch<CR>";
    }
    {
      key = "j";
      action = "gj";
      options.desc = "Move down by visual line";
    }
    {
      key = "k";
      action = "gk";
      options.desc = "Move up by visual line";
    }
    {
      key = "<C-J>";
      action = "<CMD>NavigatorDown<CR>";
      options.desc = "Move to window below";
    }
    {
      key = "<C-K>";
      action = "<CMD>NavigatorUp<CR>";
      options.desc = "Move to window above";
    }
    {
      key = "<C-L>";
      action = "<CMD>NavigatorRight<CR>";
      options.desc = "Move to window right";
    }
    {
      key = "<C-H>";
      action = "<CMD>NavigatorLeft<CR>";
      options.desc = "Move to window left";
    }
    {
      key = "<C-U>";
      action = "<C-U>zz";
    }
    {
      key = "<C-D>";
      action = "<C-D>zz";
    }
    {
      key = "<C-I>";
      action = "<C-I>zz";
    }
    {
      key = "<C-O>";
      action = "<C-O>zz";
    }
    {
      key = "n";
      action = "nzz";
    }
    {
      key = "N";
      action = "Nzz";
    }
    {
      key = "GG";
      action = "GGzz";
    }
    {
      key = "[d";
      action = "<CMD>lua vim.diagnostic.goto_prev()<CR>";
    }
    {
      key = "]d";
      action = "<CMD>lua vim.diagnostic.goto_next()<CR>";
    }
  ];
}
