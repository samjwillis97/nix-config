# NixOS modules

This directory contains reusable **NixOS** modules. A module here is part of every NixOS system built by this flake; it is not a per-host import.

## Discovery and composition

`flake-module.nix` scans `./nixos-modules` with `readModules`:

- A regular `name.nix` directly in this directory is discovered as `nixosModules.name`.
- A child directory is discovered as `nixosModules.name` when it contains a regular `default.nix`.
- Other files inside a child directory are not discovered as separate modules. Import them from that directory's `default.nix` when needed.

There is no registry to update. The discovered values are collected as `allNixosModules` and passed to every `nixosSystem`, before the host module. This is why a new module must be safe on every NixOS host. Do not import an existing module again from `nixos-hosts/<name>/default.nix`.

The same assembly also adds the repository's overlays and the imported NixOS modules for Home Manager, sops-nix, nixflix, Stylix, and base16. Use their options directly; do not duplicate those imports in a host.

NixOS modules receive normal module arguments (`config`, `lib`, `pkgs`, `modulesPath`, and so on). `flake-module.nix` additionally supplies these special arguments to every NixOS system module:

- `self` and `inputs` — the flake and its inputs;
- `userHomeModules`, `userModules`, and `groupModules` — the discovered user/group maps; and
- `secretModules` — the discovered secret-module map.

The flake also injects an `unstable` package set. Use it only when a module intentionally needs a package from the unstable input.

## Module conventions

Use a module function and put repository-specific options below `my`:

```nix
{ config, lib, pkgs, ... }:
{
  options.my.example = {
    enable = lib.mkEnableOption "the example feature";
  };

  config = lib.mkIf config.my.example.enable {
    environment.systemPackages = [ pkgs.hello ];
  };
}
```

Follow the existing split between policy and activation:

- Unconditional definitions are appropriate for genuine platform-wide baselines.
- Features that a host may not need should expose a disabled-by-default option (usually `lib.mkEnableOption`) and put their implementation behind `lib.mkIf`.
- If one option depends on another, add an assertion or guard the dependent configuration as the existing deployment and tunnel modules do.
- Keep option declarations and their implementation in the same module, and use `lib.mkMerge` when several independent conditions contribute to one feature.

A new file directly under `nixos-modules/` is therefore a global change. A feature module should normally be opt-in rather than silently enabling a service on every host. System-level behavior belongs here; user programs and dotfiles belong in [`home-modules/`](../home-modules/README.md).

## Common host-facing options

The shared modules define several `my.*` options used by host modules:

- `my.users` selects account definitions from [`users/`](../users/README.md), and `my.home-manager.enable` enables the embedded Home Manager integration.
- `my.desktop.enable`, `my.work.enable`, and `my.dix.enable` are shared flags. The latter is consumed by the flake's closure-diff checks; see the [development guide](../docs/development.md).
- `my.ingress.routes` is route-driven rather than controlled by a separate `enable` flag. A route must define exactly one of `upstream` or `root`; a non-empty route set enables nginx. For example:

  ```nix
  my.ingress.routes.example = {
    upstream = "http://127.0.0.1:<service-port>";
  };
  ```

- `my.deploy-rs.enable` adds the deploy account and deploy output only when a non-empty `my.deploy-rs.authorizedKeys` list is supplied. `my.deploy-rs.githubActions.enable` additionally requires `my.deploy-rs.enable`.
- `my.cloudflared.enable` is what makes a NixOS host appear in the generated Cloudflare host map; its connector option additionally requires `my.cloudflared.enable` and a token file.

Enable these from a host rather than baking a deployment identity or secret into a reusable module. The host-level deployment, ingress, and closure-check workflow is documented in the [operations guide](../docs/operations.md); secrets and secret-module imports are covered by [`secrets/README.md`](../secrets/README.md).

## Platform boundary

These modules are evaluated in NixOS systems (Linux). Do not put nix-darwin-only `system.defaults` settings or Home Manager-only program configuration here. For macOS system configuration use [`darwin-modules/`](../darwin-modules/README.md); for shared user configuration use [`home-modules/`](../home-modules/README.md).

When adding a module, remember that every existing host evaluates it. Keep its defaults deterministic, avoid host-specific identities, and expose machine-specific choices as options for [`nixos-hosts/`](../nixos-hosts/README.md) to set.
