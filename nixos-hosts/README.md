# NixOS hosts

Each child directory with a `default.nix` defines one NixOS system. Its directory name becomes the key under `nixosConfigurations`, and `flake-module.nix` also sets `networking.hostName` to that key. There is no host registry to edit.

## Discovery and composition

The host scanner is the same `readModules` helper used for reusable modules:

- `nixos-hosts/<name>/default.nix` is the normal host entry point.
- A regular `.nix` placed directly under `nixos-hosts/` would also be discovered as a host, but the directory-per-host convention keeps hardware and related files together.
- Files such as `hardware-configuration.nix` inside a host directory are not discovered automatically. Import them from that host's `default.nix`.

Every discovered NixOS module is already imported before the host module, along with the repository overlays and the external NixOS integrations. Do not import files from [`nixos-modules/`](../nixos-modules/README.md) individually. Host modules receive normal module arguments and the NixOS special arguments `self`, `inputs`, `userHomeModules`, `userModules`, `groupModules`, and `secretModules`; use `secretModules.<name>` only for a module that actually exists under [`secrets/`](../secrets/README.md).

## Add a hardware-aware host

Create the directory and entry point, then import a reviewed hardware module:

```nix
# nixos-hosts/<host-name>/default.nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  nixpkgs.hostPlatform = "<supported-linux-system>"; # replace with this machine's target

  my = {
    users = [ "account-name" ];
    home-manager.enable = true;
    dix.enable = true;
  };

  system.stateVersion = "<existing-system-state-version>";
}
```

Replace the placeholders with values for the new machine. The selected account must have `users/<name>/default.nix`; see [`users/README.md`](../users/README.md). Set `nixpkgs.hostPlatform` in either this file or the imported hardware file, according to the existing host pattern. A generated `hardware-configuration.nix` commonly contains boot, filesystem, swap, firmware, and platform settings; review it before committing and do not copy another machine's disk identifiers. NixOS hosts are Linux systems, and the target must be one of the systems supported by the flake.

Preserve the host's established `system.stateVersion` wherever the existing host keeps it (some current hardware files set it in `hardware-configuration.nix`). Do not blindly add a second value or change it to match a newer channel. It records compatibility behavior for the system and changing it is a deliberate migration. Keep it separate from a user's Home Manager `home.stateVersion`.

## Selecting users and features

`my.users` is an enum of discovered NixOS account names and defaults to an empty list. Selecting a name creates that system account from its `default.nix`. If `my.home-manager.enable` is true, selected users that also have `home.nix` receive embedded Home Manager configurations; selected users without `home.nix` still receive their system account but no Home Manager user. All discovered Home Manager modules are shared automatically.

Most reusable behavior is enabled through options rather than imports. Typical host-level choices include:

```nix
my = {
  users = [ "account-name" ];
  home-manager.enable = true;

  # A non-empty route set enables nginx. Each route needs exactly one upstream or root.
  ingress.routes.example.upstream = "http://127.0.0.1:<service-port>";

  # Enable only with user-supplied deployment public keys.
  deploy-rs = {
    enable = true;
    authorizedKeys = [ "ssh-ed25519 AAAA... user-supplied-public-key" ];
  };

  # Add the host to the closure-diff checks.
  dix.enable = true;
};
```

Do not copy deployment keys, identities, routes, or secret paths from another host. `my.deploy-rs.githubActions.enable` requires `my.deploy-rs.enable` and the deploy module requires at least one authorized key. `my.cloudflared` connector settings require the parent feature and a token file. The generated deploy, ingress/Cloudflare, and closure-check outputs are wired from these options; use the [operations guide](../docs/operations.md) for workflows rather than duplicating them here.

Host settings that are shared by several systems belong in [`nixos-modules/`](../nixos-modules/README.md). Account and group details belong in [`users/`](../users/README.md) and [`groups/`](../groups/README.md). Keep only machine-specific hardware, platform, imports, and feature selections in this directory.
