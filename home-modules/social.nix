{ config
, pkgs
, lib
, ...
}:
let
  workEnabled = config.my.work.enable;
  workPackages =
    if workEnabled then
      with pkgs;
      [
        slack
        zoom-us
      ]
    else
      [ ];
in
{
  options.my.social = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.desktop.enable;
      description = "Enable social features/applications";
    };
  };

  home.packages =
    with pkgs;
    [
      discord
    ]
    ++ workPackages;
}
