# nix-darwin hosts

Each child directory with a `default.nix` defines one nix-darwin system. Its directory name becomes the key under `darwinConfigurations`; unlike the NixOS assembly, the flake does not use that key to set a Darwin `networking.hostName`.

## Discovery and composition

`flake-module.nix` scans `./darwin-hosts` with `readModules`:

- `darwin-hosts/<name>/default.nix` is the normal host entry point.
- A regular `.nix` directly under `darwin-hosts/` would also be discovered as a host.
- Extra files inside a host directory are not discovered as hosts; import them explicitly from `default.nix`.

Every discovered module in [`darwin-modules/`](../darwin-modules/README.md) is already imported, as are Home Manager, sops-nix, brew-nix, Stylix, base16, and the repository overlays. Do not import those modules individually. Darwin host modules receive normal module arguments plus `self`, `inputs`, `userHomeModules`, and `darwinUserModules`; the flake also provides `unstable`. Secret modules are passed to embedded Home Manager users, not directly as a Darwin host special argument.

## Add a host

Use the platform system, select the account, and set the primary user to the same identity:

```nix
# darwin-hosts/<host-name>/default.nix
{ ... }:
{
  nixpkgs.hostPlatform = "<supported-darwin-system>"; # replace with this Mac's target

  my = {
    users = [ "account-name" ];
    home-manager.enable = true;
    dix.enable = true;
  };

  system.primaryUser = "account-name";
  # Required: set system.stateVersion to the initial nix-darwin integer for a
  # new system; preserve the existing integer on an already-managed system.
}
```

Replace the placeholders and preserve the existing `system.stateVersion` rather than copying a channel or input version. Darwin's state version is independent from Home Manager's `home.stateVersion`.

For bootstrap and platform-specific installation details, use the [nix-darwin manual](https://nix-darwin.github.io/nix-darwin/manual/) and [upstream repository](https://github.com/nix-darwin/nix-darwin). The repository pins nix-darwin as a flake input; inspect the `inputs.nix-darwin.url` in `flake.nix` and keep new commands aligned with that pinned source rather than introducing an unpinned channel.

`my.users` is built from discovered Darwin account and home names. For every selected account, provide `users/<name>/darwin.nix`; the current Darwin users module imports that file for each selected name. Add `users/<name>/home.nix` when the account should receive Home Manager configuration, and set `my.home-manager.enable = true` to embed it. See [`users/README.md`](../users/README.md) for the file matrix. `system.primaryUser` should match the selected login account because shared Darwin modules use it for user-scoped system defaults.

The host's `my.desktop.enable` and `my.work.enable` values are propagated into embedded Home Manager evaluation. Configure them on the host when the machine should use those profiles; configure other user features in the user's `home.nix`. `my.dix.enable` adds the Darwin system closure to the generated Dix checks; the [development guide](../docs/development.md) explains the check workflow.

## Platform boundary

This directory is for nix-darwin system settings: `system.defaults`, fonts, launch/system services, Nix settings, and other macOS host behavior. Do not use NixOS-only options such as Linux boot or systemd settings, and do not put user dotfiles here. Put reusable system behavior in [`darwin-modules/`](../darwin-modules/README.md) and user behavior in [`home-modules/`](../home-modules/README.md).

Deployment output in this repository is generated for NixOS hosts with `my.deploy-rs.enable`; there is no corresponding Darwin deploy-rs host path in `flake-module.nix`. For closure checks and other host operations, use the [operations guide](../docs/operations.md) rather than copying identities or machine inventories into this guide.
