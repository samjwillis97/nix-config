let
  secrets = [
    "jellyfin/api-key"
    "jellyfin/admin-password"
    "jellyfin/users/sam/password"
    "xtream/base-url"
    "xtream/username"
    "xtream/password"
    "arr/admin-password"
    "radarr/api-key"
    "sonarr/api-key"
    "prowlarr/api-key"
    "nzbgeek/api-key"
    "seerr/api-key"
    "torbox/api-key"
    "torbox/news-username"
    "torbox/news-password"
    "decypharr/api-token"
  ];
in
{
  sops.secrets = builtins.listToAttrs (
    map (secretName: {
      name = secretName;
      value = {
        sopsFile = ./secrets.yaml;
      };
    }) secrets
  );
}
