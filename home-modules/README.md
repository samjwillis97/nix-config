# Home Manager modules

This directory contains reusable **Home Manager** modules. They configure a user's home environment, not the host's account database or operating system services.

## Discovery and loading

`flake-module.nix` scans `./home-modules` with `readModules` using the normal `default.nix` entry point:

- A regular `name.nix` directly in this directory becomes `homeModules.name`.
- A child directory becomes `homeModules.name` when it contains `default.nix`.
- Other files in a child directory are ignored by the scanner unless its `default.nix` imports them.

The discovered values are collected as `allHomeModules`. For an embedded Home Manager user, `my.home-manager.enable = true` causes `flake-module.nix` to pass all of them through `home-manager.sharedModules`, together with the sops-nix and direnv-instant Home Manager modules. The current repository's user path is embedded Home Manager in NixOS or nix-darwin; `homeModules` is also exported as a flake output for consumers that assemble a standalone Home Manager configuration. A standalone configuration must explicitly assemble the modules it needs.

The repository's two unconditional baselines are worth knowing: `home-modules/default.nix` enables Home Manager's own program integration, and `zsh.nix` enables the configured zsh program for every evaluated home. Enabling the Home Manager zsh program does not select zsh as the operating system account's login shell; account shell settings belong in the platform-specific user file.

## Module conventions

Use normal Home Manager module arguments and put repository-specific options below `my`:

```nix
{ config, lib, pkgs, ... }:
{
  options.my.example = {
    enable = lib.mkEnableOption "the example home feature";
  };

  config = lib.mkIf config.my.example.enable {
    home.packages = [ pkgs.hello ];
  };
}
```

Use unconditional definitions only for deliberate baselines. Optional applications, shell integrations, and dotfiles should expose an option and guard their configuration with `lib.mkIf`. A module is shared by every integrated user, so do not put a person's identity, secret value, or host-specific path in its unconditional body. Put user choices in `users/<name>/home.nix`.

Integrated Home Manager evaluations receive the extra arguments `inputs`, `secretModules`, and `unstable` from `flake-module.nix`, in addition to normal Home Manager arguments. A user home file can import a discovered secret module using `secretModules.<name>` when that is appropriate; do not duplicate the global Home Manager module imports in the user file.

The integration also propagates the host's `my.desktop.enable` and `my.work.enable` values with `mkForce`. Configure those host-wide switches on the platform host, then let the shared Home Manager modules consume them. Other `my.*` options, such as `my.development.enable` or `my.git.enable`, are normally selected in the user's `home.nix`.

Use `pkgs.stdenv.hostPlatform.isDarwin` or `.isLinux` when a user feature genuinely needs platform-specific behavior. Keep system-level settings in [`nixos-modules/`](../nixos-modules/README.md) or [`darwin-modules/`](../darwin-modules/README.md).

## User configuration and state versions

A user's `home.nix` is discovered from `users/<name>/home.nix` and attached when that user is selected and Home Manager is enabled on the host. It should set `home.username`, preserve the existing `home.stateVersion`, and enable the `my.*` features that user wants. `home.stateVersion` is Home Manager compatibility history, independent from a host's `system.stateVersion`; do not change either merely because a newer channel is available. See [`users/README.md`](../users/README.md) for the complete account/home matrix and [`nixos-hosts/`](../nixos-hosts/README.md) or [`darwin-hosts/`](../darwin-hosts/README.md) for host selection.

## Activation and existing files

Embedded Home Manager uses the host package set (`useGlobalPkgs`) and installs
user packages through the host integration (`useUserPackages`). Its configuration
activates with the NixOS or Darwin host, not through a separately discovered home
flake output.

The integration configures `backupFileExtension = "bak"` and
`overwriteBackup = true`. An unmanaged file that conflicts with a managed home
file can therefore be moved to a `.bak` sibling, and an existing backup can be
overwritten. These activation backups are not a versioned recovery system:
preserve important dotfiles separately before the first activation or a change
in file ownership. Review the settings in
[`flake-module.nix`](../flake-module.nix) if changing this behavior.
