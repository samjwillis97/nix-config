{ lib, ... }:
{
  options.my = {
    desktop.enable = lib.mkEnableOption "desktop features/applications";

    work.enable = lib.mkEnableOption "work features/applications";

    dix.enable = lib.mkEnableOption "Dix closure diffs";
  };
}
