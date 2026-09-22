# Users

A user directory can provide three separate platform/configuration fragments:

- `default.nix` — the NixOS account definition, returned as a module attribute set (normally from a function such as `{ pkgs, ... }: { ... }`).
- `darwin.nix` — the nix-darwin account definition, also returned as a module attribute set.
- `home.nix` — the user's Home Manager module, shared by whichever integrated hosts select that user.

Use a directory per identity: `users/<name>/default.nix`, with `darwin.nix` and/or `home.nix` beside it. The scanner also treats regular `.nix` files directly under `users/` as entries in every scan, including the account, Darwin-account, and home scans. Avoid that ambiguous form; the directory convention makes the entry points explicit.

## How discovery works

`flake-module.nix` builds three maps:

- `userModules` scans `users/` for the normal `default.nix` entry point. These names are the available NixOS accounts.
- `userHomeModules` scans for `home.nix`. These names are the Home Manager modules available to selected users.
- `darwinUserModules` scans for `darwin.nix`. These names are the Darwin account modules.

There is no user registry. Adding the appropriate file under a new directory makes its name available to the corresponding host option.

## Enable an account on a host

On NixOS, `my.users` is an enum of `userModules` names. Selecting a name imports `users/<name>/default.nix` into `users.users.<name>`. A selected NixOS user therefore needs `default.nix`:

```nix
# users/<name>/default.nix
{ pkgs, ... }:
{
  isNormalUser = true;
  shell = pkgs.zsh;
  extraGroups = [ "wheel" ];
  # Add `uid = ...` only when a stable numeric identity is required.
}
```

On nix-darwin, `my.users` is assembled from the discovered Darwin-account and home names, and the current Darwin users module imports `darwinUserModules.<name>` for every selected name. Provide `darwin.nix` for each selected Darwin account even if that account also has a `home.nix`:

```nix
# users/<name>/darwin.nix
{ pkgs, ... }:
{
  shell = pkgs.zsh;
  home = "/Users/<name>";
}
```

The host must select the account in `my.users`; merely creating a user directory does not create an account. On Darwin, set `system.primaryUser` to the selected login account as described in [`darwin-hosts/`](../darwin-hosts/README.md).

## Attach Home Manager configuration

`home.nix` is optional. When a selected host sets `my.home-manager.enable = true`, the account's `home.nix` is attached to `home-manager.users.<name>` if it exists. A selected account without `home.nix` still exists at the platform level but has no embedded Home Manager user. A `home.nix` alone does not enable an account.

Use Home Manager options and the shared `my.*` feature switches rather than importing [`home-modules/`](../home-modules/README.md) manually:

```nix
# users/<name>/home.nix
{ ... }:
{
  home = {
    username = "<name>";
    stateVersion = "<existing-home-state-version>";
  };

  my.cli.enable = true;
}
```

Replace the placeholders with the real account name and the state version already established for that home. Preserve `home.stateVersion` when moving the same logical home between hosts; it is Home Manager compatibility history and is independent of each host's `system.stateVersion`. A deliberate state-version migration should be planned, not bundled into an ordinary package/input update.

Integrated Home Manager modules receive `inputs`, `secretModules`, and `unstable` as extra arguments. A home module may import a narrowly scoped secret module with `secretModules.<name>` when needed, but secrets must not be printed or embedded in reusable account files. The host's `my.desktop.enable` and `my.work.enable` values are propagated into Home Manager and take precedence over conflicting user-level values.

## Groups, identities, and platform differences

All discovered [`groups/`](../groups/README.md) are created on every NixOS host; there is no per-host group selection. A NixOS account can use a group as its primary `group`, list supplementary `extraGroups`, or receive membership from a group's `members` list. Group definitions are NixOS-only; Darwin account files should use the nix-darwin account options available on that platform.

Keep explicit UIDs only when stable ownership or interoperability requires them. Changing a UID later does not relabel existing files, service data, ACLs, or backups; plan any ownership migration separately. The same applies to an explicit group GID, which is why [`groups/README.md`](../groups/README.md) treats numeric identity as a compatibility decision. Do not copy account names, UIDs, SSH keys, home paths, or deployment identities from an existing machine.

For host selection and state-version boundaries, see [`nixos-hosts/`](../nixos-hosts/README.md) and [`darwin-hosts/`](../darwin-hosts/README.md). For the standards applied to reusable modules, see the [development guide](../docs/development.md).
