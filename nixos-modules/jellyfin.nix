{ config, lib, ... }:
{
  options.my.jellyfin = {
    enable = lib.mkEnableOption "jellyfin";

    ingress.enable = lib.mkEnableOption "jellyfin ingress route";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.jellyfin.enable {
      services.jellyfin = {
        enable = true;
      };
    })

    (lib.mkIf (config.my.jellyfin.enable && config.my.actual.ingress.enable) {
      my.ingress.routes.jellyfin = {
        upstream = "http://127.0.0.1:${toString config.services.jellyfin.settings.port}";
        websockets = true;
      };
    })
  ];
}
