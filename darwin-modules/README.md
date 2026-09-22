# nix-darwin modules

This directory contains reusable **nix-darwin system** modules. Every discovered module is evaluated for every Darwin host in this flake; this directory is not the place for per-user Home Manager configuration.

## Discovery and composition

`flake-module.nix` scans `./darwin-modules` with `readModules`:

- A regular `name.nix` directly in this directory becomes `darwinModules.name`.
- A child directory becomes `darwinModules.name` when it contains a regular `default.nix`.
- Files inside a child directory are not separate discovered modules unless the child entry point imports them.

The discovered values are collected as `allDarwinModules` and automatically passed to every `darwinSystem`. There is no registration list and hosts should not import these modules one by one. The Darwin assembly also includes Home Manager, sops-nix, brew-nix, Stylix, base16, and the repository overlays.

Normal module arguments (`config`, `lib`, `pkgs`, and so on) are available. The Darwin system's extra special arguments are `self`, `inputs`, `userHomeModules`, and `darwinUserModules`; the flake also injects the `unstable` package set. `secretModules` is passed to embedded Home Manager configurations, not as a Darwin host special argument.

## Module conventions

Use a module function, declare repository-specific switches below `my`, and guard optional system configuration with `lib.mkIf`:

```nix
{ config, lib, ... }:
{
  options.my.example = {
    enable = lib.mkEnableOption "the example feature";
  };

  config = lib.mkIf config.my.example.enable {
    system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;
  };
}
```

Unconditional definitions are appropriate for a setting that is intentionally a baseline on every Mac. A feature that only some hosts need should be disabled by default and enabled in [`darwin-hosts/`](../darwin-hosts/README.md). Keep the option and its implementation together, and use existing nix-darwin option types rather than inventing a parallel configuration format.

A new top-level file is therefore a global macOS change. Keep machine choices such as the primary user, work/desktop selection, and Dix checks in the host module. `my.desktop.enable`, `my.work.enable`, and `my.dix.enable` are declared by the shared Darwin module; Dix's generated closure checks are described in the [development guide](../docs/development.md).

## Home Manager boundary

System settings, fonts, Dock/Finder defaults, keyboard settings, and other nix-darwin options belong here. User programs and dotfiles belong in [`home-modules/`](../home-modules/README.md). When a host sets `my.home-manager.enable = true`, `flake-module.nix` embeds Home Manager and supplies every discovered Home Manager module through `home-manager.sharedModules`. It also forces the host's `my.desktop.enable` and `my.work.enable` values into that user's Home Manager evaluation so the two layers agree.

A Home Manager module may still use a platform check such as `pkgs.stdenv.hostPlatform.isDarwin` when a user feature has different Linux and macOS implementations. Do not put NixOS services or Linux-only boot/network configuration in a Darwin system module.

For adding a complete Mac, see [`darwin-hosts/`](../darwin-hosts/README.md). User account files and the distinction between `darwin.nix` and `home.nix` are documented in [`users/`](../users/README.md).
