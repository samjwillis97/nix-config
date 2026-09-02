{
  config,
  lib,
  pkgs,
  ...
}:
let
  page = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Hello, world!</title>
      </head>
      <body>
        <h1>Hello, world!</h1>
      </body>
    </html>
  '';
in
{
  options.my.hello = {
    enable = lib.mkEnableOption "hello world page";

    ingress.enable = lib.mkEnableOption "hello world ingress route";
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.hello.enable && config.my.hello.ingress.enable) {
      my.ingress.routes.hello = {
        root = page;
      };
    })
  ];
}
