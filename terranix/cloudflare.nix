{ cloudflareHosts
, cloudflareSettings
, lib
, ...
}:
let
  hosts = lib.mapAttrs
    (
      _name: host:
        host
        // {
          hostname = "${host.subdomain}.${cloudflareSettings.zoneName}";
        }
    )
    cloudflareHosts;

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
      tunnel_id = tunnelId;
      source = "cloudflare";

      config.ingress = [
        {
          inherit hostname;
          service = lib.tf.ref "each.value.origin";
        }
        {
          service = "http_status:404";
        }
      ];
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
