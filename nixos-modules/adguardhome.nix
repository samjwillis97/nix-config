{ config, lib, ... }:
let
  cfg = config.my.adguardhome;
in
{
  options.my.adguardhome = {
    enable = lib.mkEnableOption "AdGuard Home DNS ad blocker";

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Addresses the DNS server binds to. Do not use a wildcard address: when
        Podman's DNS is enabled, aardvark-dns binds port 53 on the container
        bridge addresses and the two services would collide.
      '';
      example = [
        "127.0.0.1"
        "192.168.1.10"
      ];
    };

    openFirewall = lib.mkEnableOption "opening DNS (TCP and UDP 53) on all interfaces, not only trusted ones";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = ''
        Port for the web UI. It is not opened in the firewall, so it is only
        reachable from trusted interfaces such as `tailscale0`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.adguardhome = {
      enable = true;
      port = cfg.webPort;

      # Settings are re-applied on every start, so the web UI is for
      # inspection (query log, statistics); change configuration here.
      mutableSettings = false;

      settings = {
        dns = {
          bind_hosts = cfg.listenAddresses;
          port = 53;

          upstream_dns = [
            "https://cloudflare-dns.com/dns-query"
            "https://dns.quad9.net/dns-query"
          ];
          bootstrap_dns = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          upstream_mode = "parallel";

          # Cache aggressively; stale answers are served while refreshing.
          cache_enabled = true;
          cache_size = 16777216;
          cache_optimistic = true;
        };

        filtering = {
          filtering_enabled = true;
          protection_enabled = true;
        };

        filters = [
          {
            enabled = true;
            id = 1;
            name = "AdGuard DNS filter";
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          }
        ];
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
