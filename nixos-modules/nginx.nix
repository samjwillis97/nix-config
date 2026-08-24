{ config
, lib
, pkgs
, ...
}:
let
  landingPage = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>nginx is running</title>
      </head>
      <body>
        <h1>nginx is running</h1>
        <p>This page is served by nginx on NixOS.</p>
      </body>
    </html>
  '';
in
{
  options.my.reverse-proxy = {
    enable = lib.mkEnableOption "nginx reverse proxy";
  };

  config = lib.mkIf config.my.reverse-proxy.enable {
    services.nginx = {
      enable = true;

      virtualHosts.localhost = {
        default = true;
        listen = [
          {
            addr = "127.0.0.1";
            port = 8080;
          }
          {
            addr = "[::1]";
            port = 8080;
          }
        ];
        root = landingPage;

        locations."/".tryFiles = "$uri $uri/ =404";
      };
    };
  };
}
