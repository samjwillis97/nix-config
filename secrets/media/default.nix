let
  secrets = [
    "jellyfin/api-key"
    "jellyfin/admin-password"
    "jellyfin/users/sam/password"
    "xtream/base-url"
    "xtream/username"
    "xtream/password"
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
