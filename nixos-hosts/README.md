# NixOS hosts

Each subdirectory defines one NixOS system. Its name becomes the key under `nixosConfigurations`, and its `default.nix` contains host-specific imports and settings such as hardware configuration and `my.users`.

Every module in `nixos-modules/` is already imported into each host. Do not import those modules individually here; configure the options they expose instead.

Keep configuration here when it varies by machine. Move behavior shared by multiple NixOS hosts into `nixos-modules/`.