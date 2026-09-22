# Groups

This directory defines reusable **NixOS** group records. Groups are not selected per host: every discovered group is assigned to `users.groups` on every NixOS system by [`nixos-modules/groups.nix`](../nixos-modules/groups.nix).

## Discovery and file shape

`flake-module.nix` scans `./groups` with `readModules`:

- `groups/<name>/default.nix` is the normal entry point and becomes `groupModules.<name>`.
- A regular `.nix` directly under `groups/` would also be discovered; prefer the directory convention so related files and documentation stay together.
- Other files in a group directory are ignored unless its `default.nix` imports them.

A group entry point must be an attribute set. The groups module imports it with no arguments and builds `users.groups` from every discovered name:

```nix
# groups/<name>/default.nix
{
  members = [ "account-name" ];
  # Add `gid = ...` only when a stable numeric GID is required.
}
```

Replace the example member and, if necessary, choose a stable GID for the deployment. Do not use a module function that expects `{ pkgs, ... }`; unlike user account files, group definitions are imported without arguments.

## Membership and identity

A group exists on every NixOS host even when it has no members. Membership can be declared from either side:

- Set `group = "group-name"` in a user's `users/<name>/default.nix` for the primary group.
- Set `extraGroups = [ "group-name" ]` in that account for supplementary membership.
- Set `members = [ "account-name" ]` here for group-owned membership that should be maintained with the group.

Use the membership form that expresses ownership of the relationship; do not list an account here unless that account is also declared/selected appropriately on the host. Groups are created by the NixOS module path and are not part of nix-darwin's `my.users` composition.

Treat an explicit `gid` like an explicit UID: changing it later does not migrate existing file ownership, ACLs, service data, or backups. Preserve a numeric GID when external files or services depend on it, and plan any ownership migration deliberately. See [`users/README.md`](../users/README.md) for account identity and host selection, and [`nixos-hosts/README.md`](../nixos-hosts/README.md) for composing a machine.
