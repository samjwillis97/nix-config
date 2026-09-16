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

`nixosConfigurations.<name>` is the complete `nixosSystem` value. It contains functions such as `extendModules`, so the complete value cannot be encoded as JSON. Select a serializable leaf instead:

```
nix eval --json .#nixosConfigurations.teeny.config.system.build.toplevel.drvPath
```

To inspect a scalar through the complete configuration value, use `--apply`:

```
nix eval --json .#nixosConfigurations.teeny --apply 'system: system.config.system.stateVersion'
```

### Getting closure size of build

```
nix path-info -Sh \
    .#nixosConfigurations.staging-vm.config.system.build.toplevel
```

### See packages that would be installed

```
nix eval --json .#nixosConfigurations.staging-vm.config.environment.systemPackages --apply 'packages: map (package: package.name) packages' | jq -r '.[]' | sort -u
```

### Supernote database initialization

The Supernote module expects the schema file downloaded from Supernote at
`/var/lib/supernote/supernotedb.sql` before `supernote-mariadb.service` can
start:

```sh
curl --fail --location \
    --output /tmp/supernotedb.sql \
    https://supernote-private-cloud.supernote.com/cloud/supernotedb.sql
sudo install -o root -g root -m 0640 \
    /tmp/supernotedb.sql \
    /var/lib/supernote/supernotedb.sql
rm /tmp/supernotedb.sql
sudo systemctl start supernote-mariadb.service
sudo systemctl restart supernote-service.service
```

The database container only executes the mounted SQL file while initializing
an empty data directory. If MariaDB has already initialized its data
directory, import an updated schema manually inside the container instead of
recreating the data directory.
