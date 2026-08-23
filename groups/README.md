# Groups

Each subdirectory describes one system group:

- `default.nix` returns the group settings assigned to `users.groups.<name>`. Group definitions are loaded as functions and should use the form `{ pkgs, ... }: { ... }`.

All declared groups are created on every NixOS host; groups are inert without members, so there is no per-host selection.

Membership can be expressed two ways:

- Primary group: set `group = "<name>"` in the user's `default.nix` (e.g. `users/media/default.nix`).
- Secondary membership: list usernames in `members` here, e.g. `members = [ "sam" ];`. This merges cleanly with each user's own `extraGroups`, so either side may express membership.
