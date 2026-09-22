# Packages

This repository has two kinds of package-facing outputs:

- `perSystem.packages` contains buildable flake packages. The output set is
  registered explicitly in `flake.nix`; package directories are **not**
  discovered automatically.
- The shared overlay exposes selected outputs as `pkgs` attributes inside the
  NixOS and nix-darwin configurations. See
  [the overlay guide](../overlays/README.md) for when that indirection is
  useful.

The package source and its Nix expression live together. The reusable package
expressions in this repository are normally `default.nix` files called with
`pkgs.callPackage`; function arguments such as `buildGoModule` or runtime
dependencies are supplied by the package set.

## Discover and use package outputs

Do not maintain a hand-written package inventory in documentation. Ask the
flake which systems and package names it currently exports:

```sh
nix eval --json .#packages \
  --apply 'packages: builtins.mapAttrs (_system: systemPackages: builtins.attrNames systemPackages) packages' |
  jq -r 'to_entries[] | .key as $system | .value[] | "\($system)\t\(.)"' |
  sort
```

For the current machine, the package names can be queried without evaluating
the derivations as JSON:

```sh
system="$(nix eval --impure --raw --expr 'builtins.currentSystem')"
nix eval --json ".#packages.${system}" --apply builtins.attrNames |
  jq -r '.[]'
```

Build a package by its flake output name. Set `PACKAGE_NAME` to a name from the
listing rather than copying a stale inventory:

```sh
package_name="${PACKAGE_NAME:?set PACKAGE_NAME to a discovered output name}"
nix build ".#${package_name}" --print-out-paths
```

`nix run` is appropriate when the package has a runnable application. Use the
application's own usage argument; for example, the `f` package uses `-h`,
while other packages may use different arguments or only be libraries:

```sh
nix run ".#${package_name}" -- --help
```

Inside a NixOS, nix-darwin, or Home Manager module, use the `pkgs` attribute
when the package is exposed by the shared overlay:

```nix
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.f ];
  # Home Manager uses the same package set:
  # home.packages = [ pkgs.f ];
}
```

The corresponding package selection is configuration-owned; adding an output
to the flake does not install it everywhere. The local overlay is imported by
the generated NixOS and nix-darwin configurations. A standalone consumer
should use the direct flake output, or import/adapt the module in a matching
NixOS or nix-darwin module context when it specifically needs a `pkgs`
attribute.

For the application-specific HttpCraft configuration and command reference,
use [the HttpCraft documentation](httpcraft/docs/README.md) rather than
duplicating that material here.

## Package arguments and package sets

`perSystem` receives `pkgs` from the flake's `nixpkgs` input. A package
expression should accept the dependencies it needs as arguments and let
`callPackage` fill them. This minimal expression is a complete
`callPackage`-compatible executable; replace its body with the real build
logic for a source package:

```nix
{ writeShellApplication }:

writeShellApplication {
  name = "my-package";
  text = ''
    printf '%s\n' "my-package";
  '';
}
```

The exact build function and argument names must match the package set in use.
When an input is available from the separate `unstable` flake input, make the
choice explicit at registration time instead of silently mixing package sets:

```nix
let
  unstable_pkgs = import inputs.unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
in
{
  packages = {
    stable-package = pkgs.callPackage ./packages/stable-package { };
    unstable-package = unstable_pkgs.callPackage ./packages/unstable-package { };
  };
}
```

The current Neovim outputs follow this pattern: the editor is evaluated with
an `unstable` package set while the ordinary package registrations use
`pkgs`. Configuration modules also receive an `unstable` module argument from
`flake-module.nix`; that argument is separate from the package output
registration and should be used deliberately.

## Add or update a package

1. Create a package directory (normally with `default.nix`) and keep its
   source, lock/vendor metadata, and package-specific tests beside it.
2. Define a package function whose arguments are the tools and libraries it
   needs. Use `nativeBuildInputs` for build-time tools, `buildInputs` for
   linked/runtime dependencies, and an explicit check phase when the upstream
   project has tests.
3. Register the package manually in the `packages` attrset in `flake.nix`:

   ```nix
   packages = {
     my-package = pkgs.callPackage ./packages/my-package { };
   };
   ```

   A directory alone does not create `packages.my-package`.

4. If a package should be available as `pkgs.my-package` in configurations,
   add a matching attribute to `overlays/default.nix` after the package output
   exists. Do not use an overlay merely to select a package for one host or
   user.
5. Build the output and run its application (when applicable):

   ```sh
   package_name="${PACKAGE_NAME:?set PACKAGE_NAME to a discovered output name}"
   nix build ".#${package_name}" --print-out-paths
   nix run ".#${package_name}" -- --help
   ```

   Replace the run arguments with the application's documented command. A
   package with no executable should be checked with `nix build` instead.

Updating a derivation means updating the expression and its source metadata
together. For example, `packages/f/default.nix` uses `buildGoModule`, keeps
its Go source in the same directory, runs `go test ./...` during the
derivation's check phase, and wraps the installed executable with the runtime
tools it invokes. Preserve that relationship when changing the package; do
not move a dependency into a configuration just to make a build pass.

### Checks and supported systems

Build-time checks belong in the derivation's `checkPhase` (or the equivalent
build-function hook). Flake checks are a separate, explicit `perSystem.checks`
attrset. The repository currently registers the HttpCraft smoke check there;
new package checks must be registered intentionally rather than assuming that
`nix flake check` discovers every package test.

The root `systems` list controls which system-specific package outputs are
generated. When adding platform support, update that list only when the
derivation and its dependencies support the system, then inspect the actual
outputs and build the package for each advertised system:

```sh
package_name="${PACKAGE_NAME:?set PACKAGE_NAME to a package name}"
nix eval --json .#packages --apply builtins.attrNames |
  jq -r '.[]' |
  while IFS= read -r system; do
    nix build ".#packages.${system}.${package_name}"
  done
```

The command intentionally derives the system list from the flake. A failed
system build is a platform or dependency issue to fix in the derivation (or a
system that should not be advertised), not a reason to add a package-specific
conditional that hides the failure.

## Neovim package and module extension

Neovim is a generated Nixvim package rather than a conventional `default.nix`
derivation. The stable local API is `self.lib.mkNeovim` from
`packages/neovim/lib.nix`:

```nix
self.lib.mkNeovim {
  pkgs = nvim_pkgs;
  modules = [
    ./packages/neovim/profiles/full.nix
    ({ ... }: {
      my.theme.rainbowBrackets = false;
    })
  ];
  extraSpecialArgs = { };
}
```

`pkgs` is required. `modules` and `extraSpecialArgs` are optional; the helper
always adds the local `packages/neovim/module.nix` and binds the supplied
package set as `nixpkgs.pkgs`, then returns Nixvim's built package. The ordinary
and full outputs in `flake.nix` differ only by the explicitly composed profile
module.

`packages/neovim/module.nix` imports implementation modules from
`packages/neovim/modules`: a direct `.nix` file or a subdirectory containing
`default.nix` is discovered. The language aggregate module additionally
imports the language files beneath `packages/neovim/modules/languages/`. Add a
module there when introducing an option or feature; keep profiles under
`packages/neovim/profiles/` and pass them explicitly because profiles are not
implementation-module discovery targets.

The flake also exports `nixvimModules.default` (the local implementation
module) and `nixvimModules.full` (implementation module plus the full profile).
Consumers that compose their own Nixvim configuration can import one of those
outputs and then set the module options; consumers that need an executable
package should use `self.lib.mkNeovim`. See the focused
[Neovim extension guide](neovim/README.md) for composition examples.
