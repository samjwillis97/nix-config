{
  sops.secrets = {
    "supernote/mysql-root-password" = {
      sopsFile = ./secrets.yaml;
    };

    "supernote/mysql-password" = {
      sopsFile = ./secrets.yaml;
    };

    "supernote/redis-password" = {
      sopsFile = ./secrets.yaml;
    };
  };
}
