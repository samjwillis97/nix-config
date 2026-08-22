# NixOS modules

Every module in this directory is discovered by `flake-module.nix` and imported into every NixOS configuration.

Use unconditional definitions for system-wide baselines. Optional behavior should declare disabled-by-default options and guard its configuration with `lib.mkIf`; hosts enable or configure those options from `nixos-hosts/<name>/default.nix`.

The `users` module creates the accounts selected by `my.users` and attaches their Home Manager configurations. `zsh.nix` enables NixOS-side zsh support. Home Manager integration is assembled in `flake-module.nix`; user-level programs and dotfiles belong in `home-modules/` and `users/<name>/home.nix`.