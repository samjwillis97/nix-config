let
  secrets = [
    "jellyfin/api-key"
    "jellyfin/admin-password"
    "xtream/base-url"
    "xtream/username"
    "xtream/password"
  ];
in
{
  sops.secrets = builtins.listToAttrs (
    map
      (secretName: {
        name = secretName;
        value = {
          sopsFile = ./secrets.yaml;
        };
      })
      secrets
  );
}
