{ config
, lib
, pkgs
, ...
}:
{
  options.my.development = {
    enable = lib.mkEnableOption "development environment";
  };

  config = lib.mkIf config.my.development.enable {
    home.packages = with pkgs; [
      neovim
    ];
  };
}
