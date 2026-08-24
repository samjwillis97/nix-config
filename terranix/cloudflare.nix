{ cloudflareHosts
, cloudflareSettings
, lib
, ...
}:
let
  hosts = lib.mapAttrs
    (
      _hostName: host:
        let
          hostname = "${host.subdomain}.${cloudflareSettings.zoneName}";

          routes = lib.mapAttrs
            (
              _routeName: route:
                route
                // {
                  hostname = "${route.subdomain}.${cloudflareSettings.zoneName}";
                }
            )
            host.routes;
        in
        host
        // {
          inherit hostname routes;

          ingress = [
            {
              inherit hostname;
              service = host.origin;

              origin_request = {
                http_host_header = "localhost";
              };
            }
          ]
          ++ lib.mapAttrsToList
            (_routeName: route: {
              inherit (route) hostname;
              service = host.origin;

              origin_request = {
                http_host_header = route.internalHost;
              };
            })
            routes
          ++ [
            {
              service = "http_status:404";
            }
          ];
        }
    )
    cloudflareHosts;

  dnsRoutes = lib.concatMapAttrs
    (
      hostName: host:
        lib.mapAttrs'
          (
            routeName: route:
              lib.nameValuePair "${hostName}/${routeName}" (
                route
                // {
                  tunnelHost = hostName;
                }
              )
          )
          host.routes
    )
    hosts;

  tunnelId = lib.tf.ref "cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id";
  hostname = lib.tf.ref "each.value.hostname";
in
{
  terraform.required_providers.cloudflare = {
    source = "cloudflare/cloudflare";
    version = "~> 5.23";
  };

  resource = {
    cloudflare_zero_trust_tunnel_cloudflared.host = {
      for_each = hosts;

      account_id = cloudflareSettings.accountId;
      name = lib.tf.ref "each.key";
      config_src = "cloudflare";
    };

    cloudflare_zero_trust_tunnel_cloudflared_config.host = {
      for_each = hosts;

      account_id = cloudflareSettings.accountId;
      tunnel_id = lib.tf.ref "cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id";
      source = "cloudflare";

      config.ingress = lib.tf.ref "each.value.ingress";
    };

    cloudflare_dns_record.host = {
      for_each = hosts;

      zone_id = cloudflareSettings.zoneId;
      name = hostname;
      type = "CNAME";

      content = lib.tf.ref ''
        format("%s.cfargotunnel.com",
         cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id)'';

      proxied = true;
      ttl = 1;
    };

    cloudflare_dns_record.route = {
      for_each = dnsRoutes;

      zone_id = cloudflareSettings.zoneId;
      name = lib.tf.ref "each.value.hostname";
      type = "CNAME";

      content = lib.tf.ref ''
        format(
          "%s.cfargotunnel.com",
          cloudflare_zero_trust_tunnel_cloudflared.host[each.value.tunnelHost].id
        )'';

      proxied = true;
      ttl = 1;
    };
  };

  data.cloudflare_zero_trust_tunnel_cloudflared_token.host = {
    for_each = hosts;

    account_id = cloudflareSettings.accountId;
    tunnel_id = tunnelId;
  };

  output.cloudflare_tunnel_tokens = {
    sensitive = true;
    value = lib.tf.ref "{ for name, tunnel in data.cloudflare_zero_trust_tunnel_cloudflared_token.host :
 name => tunnel.token }";
  };

}
