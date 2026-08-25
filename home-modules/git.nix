{
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
          name = "samjwillis97";
          email = "sam@williscloud.org";
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
}
