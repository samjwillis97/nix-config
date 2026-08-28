{ config, lib, ... }:
{
  options.my.dispatcharr = {
    enable = lib.mkEnableOption "dispatcharr, iptv & stream management";

    ingress.enable = lib.mkEnableOption "dispatcharr ingress route";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.dispatcharr.enable { })

    (lib.mkIf (config.my.dispatcharr.enable && config.my.actual.ingress.enable) {
      my.ingress.routes.dispatcharr = {
        upstream = "http://127.0.0.1:${toString config.services.dispatcharr.settings.port}";
        websockets = true;
      };
    })
  ];
}
