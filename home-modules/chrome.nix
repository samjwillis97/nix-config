{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my.chrome = {
    enable = lib.mkEnableOption "Enable the Google Chrome browser";
  };

  config = lib.mkIf config.my.chrome.enable {
    home.packages = [
      pkgs.google-chrome
    ];
  };
}
