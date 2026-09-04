{ config, lib, ... }:
let
  lazyLoadingEnabled = config.my.lazyLoading.enable;
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
  };

  config = lib.mkIf config.my.theme.enable (
    lib.mkMerge [
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
                # gitsigns = true;
                treesitter = config.plugins.treesitter.enable;
                # diffview = true;
                # fidget = true;
                # indent_blankline = {
                #   enabled = false;
                # };
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
    ]
  );
}
