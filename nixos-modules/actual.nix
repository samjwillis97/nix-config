{ config, lib, ... }:
{
  options.my.actual = {
    enable = lib.mkEnableOption "actual budgetting";
  };

  config = lib.mkIf config.my.actual.enable {
    services.actual = {
      enable = true;

      settings = {
        hostname = "127.0.0.1";
        port = 3000;
      };
    };

    # TODO: create option for this behaviour
    my.ingress.routes.actual = {
      upstream = "http://127.0.0.1:${toString config.services.actual.settings.port}";
      websockets = true;
    };
  };
}
