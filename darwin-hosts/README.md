# nix-darwin hosts

Each subdirectory defines one macOS system. Its name becomes the key under `darwinConfigurations`, and its `default.nix` contains host-specific settings such as the platform, selected users, and `system.stateVersion`.

Every module in `darwin-modules/` is already imported into each host. The shared overlays and Home Manager integration are also assembled by `flake-module.nix`; configure the options they expose instead of importing them again here.

Keep configuration here when it varies by machine. Move behavior shared by multiple macOS systems into `darwin-modules/`.
