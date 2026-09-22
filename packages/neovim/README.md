# Neovim package and modules

This directory contains the local Nixvim integration used by the flake. It is
split into three contracts:

- `lib.nix` exposes `mkNeovim`, which evaluates a Nixvim module list and
  returns the built editor package.
- `module.nix` imports the reusable implementation modules beneath `modules/`.
- `profiles/` contains opt-in compositions, including `full.nix`; profiles are
  not imported automatically by `module.nix`.

The package output registration and the package-set choice live in the root
`flake.nix`. The generic package lifecycle is documented in
[the package guide](../README.md).

## Build a custom editor

`self.lib.mkNeovim` is the supported local constructor. Its required argument
is a Nixpkgs package set; it also accepts a `modules` list and
`extraSpecialArgs` attrset:

```nix
let
  nvim_pkgs = import inputs.unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
  my_neovim = self.lib.mkNeovim {
    pkgs = nvim_pkgs;
    modules = [
      ./packages/neovim/profiles/full.nix
      ({ ... }: {
        my.theme.rainbowBrackets = false;
      })
    ];
    extraSpecialArgs = { };
  };
in
{
  packages.custom-neovim = my_neovim;
}
```

The constructor always evaluates these base modules in order:

1. Nixvim's evaluator is called with the requested system and
   `extraSpecialArgs`.
2. `packages/neovim/module.nix` is imported.
3. The supplied package set is bound as `nixpkgs.pkgs`.
4. The caller's `modules` are appended.

The result is `configuration.config.build.package`, not the intermediate
Nixvim configuration attrset. Use a separate package registration when you
want the result to be available as a flake package.

The root flake follows this contract for its ordinary and full editor outputs.
It evaluates both with the separately imported `unstable` package set; the full
variant adds `profiles/full.nix`. That profile is an example of composition,
not a requirement that every consumer use all features.

## Add an implementation module

`module.nix` discovers implementation modules by reading
`packages/neovim/modules/`:

- a direct `feature.nix` file is imported as the `feature` module;
- a `feature/default.nix` file is imported as the `feature` module;
- files and directories outside those shapes are ignored by this discovery
  pass.

A module can define Nixvim options and merge configuration when enabled. For
example, the existing Treesitter module defines `my.treesitter.enable`,
`my.treesitter.grammars`, and `my.treesitter.showContext`, then guards its
plugin configuration with `lib.mkIf`. Follow that option/configuration split
for a new feature instead of unconditionally changing every editor.

Language support has one additional layer:
`modules/languages/default.nix` imports the language files beneath its own
folder and defines the shared `my.languages` switches (`all`, `lsp`, `dap`,
and `formatter`). A new language file belongs there when it follows that
aggregate contract. It does not need to be added to the top-level module
imports separately.

Profiles belong in `profiles/` so they remain explicit compositions. Import a
profile in `mkNeovim { modules = [ ... ]; }` or in a consumer's Nixvim module
list. Do not place a profile in `modules/` unless it is intended to be enabled
for every editor that imports the base module.

## Consume exported module sets

The flake exports two reusable Nixvim module values under `nixvimModules`:

- `nixvimModules.default` is the local implementation module;
- `nixvimModules.full` imports that module and the full profile.

A consumer composing its own Nixvim configuration can import one of those
outputs from the flake input and then set the exposed options. A consumer that
needs the final executable should use `lib.mkNeovim` instead, because the
module output alone is not a built package.

Module options use ordinary Nix module merge semantics. Keep custom changes in
an additional module so they can override or extend the profile without
forking it, for example:

```nix
modules = [
  ./packages/neovim/profiles/full.nix
  ({ ... }: {
    my.icons.enable = false;
    my.treesitter.showContext = false;
  })
];
```

The option names above are provided by the local implementation modules. When
adding a new option, document its default and guard the resulting configuration
with the option so a plain `nixvimModules.default` import remains predictable.
