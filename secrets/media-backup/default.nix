let
  secrets = [
    "b2/account-id"
    "b2/application-key"
    "restic/password"
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
