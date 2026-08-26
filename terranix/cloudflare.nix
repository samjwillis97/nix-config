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
        {
          inherit routes;

          ingress = lib.mapAttrsToList
            (_routeName: route: {
              inherit (route) hostname;
              service = "http://127.0.0.1:8080";

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
  rootRoutes = lib.filterAttrs
    (_routeName: route: route.subdomain == route.tunnelHost)
    dnsRoutes;

  tunnelId = lib.tf.ref "cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id";
in
{
  moved = lib.mapAttrsToList
    (routeName: route: {
      from = ''cloudflare_dns_record.host["${route.tunnelHost}"]'';
      to = ''cloudflare_dns_record.route["${routeName}"]'';
    })
    rootRoutes;
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
