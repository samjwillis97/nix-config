{ config, lib, ... }:
let
  lazyLoadingEnabled = config.my.lazyLoading.enable;

  themeRainbowLookup = {
    "catppuccin" = {
      "RainbowRed" = "#F38BA8";
      "RainbowYellow" = "#F9E2AF";
      "RainbowBlue" = "#89B4FA";
      "RainbowOrange" = "#FAB387";
      "RainbowGreen" = "#A6E3A1";
      "RainbowViolet" = "#B4BEFE";
      "RainbowCyan" = "#89DCEB";
    };
    "default" = {
      "RainbowRed" = "#E06C75";
      "RainbowYellow" = "#E5C07B";
      "RainbowBlue" = "#61AFEF";
      "RainbowOrange" = "#D19A66";
      "RainbowGreen" = "#98C379";
      "RainbowViolet" = "#C678DD";
      "RainbowCyan" = "#56B6C2";
    };
  };

  highlightNames = builtins.attrNames themeRainbowLookup.default;
in
{
  options.my.theme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the theme module.";
    };

    theme = lib.mkOption {
      type = lib.types.enum [
        "catppuccin"
      ];
      default = "catppuccin";
      description = "The theme to use.";
    };

    transparentBackground = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable transparent background for the theme.";
    };

    rainbowIndents = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable rainbow indents for the theme.";
    };

    rainbowBrackets = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable rainbow brackets for the theme.";
    };
  };

  config = lib.mkIf config.my.theme.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              !(config.my.theme.rainbowIndents || config.my.theme.rainbowBrackets)
              || builtins.hasAttr config.my.theme.theme themeRainbowLookup;
            message = "${config.my.theme.theme} missing from themeRainbowLookup, please add it to the lookup table.";
          }
        ];
      }

      (lib.mkIf config.my.theme.transparentBackground {
        plugins.transparent = {
          enable = true;

          lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
            event = "DeferredUIEnter";
          };
        };
      })

      (lib.mkIf (config.my.theme.theme == "catppuccin") {
        colorschemes = {
          catppuccin = {
            autoLoad = true;
            enable = true;

            # Lazy load colorscheme
            lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
              colorscheme = "catppuccin";
            };

            settings = {
              flavour = "mocha";
              integrations = {
                # cmp = true;
                gitsigns = config.plugins.gitsigns.enable;
                treesitter = config.plugins.treesitter.enable;
                # diffview = true;
                # fidget = true;
                # which_key = true;

                native_lsp = {
                  enabled = true;
                  virtual_text = {
                    errors = [ "italic" ];
                    hints = [ "italic" ];
                    warnings = [ "italic" ];
                    information = [ "italic" ];
                    ok = [ "italic" ];
                  };
                  underlines = {
                    errors = [ "underline" ];
                    hints = [ "underline" ];
                    warnings = [ "underline" ];
                    information = [ "underline" ];
                    ok = [ "underline" ];
                  };
                  inlay_hints = {
                    background = true;
                  };
                };
              };

              transparent_background = config.my.theme.transparentBackground;

              dim_inactive = {
                enabled = true;
              };
            };
          };
        };
      })

      (lib.mkIf (config.my.theme.rainbowIndents || config.my.theme.rainbowBrackets) {
        highlightOverride = builtins.mapAttrs (_name: value: {
          fg = value;
        }) themeRainbowLookup.${config.my.theme.theme};
      })

      (lib.mkIf config.my.theme.rainbowIndents {
        opts.list = true;

        plugins.indent-blankline = {
          enable = true;

          lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
            event = "BufReadPost";
          };

          settings = {
            indent = {
              char = "▎";
              tab_char = "▎";
            };

            scope = {
              enabled = true;
              show_start = true;
              show_exact_scope = false;
              show_end = true;
              highlight = highlightNames;
            };
          };

          luaConfig = {
            pre = ''
              local hooks = require("ibl.hooks")
              hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: value: ''
                    vim.api.nvim_set_hl(0, "${name}", { fg = "${value}" })
                  '') themeRainbowLookup.${config.my.theme.theme}
                )}
              end)
              hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
            '';
          };
        };
      })

      (lib.mkIf config.my.theme.rainbowBrackets {
        plugins.rainbow-delimiters = {
          enable = true;

          lazyLoad.settings = lib.mkIf lazyLoadingEnabled {
            event = "BufReadPost";
          };

          settings = {
            highlight = highlightNames;
          };
        };
      })
    ]
  );
}
