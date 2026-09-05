{ config, lib, ... }:
let
  cfg = config.my.completions;
  copilotSuggestionsEnabled = cfg.copilot.suggestion.enabled;
  copilotNextEditsEnabled = cfg.copilot.nextEdits.enabled;
  copilotEnabled = copilotSuggestionsEnabled || copilotNextEditsEnabled;

  sidekickTab = lib.nixvim.utils.mkRaw ''
    function()
      return require("sidekick").nes_jump_or_apply()
    end
  '';

  nativeTab = lib.nixvim.utils.mkRaw ''
    function()
      ${lib.optionalString copilotNextEditsEnabled ''
        if require("sidekick").nes_jump_or_apply() then
          return ""
        end
      ''}
      ${lib.optionalString copilotSuggestionsEnabled ''
        if vim.lsp.inline_completion.get() then
          return ""
        end
      ''}
      return "<Tab>"
    end
  '';
in
{
  options.my.completions = {
    engine = lib.mkOption {
      type = lib.types.enum [
        "blink-cmp"
        "native"
      ];
      default = "native";
      description = "The completion engine to use.";
    };

    copilot = {
      suggestion = {
        enabled = lib.mkEnableOption "Copilot suggestions";
      };

      nextEdits = {
        enabled = lib.mkEnableOption "Copilot next edit suggestions";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf copilotEnabled {
      plugins = {
        lsp = {
          enable = true;
          servers.copilot.enable = true;
        };

        # blink-copilot defaults to copilot-lua, but both completion modes and
        # Sidekick can share Neovim's native Copilot LSP client.
        copilot-lua.enable = false;
      };
    })

    (lib.mkIf copilotNextEditsEnabled {
      plugins.sidekick.enable = true;
    })

    (lib.mkIf (cfg.engine == "native" && copilotSuggestionsEnabled) {
      plugins.lsp.onAttach = ''
        if client:supports_method(vim.lsp.protocol.Methods.textDocument_inlineCompletion, bufnr) then
          vim.lsp.inline_completion.enable(true, { bufnr = bufnr })
        end
      '';
    })

    (lib.mkIf (cfg.engine == "native" && copilotEnabled) {
      keymaps = [
        {
          key = "<Tab>";
          mode = "i";
          action = nativeTab;
          options = {
            expr = true;
            desc = "Accept Copilot suggestion or next edit";
          };
        }
      ];
    })

    (lib.mkIf (config.my.completions.engine == "blink-cmp") {
      plugins = {
        colorful-menu = {
          enable = true;
        };

        blink-copilot.enable = copilotSuggestionsEnabled;

        blink-cmp = {
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
                draw = {
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
              ]
              ++ lib.optional copilotSuggestionsEnabled "copilot";

              providers = lib.optionalAttrs copilotSuggestionsEnabled {
                copilot = {
                  async = true;
                  module = "blink-copilot";
                  name = "copilot";
                  score_offset = 100;
                  opts = {
                    max_completions = 3;
                    max_attempts = 4;
                    kind_name = "Copilot";
                    debounce = 750;
                    auto_refresh = {
                      backward = true;
                      forward = true;
                    };
                  };
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

              # Accept visible completion text before snippets or next edits.
              "<Tab>" = [
                "select_and_accept"
                "snippet_forward"
              ]
              ++ lib.optional copilotNextEditsEnabled sidekickTab
              ++ [ "fallback" ];
            };
          };
        };
      };
    })
  ];
}
