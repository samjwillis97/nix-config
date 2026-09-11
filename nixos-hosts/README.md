# NixOS hosts

Each subdirectory defines one NixOS system. Its name becomes the key under `nixosConfigurations`, and its `default.nix` contains host-specific imports and settings such as hardware configuration and `my.users`.

Every module in `nixos-modules/` is already imported into each host. Do not import those modules individually here; configure the options they expose instead.

Keep configuration here when it varies by machine. Move behavior shared by multiple NixOS hosts into `nixos-modules/`.

The encrypted Git identity used by workstation hosts authenticates SSH Git transport and signs commits; it does not authenticate the GitHub CLI API. Enrol `gh` once as the workstation user with `gh auth login --web --git-protocol ssh --skip-ssh-key`. Keep that OAuth credential as mutable per-user state rather than sharing it through the machine SOPS groups; use a dedicated, narrowly scoped token secret only for unattended workloads.
