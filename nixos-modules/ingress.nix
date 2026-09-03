{
  config,
  lib,
  ...
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
                default = "${name}-${config.networking.hostName}";
                description = "Subdomain relative to the Cloudflare zone";
              };

              upstream = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Local HTTP origin proxied by nginx";
                example = "http://127.0.0.1:3000";
              };

              root = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Directory containing static files served by nginx";
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
    assertions = [
      {
        assertion = lib.all (route: (route.upstream == null) != (route.root == null)) (
          lib.attrValues config.my.ingress.routes
        );
        message = "Each ingress route must define exactly one of upstream or root";
      }
    ];

    services.nginx = {
      enable = true;

      virtualHosts = lib.mapAttrs (
        _name: route:
        {
          inherit listen;
        }
        // lib.optionalAttrs (route.upstream != null) {
          locations."/" = {
            proxyPass = route.upstream;
            proxyWebsockets = route.websockets;
            recommendedProxySettings = true;
          };
        }
        // lib.optionalAttrs (route.root != null) {
          inherit (route) root;
        }
      ) config.my.ingress.routes;
    };
  };
}
