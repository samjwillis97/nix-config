{ lib, config, ... }:
{
  options.my.networking.tailscale = {
    enable = lib.mkEnableOption "Enable tailscale VPN";

    exitNode = {
      enable = lib.mkEnableOption "Enable exit node functionality";
    };

    authKeyFile = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          path
          str
        ];
      description = "File containing authKey";
      example = "/var/lib/myKey";
    };
  };

  config = lib.mkIf config.my.networking.tailscale.enable (
    lib.mkMerge [
      {
        services.tailscale.enable = true;

        networking.firewall = {
          enable = true;
          trustedInterfaces = [ "tailscale0" ];
          allowedUDPPorts = [ config.services.tailscale.port ];
          checkReversePath = "loose";
        };
      }
      (lib.mkIf config.my.networking.tailscale.exitNode.enable {
        boot.kernel.sysctl = {
          "net.ipv6.conf.all.forwarding" = 1;
        };
      })
    ]
  );
}
