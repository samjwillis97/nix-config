{ config, ... }:
{
  my = {
    git.enable = true;

    treesitter = {
      showContext = true;
      grammars = config.plugins.treesitter.package.allGrammars;
    };

    theme = {
      rainbowBrackets = true;
      indents = {
        enable = true;
        rainbow = false;
      };
    };

    icons.enable = true;

    completions = {
      engine = "blink-cmp";
      copilot = {
        suggestion.enabled = true;
        nextEdits.enabled = false;
      };
    };

    languages = {
      all = true;
      formatter = true;
      lsp = true;
      dap = true;
    };

    picker = {
      enable = true;
      engine = "snacks";
    };

    explorer = {
      engine = "snacks";
      windowBorders = true;
    };

    statusline.engine = "mini";

    folding.engine = "ufo";

    code-diff.enable = true;
  };
}
