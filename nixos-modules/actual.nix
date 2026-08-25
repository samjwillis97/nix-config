{ config, lib, ... }:
{
  options.my.actual = {
    enable = lib.mkEnableOption "actual budgetting";

    ingress.enable = lib.mkEnableOption "actual ingress route";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.actual.enable {
      services.actual = {
        enable = true;

        settings = {
          hostname = "127.0.0.1";
          port = 3000;
        };
      };
    })

    (lib.mkIf (config.my.actual.enable && config.my.actual.ingress.enable) {
      my.ingress.routes.actual = {
        upstream = "http://127.0.0.1:${toString config.services.actual.settings.port}";
        websockets = true;
      };
    })
  ];
}
