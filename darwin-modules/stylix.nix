{ pkgs
, config
, inputs
, lib
, ...
}:
let
  isDesktopEnabled = config.my.desktop.enable;
in
{
  options.my.styling = {
    enable = lib.mkEnableOption "Enable styling configuration for the system.";
  };

  config = lib.mkIf config.my.styling.enable (
    lib.mkMerge [
      {
        stylix = {
          enable = true;

          autoEnable = true;

          base16Scheme = "${inputs.tt-schemes}/base16/catppuccin-mocha.yaml";
          polarity = "dark";
        };
      }
      (lib.mkIf isDesktopEnabled {
        stylix = {
          fonts = {
            monospace = {
              package = pkgs.nerd-fonts.fira-code;
              name = "FiraCode Nerd Font Mono";
            };

            serif = {
              package = pkgs.dejavu_fonts;
              name = "DejaVu Serif";
            };

            sansSerif = {
              package = pkgs.dejavu_fonts;
              name = "DejaVu Sans";
            };

            emoji = {
              package = pkgs.noto-fonts-color-emoji;
              name = "Noto Color Emoji";
            };

            sizes = {
              desktop = 11;
              terminal = 11;
              applications = 10;
              popups = 10;
            };
          };

          opacity = {
            terminal = 1.0;
            desktop = 1.0;
            popups = 1.0;
          };
        };
      })
    ]
  );
}
