# Nix Configuration
This repository is home to the nix code that builds my systems.

## Why Nix?
Nix allows for easy to manage, collaborative, reproducible deployments. This means that once something is setup and configured once, it works forever. If someone else shares their configuration, anyone can make use of it.

This flake is configured with the use of [digga][digga].

## Inspiration

- https://github.com/thiagokokada/nix-configs
- https://github.com/JayRovacsek/nix-config

## TODO

- Add i3 lock
- Add Nvidia
- Add Logitech
- Add Gaming
- Workout what overlays do lol
- Re add sound block to i3status-rs
- Fix i3status-rs look
- Determine way to differentiate systems for different blocks in i3status
- Investigate using nix for building node programs
- Change i3 + alacritty + rofi one dark theme
- Fix tmux and vim interactions, currently need C-w + direction to move within vim when in tmux
- Remove tmux theme
- Setup Feh for backgrounds in i3
- Determine why Firefox Bookmarks don't work
- Workout how to apply configurations to the likes of PyCharm and WebStorm
- Modify the root setup to my likings:
  - Remove Starship
- Look into storing secrets - agenix?
- nnn Configuration
- Doom Emacs
- Notifications with Dunst
- Get Steam/Runelite working
- Picom
- Nvidia
- Pipewire
- Test working on Darwin
- Test working on aarch64
- Better Theming

[digga]: https://github.com/divnix/digga

