{
  config,
  lib,
  ...
}:
{
  options.my.secrets.development.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the personal development secrets.";
  };

  config = lib.mkIf config.my.secrets.development.enable {
    sops.secrets = {
      "git-identity-file" = {
        sopsFile = ./secrets.yaml;
      };
    };
  };
}
