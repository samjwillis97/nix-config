# `f` package

`f` is packaged from the Go source in this directory. The Nix expression in
`default.nix` uses `buildGoModule`, builds the root Go package, disables cgo,
and runs `go test ./...` during the derivation check phase. The installed
executable is wrapped with the external commands used at runtime (Git, SSH,
tmux, fzf, and direnv), so callers do not need to reconstruct that `PATH`
combination in every configuration.

## Build and run

Discover the output name from the flake, then build it:

```sh
package_name=f
nix build ".#${package_name}" --print-out-paths
nix run ".#${package_name}" -- -h
```

The `-h` command prints the CLI usage. For workspace operations, pass the
root and hosting-domain settings explicitly when the defaults do not match the
machine; use shell variables rather than baking machine-specific paths into a
configuration:

```sh
workspace_root="${F_WORKSPACE_ROOT:?set F_WORKSPACE_ROOT to your workspace directory}"
git_domain="${F_GIT_DOMAIN:?set F_GIT_DOMAIN to your Git hosting domain}"
nix run .#f -- -r "$workspace_root" -g "$git_domain" -L
```

The command's `-p` mode prints an existing workspace path without creating a
workspace or starting tmux; consult `f -h` for the other list, sync, garbage
collection, and cleanup modes. Cleanup is destructive to stale worktrees, so
review the list produced by the non-destructive mode before using a cleanup
command.

## Use from a configuration

The shared overlay maps the flake package to `pkgs.f` for generated NixOS,
nix-darwin, and Home Manager configurations. The dedicated Home Manager
module exposes the opt-in `my.f.enable` option and installs `pkgs.f` when it is
enabled; see [the user and module guides](../../home-modules/README.md) for
how those modules are discovered.

A direct package selection is also possible:

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.f ];
}
```

Use the direct flake output when working outside a configuration that imports
the local overlay:

```sh
nix profile install ".#f"
```

## Updating the package

Keep Go source and dependency metadata beside `default.nix`. When changing the
Go dependencies, update the module files and the derivation's vendoring hash
together. Preserve the check phase unless the upstream test command changes;
`nix build .#f` then exercises the package's Nix build and Go test check.

The derivation is currently intentionally non-cgo. Introducing a dependency
that requires cgo is a platform/build-policy change, not just a new Go module;
update the expression, supported systems, and documentation together. Runtime
commands added by the application must also be added to the wrapper's
`lib.makeBinPath` list so a configuration does not depend on an ambient
interactive shell.
