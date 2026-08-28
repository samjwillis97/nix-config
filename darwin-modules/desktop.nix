{ lib, ... }:
{
  options.my.desktop = {
    enable = lib.mkEnableOption "desktop features";
  };
}
