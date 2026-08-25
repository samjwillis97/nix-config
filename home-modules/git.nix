{ config
, pkgs
, lib
, ...
}:
let
  email = "sam@williscloud.org";
  githubPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0JQTnmK59i/vGOzMb4MR3KphYThSxEOorbribPp/Y1 sam@williscloud.org";

  allowedSignersFile = pkgs.writeText "git-allowed-signers" ''
    ${email} namespaces="git" ${githubPublicKey}
  '';
in
{
  options.my.git = {
    enable = lib.mkEnableOption "git configuration";

    signedCommits = {
      enable = lib.mkEnableOption "enable git commit signing";

      identityFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the GPG key used for signing git commits.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.git.enable {
      programs = {
        difftastic.enable = true;

        git = {
          enable = true;
          lfs.enable = true;

          ignores = [
            "*~"
            "*.swp"
            ".idea/*"
            ".vscode/*"
            ".history/"
            "node_modules/"
            ".DS_Store"
            "venv/"
            ".direnv/"
            ".envrc"
            ".opencode/"
            "plans/"
            ".lavish/"
          ];

          settings = {
            user = {
              inherit email;
              name = "samjwillis97";
            };

            alias = {
              lg1 = "lg1-specific --all";
              lg2 = "lg2-specific --all";
              lg3 = "lg3-specific --all";
              lg1-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)'";
              lg2-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)'";
              lg3-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset) %C(bold cyan)(committed: %cD)%C(reset) %C(auto)%d%C(reset)%n''          %C(white)%s%C(reset)%n''          %C(dim white)- %an <%ae> %C(reset) %C(dim white)(committer: %cn <%ce>)%C(reset)'";
              s = "status";
              tug = "!git fetch && git pull";
              undo = "reset --soft HEAD^";
            };

            merge = {
              tool = "fugitive";
            };

            push = {
              autoSetupRemote = true;
            };

            safe = {
              directory = "*";
            };
          };
        };
      };
    })
    (lib.mkIf (config.my.git.enable && config.my.git.signedCommits.enable) {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        settings = {
          "*" = {
            ForwardAgent = false;
            AddKeysToAgent = "no";
            Compression = false;
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";
          };

          "github.com" = {
            identityFile = builtins.replaceStrings [ "$HOME" ] [ "~" ] config.my.git.signedCommits.identityFile;
            identitiesOnly = true;
            compression = true;
            forwardAgent = true;
          };
        };
      };

      programs.git = {
        signing = {
          key = githubPublicKey;
          format = "ssh";
          signByDefault = true;
        };

        settings = {
          gpg.format = "ssh";
          gpg.ssh.allowedSignersFile = "${allowedSignersFile}";
        };
      };
    })
  ];
}
