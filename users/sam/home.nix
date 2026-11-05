{
  config,
  lib,
  secretModules,
  ...
}:
let
  work = config.my.work.enable;

  # The work key is generated on the work laptop and never leaves it, so the
  # personal machines cannot decrypt it and no SOPS recipient is needed.
  githubKeyFile =
    if work then
      "${config.home.homeDirectory}/.ssh/id_ed25519_orica"
    else
      config.sops.secrets."git-identity-file".path;
in
{
  imports = [
    secretModules.development
    secretModules.work
  ];

  config = {
    home = {
      username = "sam";
      stateVersion = "23.11";
    };

    my = {
      secrets.development.enable = !work;
      secrets.work.enable = work;

      git = {
        enable = true;

        username = if work then "sam-willis-orica" else "samjwillis97";
        email = if work then null else "sam@williscloud.org";

        authentication.github = {
          enable = true;
          keyFile = githubKeyFile;
        };

        signedCommits.github = {
          enable = true;
          keyFile = githubKeyFile;
          publicKey =
            if work then
              null
            else
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0JQTnmK59i/vGOzMb4MR3KphYThSxEOorbribPp/Y1 sam@williscloud.org";
        };
      };

      _1password.enable = true;

      development.enable = true;

      agents.provider = if work then "github-copilot" else "openai-codex";

      omp = {
        enable = true;
      };

      pi = {
        enable = true;
      };
    };

    programs.git.settings = lib.optionalAttrs work {
      include.path = config.sops.templates."git-email".path;
    };
  };
}
