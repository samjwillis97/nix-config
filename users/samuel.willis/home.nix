# pre-assigned user on work macbook
{
  config,
  secretModules,
  ...
}:
{
  imports = [
    secretModules.development
  ];

  home = {
    username = "samuel.willis";
    stateVersion = "23.11";
  };

  my = {
    firefox.enable = false;

    development = {
      enable = true;

      platform-clis = [ "aws" ];
    };

    _1password.enable = true;

    omp = {
      enable = true;
      settings = {
        provider = "github-copilot";
      };
    };

    git = {
      enable = true;

      email = "sam@williscloud.org";

      authentication.github = {
        enable = true;
        keyFile = config.sops.secrets."git-identity-file".path;
      };

      signedCommits.github = {
        enable = true;
        keyFile = config.sops.secrets."git-identity-file".path;
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0JQTnmK59i/vGOzMb4MR3KphYThSxEOorbribPp/Y1 sam@williscloud.org";
      };
    };
  };
}
