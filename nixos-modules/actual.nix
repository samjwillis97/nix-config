{ config, lib, ... }:
{
  options.my.actual = {
    enable = lib.mkEnableOption "actual budgetting";
  };

  config = lib.mkIf config.my.actual.enable {
    services.actual = {
      enable = true;
    };
  };
}
