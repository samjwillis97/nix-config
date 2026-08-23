# Users

Each subdirectory describes one user:

- `default.nix` returns the account settings assigned to `users.users.<name>`. Account definitions are loaded as functions and should use the form `{ pkgs, ... }: { ... }`.
- `home.nix` is optional and contains that user's Home Manager configuration.

NixOS hosts select accounts with `my.users`. A selected user with a `home.nix` is also added to `home-manager.users`.

All reusable Home Manager modules are already imported. A user's `home.nix` should configure their options rather than import modules from `home-modules/` itself.

Keep `home.stateVersion` in `home.nix` when the same logical home configuration is shared across hosts. Make it host-specific only when those home installations intentionally have different compatibility histories.
