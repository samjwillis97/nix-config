{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.my.unreal-agent = {
    enable = lib.mkEnableOption "unreal-agent";
  };

  config = lib.mkIf config.my.unreal-agent.enable {
    home.packages = [ pkgs.unreal-agent ];
  };
}
