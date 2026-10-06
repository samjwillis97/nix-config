{ lib, ... }:
{
  options.my = {
    desktop.enable = lib.mkEnableOption "desktop features/applications";

    desktop.monitors = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            mode = lib.mkOption {
              type = lib.types.str;
              description = "Niri mode string for the monitor.";
            };

            width = lib.mkOption {
              type = lib.types.int;
              description = "Monitor width in pixels.";
            };

            height = lib.mkOption {
              type = lib.types.int;
              description = "Monitor height in pixels.";
            };

            refreshRate = lib.mkOption {
              type = lib.types.int;
              description = "Greeter refresh rate in hertz.";
            };

            scale = lib.mkOption {
              type = lib.types.number;
              description = "Niri output scale.";
            };

            x = lib.mkOption {
              type = lib.types.int;
              description = "Monitor X position in the global layout.";
            };

            y = lib.mkOption {
              type = lib.types.int;
              description = "Monitor Y position in the global layout.";
            };
          };
        }
      );
      default = { };
      description = "Monitor geometry shared by the desktop integrations.";
    };

    work.enable = lib.mkEnableOption "work features/applications";

    dix.enable = lib.mkEnableOption "Dix closure diffs";

    gaming.enable = lib.mkEnableOption "gaming features/applications";
  };
}
