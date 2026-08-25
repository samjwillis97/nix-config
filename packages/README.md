# Packages

Each subdirectory contains one local package, normally as a `default.nix` expression called with `pkgs.callPackage`. Package directories are not discovered automatically; register each package under `perSystem.packages` in `flake.nix`.

Keep a package's source files beside its Nix expression and accept build dependencies as function arguments so `callPackage` can supply them.

Expose a package through an overlay only when it needs to be available as an attribute of `pkgs`; select packages for installation in the relevant host or user configuration.
