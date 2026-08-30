{ config
, lib
, pkgs
, ...
}:
{
  options.my.deploy-rs = {
    enable = lib.mkEnableOption "deploy-rs remote deployment access.";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of authorized SSH public keys for the deploy user.";
    };

    githubActions.enable = lib.mkEnableOption "deployment of this host through GitHub Actions.";
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !config.my.deploy-rs.githubActions.enable || config.my.deploy-rs.enable;
          message = "my.deploy-rs.githubActions requires my.deploy-rs.enable";
        }
      ];
    }

    (lib.mkIf config.my.deploy-rs.enable {
      assertions = [
        {
          assertion = config.my.deploy-rs.authorizedKeys != [ ];
          message = "my.deploy-rs.authorizedKeys must contain at least one key when enabled.";
        }
      ];

      users.groups.deploy = { };

      users.users.deploy = {
        isSystemUser = true;
        group = "deploy";

        shell = pkgs.bashInteractive;

        home = "/var/lib/deploy";
        createHome = true;

        hashedPassword = "!";

        openssh.authorizedKeys.keys = config.my.deploy-rs.authorizedKeys;
      };

      # The Nix daemon must accept unsigned store paths copied by deploy-rs.
      # This is root-equivalent trust, matching the sudo capability below.
      nix.settings.trusted-users = [ "deploy" ];

      security.sudo.extraRules = [
        {
          users = [ "deploy" ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    })
  ];
}
