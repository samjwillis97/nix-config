# Nixpkgs overlays

`overlays/default.nix` is a Nix module that contributes overlays to the
NixOS and nix-darwin configurations built by this flake. It combines selected
upstream overlays with a local overlay whose attributes point at this flake's
system-specific package outputs.

## What the local overlay does

The module derives the current system from
`pkgs.stdenv.hostPlatform.system`, then maps selected
`self.packages.${system}` outputs into `pkgs`. This lets configuration modules
write `pkgs.package-name` instead of threading `self.packages` through every
host or user module.

The overlay is imported in both generated NixOS and nix-darwin configurations
by `flake-module.nix`. It is therefore available to their Home Manager
integration as well. It is not a global mutation of every Nixpkgs import:
standalone consumers should use a flake package output, or import/adapt this
module in a matching NixOS or nix-darwin module context when they specifically
need the `pkgs` attributes.

An overlay is a package-namespace integration point, not a package selector.
Selecting a package for one host or user belongs in that configuration (for
example, `environment.systemPackages` or `home.packages`).

## Adding a local package to the overlay

Register the package output first in the `packages` attrset in `flake.nix`:

```nix
packages = {
  my-package = pkgs.callPackage ./packages/my-package { };
};
```

Then add an attribute to the local overlay:

```nix
(_final: _prev: {
  my-package = self.packages.${system}.my-package;
})
```

The package output and overlay attribute must use the same name. A package
directory by itself is not discovered, and an overlay entry cannot repair a
missing `self.packages.${system}` output. Evaluate the flake and build the
output before wiring it into a system configuration:

```sh
package_name=my-package
nix eval --json ".#packages.$(nix eval --impure --raw --expr 'builtins.currentSystem')" \
  --apply builtins.attrNames |
  jq -r '.[]'
nix build ".#${package_name}" --print-out-paths
```

Use `pkgs.my-package` only after the configuration imports this overlay. A
package that is useful only as a direct flake output does not need an overlay
entry.

## Limitations and maintenance

- The output must exist for every system that the configuration evaluates.
  The overlay does not provide a fallback package for an unsupported system.
- Overlay attributes are evaluated from `self.packages.${system}`. Keep the
  package registration and overlay change in the same update so evaluation
  does not expose a dangling attribute.
- Replacing `nixpkgs.overlays` wholesale in a host or user module can remove
  the shared upstream and local overlays. Extend the list deliberately when
  a configuration needs another overlay.
- Overlays cannot add a package to the flake's `packages` output and do not
  make package tests into flake checks. Register outputs and checks explicitly
  under `perSystem` in `flake.nix`.
- An overlay is not a substitute for choosing the right package set. A
  derivation registered with `pkgs` and one registered with the separately
  imported `inputs.unstable` set can have different dependency graphs; make
  that choice explicit in the package registration.

For package derivation structure, checks, and the stable/unstable package-set
boundary, see [the package guide](../packages/README.md).
