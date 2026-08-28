{ config
, pkgs
, lib
, ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  options.my.ghostty = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.desktop.enable;
      description = "Enable Ghostty terminal emulator";
    };
  };

  config = lib.mkIf config.my.ghostty.enable (
    lib.mkMerge [
      {
        programs.ghostty = {
          enable = true;
          enableZshIntegration = false;

          settings = {
            title = "Ghostty";
            macos-titlebar-style = "hidden";
            cursor-style = "block";
            font-feature = "-calt";
            font-thicken = true;
            shell-integration-features = "no-cursor, title";
          };
        };
      }

      (lib.mkIf (!isDarwin) {
        programs.ghostty = {
          systemd.enable = true;
        };
      })

      (lib.mkIf isDarwin {
        programs.ghostty = {
          systemd.enable = false;
          package = pkgs.ghostty-bin;
          settings = {
            window-colorspace = "display-p3";
          };
        };
      })
    ]
  );
}
