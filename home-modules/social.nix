{ config
, pkgs
, lib
, ...
}:
let
  workEnabled = config.my.work.enable;
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
        home.packages = with pkgs; [
          discord
        ];
      }

      (lib.mkIf workEnabled {
        home.packages = with pkgs; [
          slack
          zoom-us
        ];
      })
    ]
  );
}
