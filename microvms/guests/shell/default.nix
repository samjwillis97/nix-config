# "shell" MicroVM guest — a minimal Linux guest that reuses the repository's
# Home Manager configuration to provide zsh shell, aliases and CLI tools for
# sam-microvm user
{
  my = {
    users = [ "sam-microvm" ];
    home-manager.enable = true;
  };
}
