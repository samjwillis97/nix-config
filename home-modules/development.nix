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
    my.f.enable = true;

    home.packages = with pkgs; [
      neovim
      jq
    ];
  };
}
