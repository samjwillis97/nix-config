{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.my.cloudflared = {
    enable = lib.mkEnableOption "cloudflared tunnels";

    connector = {
      enable = lib.mkEnableOption "cloudflared connector";

      tokenFile = lib.mkOption {
        type =
          with lib.types;
          oneOf [
            path
            str
          ];
        description = "File containing the remotely managed tunnel token";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !config.my.cloudflared.connector.enable || config.my.cloudflared.enable;
          message = "my.cloudflared.connector requires my.cloudflared.enable";
        }
      ];
    }

    (lib.mkIf config.my.cloudflared.connector.enable {
      systemd.services.cloudflared-tunnel = {
        description = "Cloudflare Tunnel connector";

        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "nginx.service"
        ];

        serviceConfig = {
          DynamicUser = true;
          LoadCredential = [
            "token:${config.my.cloudflared.connector.tokenFile}"
          ];

          ExecStart = ''
            ${pkgs.cloudflared}/bin/cloudflared \
              tunnel \
              --no-autoupdate \
              run \
              --token-file %d/token
          '';

          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    })
  ];
}
