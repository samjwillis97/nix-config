{ config, lib, ... }:
{
  options.my.completions = {
    enable = lib.mkEnableOption "completion support";
  };

  config = lib.mkIf config.my.completions.enable (
    lib.mkMerge [
      {
        plugins.blink-cmp = {
          enable = true;

          setupLspCapabilities = config.my.languages.lsp;

          settings = {
            appearance = {
              nerd_font_variant = "mono";
            };

            signature = {
              window = {
                border = if config.my.theme.windowBorders then "single" else null;
              };
            };

            completion = {
              ghost_text = {
                enabled = true;
                show_with_menu = false;
              };

              menu = {
                enabled = true;
                border = if config.my.theme.windowBorders then "single" else null;
                auto_show = false; # only show menu on <C-Space>
              };

              documentation = {
                window = {
                  border = if config.my.theme.windowBorders then "single" else null;
                };
              };

              accept = {
                auto_brackets = {
                  enabled = true;

                  semantic_token_resolution = {
                    enabled = true;
                  };
                };
              };

              documentation = {
                auto_show = true;
              };

              list = {
                selection = {
                  preselect = true;
                  auto_insert = true;
                };
              };
            };

            signature = {
              enabled = true;
            };

            sources = {
              default = [
                "lsp"
                "path"
                "buffer"
              ];

              cmdline = [ ];

              providers = {
                buffer = {
                  score_offset = -7;
                };

                lsp = {
                  fallbacks = [ ];
                };
              };
            };

            keymap = {
              preset = "default";

              # if the completion menu is up, enter should select and accept
              # otherwise enter should be a newline like default
              "<Enter>" =
                let
                  function = lib.nixvim.utils.mkRaw ''
                    function(cmp)
                      if cmp.is_menu_visible() then 
                        return cmp.accept()
                      end
                    end
                  '';
                in
                [
                  function
                  "fallback"
                ];

              "<C-d>" = [
                "scroll_documentation_up"
                "fallback"
              ];
              "<C-f>" = [
                "scroll_documentation_down"
                "fallback"
              ];

              # This handles "Tab" accepting the ghost text
              "<Tab>" = [
                "select_and_accept"
                "fallback"
              ];
            };
          };
        };
      }

      (lib.mkIf config.my.icons.enable {
        plugins = {
          colorful-menu = {
            enable = true;
          };

          blink-cmp.settings.completion.menu.draw = {
            # This is a really annoying datastructure to define in Nix
            columns = lib.nixvim.utils.mkRaw ''
              { { "kind_icon" }, { "label", gap = 1 } }
            '';
            components = {
              label = {
                text = lib.nixvim.utils.mkRaw ''
                  require("colorful-menu").blink_components_text
                '';
                highlight = lib.nixvim.utils.mkRaw ''
                  require("colorful-menu").blink_components_highlight
                '';
              };
            };
          };
        };
      })
    ]
  );
}
