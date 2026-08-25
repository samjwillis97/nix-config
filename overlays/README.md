# Nixpkgs overlays

This directory contains Nixpkgs overlays imported into every NixOS and nix-darwin configuration.

Use overlays to add packages or override attributes in `pkgs`. Keep host and user package selection in the relevant system or Home Manager configuration rather than in the overlay.

Local packages must be registered under `perSystem.packages` in `flake.nix` before an overlay can reference them through `self.packages.${system}`.
