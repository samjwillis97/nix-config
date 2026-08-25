{ config, secretModules, ... }:
{
  imports = [
    secretModules.development
  ];

  config = {
    my = {
      git = {
        enable = true;
        signedCommits = {
          enable = true;
          identityFile = config.sops.secrets."git-identity-file".path;
        };
      };
    };

    home.stateVersion = "23.11";
  };
}
