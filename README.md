# Nix Configuration
This repository is home to the nix code that builds my systems.

## Why Nix?
Nix allows for easy to manage, collaborative, reproducible deployments. This means that once something is setup and configured once, it works forever. If someone else shares their configuration, anyone can make use of it.

This flake is configured with the use of [digga][digga].

## TODO

- Change to a one dark theme
- Fix tmux and vim interactions
- check tmux bar

## Concepts

### Profiles
Shorthand for the definition of options in contrast to their declaration.

Current thoughts for profiles include:
  - CLI
  - Desktop
    - Audio
    - Fonts
  - Dev
  - Games (Desktop)

### Suites
Provide a mechanism for users to easily combine and name collections of profiles.

[digga]: https://github.com/divnix/digga

