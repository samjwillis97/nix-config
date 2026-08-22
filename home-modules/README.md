# Home Manager modules

Every module in this directory is discovered by `flake-module.nix` and imported into every integrated Home Manager user through `home-manager.sharedModules`. Standalone `homeConfigurations` should use the same module set when they are added.

An unconditional definition applies to every home configuration. Optional behavior should declare an option and guard its configuration with `lib.mkIf`; individual users enable or configure it in `users/<name>/home.nix`.

`zsh/default.nix` currently enables Home Manager's zsh configuration for every user. It creates user-level zsh configuration, but does not select zsh as a system account's login shell; that requires platform-level shell support and an account setting.
