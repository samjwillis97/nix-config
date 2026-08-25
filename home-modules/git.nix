{ config
, pkgs
, lib
, ...
}:
let
  allowedSignersFile = pkgs.writeText "git-allowed-signers" ''
    ${config.my.git.email} namespaces="git" ${config.my.git.signedCommits.github.publicKey}
  '';
in
{
  options.my.git = {
    enable = lib.mkEnableOption "git configuration";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address used for git configuration.";
    };

    authentication = {
      github = {
        enable = lib.mkEnableOption "enable GitHub authentication for git";

        keyFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the SSH key used for GitHub authentication.";
        };
      };
    };

    signedCommits = {
      github = {
        enable = lib.mkEnableOption "enable git commit signing for github";

        keyFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the SSH private key used for signing git commits.";
        };

        publicKey = lib.mkOption {
          type = lib.types.str;
          description = "SSH public key used for signing git commits.";
        };
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
              email = config.my.git.email;
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

    (lib.mkIf (config.my.git.enable && config.my.git.authentication.github.enable) {
      my.ssh.enable = true;

      programs.ssh.settings."github.com" = {
        identityFile =
          builtins.replaceStrings [ "$HOME" ] [ "~" ]
            config.my.git.authentication.github.keyFile;
        identitiesOnly = true;
        compression = true;
      };
    })

    (lib.mkIf (config.my.git.enable && config.my.git.signedCommits.github.enable) {
      programs.git = {
        signing = {
          key = toString config.my.git.signedCommits.github.keyFile;
          format = "ssh";
          signByDefault = true;
        };

        settings = {
          gpg.format = "ssh";
          gpg.ssh.allowedSignersFile = toString allowedSignersFile;
        };
      };
    })
  ];
}
