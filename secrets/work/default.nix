{
  config,
  lib,
  ...
}:
{
  options.my.secrets.work.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to install the work secrets.";
  };

  config = lib.mkIf config.my.secrets.work.enable {
    sops.secrets."git-email" = {
      sopsFile = ./secrets.yaml;
    };

    sops.templates."git-email" = {
      content = ''
        [user]
        email = ${config.sops.placeholder."git-email"}
      '';
    };
  };
}
