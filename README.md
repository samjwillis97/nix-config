# nix-config

A flake-parts configuration for NixOS and Home Manager, with scaffolding for nix-darwin.

`flake-module.nix` discovers hosts, users, and reusable modules from the directories below. Reusable modules are imported into every relevant configuration: unconditional definitions apply everywhere, while optional behavior should expose disabled-by-default options and guard its configuration with `lib.mkIf`.

## Layout

| Path              | Purpose                                                             |
| ----------------- | ------------------------------------------------------------------- |
| `nixos-hosts/`    | Host-specific NixOS configuration and hardware imports.             |
| `nixos-modules/`  | Reusable modules imported into every NixOS configuration.           |
| `darwin-modules/` | Reusable modules intended for every nix-darwin configuration.       |
| `home-modules/`   | Reusable modules imported into every Home Manager configuration.    |
| `users/`          | System account definitions and per-user Home Manager configuration. |

Directory entries can be either `<name>.nix` or `<name>/default.nix`. See each directory's README for its local conventions.
