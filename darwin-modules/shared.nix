{ lib, ... }:
{
  options.my = {
    desktop.enable = lib.mkEnableOption "desktop features/applications";

    work.enable = lib.mkEnableOption "work features/applications";

    dix.enable = lib.mkEnableOption "Dix closure diffs";

    gaming.enable = lib.mkEnableOption "gaming features/applications";
  };
}
