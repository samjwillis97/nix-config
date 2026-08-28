{ config, lib, ... }:
{
  options.my.jellyfin = {
    enable = lib.mkEnableOption "jellyfin media server";

    openFirewall = lib.mkEnableOption "open firewall for jellyfin, independent of ingress route";

    ingress.enable = lib.mkEnableOption "jellyfin ingress route";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.jellyfin.enable {
      services.jellyfin = {
        enable = true;
        openFirewall = config.my.jellyfin.openFirewall;
      };
    })

    (lib.mkIf (config.my.jellyfin.enable && config.my.actual.ingress.enable) {
      my.ingress.routes.jellyfin = {
        upstream = "http://127.0.0.1:8096";
        websockets = true;
      };
    })
  ];
}
