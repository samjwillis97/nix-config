{ config
, lib
, ...
}:
let
  listen = [
    {
      addr = "127.0.0.1";
      port = config.my.ingress.listenPort;
    }
    {
      addr = "[::1]";
      port = config.my.ingress.listenPort;
    }
  ];
in
{
  options.my.ingress = {
    listenPort = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "Port on which nginx listens for incoming requests";
    };

    routes = lib.mkOption {
      default = { };

      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              subdomain = lib.mkOption {
                type = lib.types.str;
                default = "${name}.${config.networking.hostName}";
                description = "Subdomain relative to the Cloudflare zone";
              };

              upstream = lib.mkOption {
                type = lib.types.str;
                description = "Local HTTP origin proxied by nginx";
                example = "http://127.0.0.1:3000";
              };

              websockets = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether to proxy WebSocket upgrades";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf (config.my.ingress.routes != { }) {
    services.nginx = {
      enable = true;

      virtualHosts = lib.mapAttrs
        (_name: route: {
          inherit listen;

          locations."/" = {
            proxyPass = route.upstream;
            proxyWebsockets = route.websockets;
            recommendedProxySettings = true;
          };
        })
        config.my.ingress.routes;
    };
  };
}
