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
| `groups/`         | System group definitions and their member lists.                    |

Directory entries can be either `<name>.nix` or `<name>/default.nix`. See each directory's README for its local conventions.

## Useful commands

### Getting closure size of build

```
nix path-info -Sh \
    .#nixosConfigurations.staging-vm.config.system.build.toplevel
```

### See packages that would be installed

```
nix eval --json .#nixosConfigurations.staging-vm.config.environment.systemPackages --apply 'packages: map (package: package.name) packages' | jq -r '.[]' | sort -u
```
