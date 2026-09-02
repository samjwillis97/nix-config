{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.my.f = {
    enable = lib.mkEnableOption "f CLI";
  };

  config = lib.mkIf config.my.f.enable {
    my.tmux.enable = true;

    home.packages = with pkgs; [
      f
    ];
  };
}
