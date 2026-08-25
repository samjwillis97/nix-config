{
  sops.secrets = {
    "git-identity-file" = {
      sopsFile = ./secrets.yaml;
    };
  };
}
