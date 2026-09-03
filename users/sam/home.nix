{
  config,
  secretModules,
  ...
}:
{
  imports = [
    secretModules.development
  ];

  config = {
    home = {
      username = "sam";
      stateVersion = "23.11";
    };

    my = {
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

      _1password.enable = true;

      development.enable = true;

      omp = {
        enable = true;
        settings = {
          provider = "openai-codex";
        };
      };
    };
  };
}
