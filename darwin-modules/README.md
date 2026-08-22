# nix-darwin modules

This directory is the scaffold for reusable nix-darwin modules. Darwin configuration assembly is not enabled yet.

Once Darwin hosts are added, every module here should be imported into every nix-darwin configuration. Use unconditional definitions for platform-wide baselines; optional behavior should declare disabled-by-default options and apply its configuration with `lib.mkIf`.

Home Manager behavior belongs in `home-modules/`, not here. This directory is for macOS system configuration.
