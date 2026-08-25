# nix-darwin modules

Every module in this directory is discovered by `flake-module.nix` and imported into every nix-darwin configuration.

Use unconditional definitions for platform-wide baselines. Optional behavior should declare disabled-by-default options and apply its configuration with `lib.mkIf`; hosts enable or configure those options from `darwin-hosts/<name>/default.nix`.

Home Manager behavior belongs in `home-modules/`, not here. This directory is for macOS system configuration.
