{
  config,
  pkgs,
  lib,
  ...
}:
let
  workEnabled = config.my.work.enable;
  filterPackages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform);
in
{
  options.my.social = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.desktop.enable;
      description = "Enable social features/applications";
    };
  };

  config = lib.mkIf config.my.social.enable (
    lib.mkMerge [
      {
        home.packages = filterPackages (
          with pkgs;
          [
            discord
          ]
        );
      }

      (lib.mkIf workEnabled {
        home.packages = filterPackages (
          with pkgs;
          [
            slack
            zoom-us
          ]
        );
      })
    ]
  );
}
