{
  description = "A highly structured configuration database.";

  nixConfig.extra-experimental-features = "nix-command flakes";
  nixConfig.extra-substituters = "https://nrdxp.cachix.org https://nix-community.cachix.org";
  nixConfig.extra-trusted-public-keys = "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";

  inputs =
    {
      # Track channels with commits tested and built by hydra
      nixos.url = "github:nixos/nixpkgs/nixos-21.11";
      latest.url = "github:nixos/nixpkgs/nixos-unstable";
      # For darwin hosts: it can be helpful to track this darwin-specific stable
      # channel equivalent to the `nixos-*` channels for NixOS. For one, these
      # channels are more likely to provide cached binaries for darwin systems.
      # But, perhaps even more usefully, it provides a place for adding
      # darwin-specific overlays and packages which could otherwise cause build
      # failures on Linux systems.
      nixpkgs-darwin-stable.url = "github:NixOS/nixpkgs/nixpkgs-21.11-darwin";

      digga.url = "github:divnix/digga";
      digga.inputs.nixpkgs.follows = "nixos";
      digga.inputs.nixlib.follows = "nixos";
      digga.inputs.home-manager.follows = "home";
      digga.inputs.deploy.follows = "deploy";

      bud.url = "github:divnix/bud";
      bud.inputs.nixpkgs.follows = "nixos";
      bud.inputs.devshell.follows = "digga/devshell";

      home.url = "github:nix-community/home-manager/release-21.11";
      home.inputs.nixpkgs.follows = "nixos";

      darwin.url = "github:LnL7/nix-darwin";
      darwin.inputs.nixpkgs.follows = "nixpkgs-darwin-stable";

      deploy.url = "github:serokell/deploy-rs";
      deploy.inputs.nixpkgs.follows = "nixos";

      agenix.url = "github:ryantm/agenix";
      agenix.inputs.nixpkgs.follows = "nixos";

      nvfetcher.url = "github:berberman/nvfetcher";
      nvfetcher.inputs.nixpkgs.follows = "nixos";

      naersk.url = "github:nmattia/naersk";
      naersk.inputs.nixpkgs.follows = "nixos";

      nixos-hardware.url = "github:nixos/nixos-hardware";

      nixos-generators.url = "github:nix-community/nixos-generators";

      nnn-plugins.url = "github:jarun/nnn/v4.4";
      nnn-plugins.flake= false;

      emacs-overlay.url = "github:nix-community/emacs-overlay";
    };

  outputs =
    { self
    , digga
    , bud
    , nixos
    , home
    , nixos-hardware
    , nur
    , agenix
    , nvfetcher
    , deploy
    , nixpkgs
    , ...
    } @ inputs':
    let
      # TODO: https://github.com/divnix/digga/issues/464
      inputs = inputs' // {
        emacs-overlay = inputs'.emacs-overlay // {
          overlay = self.lib.overlayNullProtector inputs'.emacs-overlay.overlay;
        };
      };
    in
    digga.lib.mkFlake
      {
        inherit self inputs;

        channelsConfig = { allowUnfree = true; };

        channels = {
          nixos = {
            imports = [ (digga.lib.importOverlays ./overlays) ];
            overlays = [ inputs.emacs-overlay.overlay ];
          };
          nixpkgs-darwin-stable = {
            imports = [ (digga.lib.importOverlays ./overlays) ];
            overlays = [ ];
          };
          latest = { };
        };

        lib = import ./lib { lib = digga.lib // nixos.lib; };

        sharedOverlays = [
          (final: prev: {
            __dontExport = true;
            lib = prev.lib.extend (lfinal: lprev: {
              our = self.lib;
            });
          })

          nur.overlay
          agenix.overlay
          nvfetcher.overlay

          (import ./pkgs)
        ];

        nixos = {
          hostDefaults = {
            system = "x86_64-linux";
            channelName = "nixos";
            imports = [ (digga.lib.importExportableModules ./modules) ];
            modules = [
              { lib.our = self.lib; }
              digga.nixosModules.bootstrapIso
              digga.nixosModules.nixConfig
              home.nixosModules.home-manager
              agenix.nixosModules.age
              bud.nixosModules.bud
            ];
          };

          imports = [ (digga.lib.importHosts ./hosts/nixos) ];
          hosts = {
            /* set host-specific properties here */
            NixOS = { };
            dev-vm = { };
            desktop = { };
          };
          importables = rec {
            profiles = digga.lib.rakeLeaves ./profiles // {
              users = digga.lib.rakeLeaves ./users;
            };
            suites = with profiles; rec {
              base = [ core.nixos core-cli users.nixos users.root users.sam];
	            desktopBase = base ++ [ dev office audio core-gui fonts social ];
              gnomeBase = desktopBase ++ [ gnome-desktop ];
              i3Base = desktopBase ++ [ i3-desktop ];
            };
          };
        };

        darwin = {
          hostDefaults = {
            system = "x86_64-darwin";
            channelName = "nixpkgs-darwin-stable";
            imports = [ (digga.lib.importExportableModules ./modules) ];
            modules = [
              { lib.our = self.lib; }
              digga.darwinModules.nixConfig
              home.darwinModules.home-manager
              agenix.nixosModules.age
            ];
          };

          imports = [ (digga.lib.importHosts ./hosts/darwin) ];
          hosts = {
            /* set host-specific properties here */
            Mac = { };
          };
          importables = rec {
            profiles = digga.lib.rakeLeaves ./profiles // {
              users = digga.lib.rakeLeaves ./users;
            };
            suites = with profiles; rec {
              base = [ core.darwin users.darwin ];
            };
          };
        };

        home = {
          imports = [ (digga.lib.importExportableModules ./users/modules) ];
          modules = [ ];
          importables = rec {
            profiles = digga.lib.rakeLeaves ./users/profiles;
            suites = with profiles; rec {
              base = [ direnv git ];
              baseGUI = [ firefox alacritty ];
              baseCLI = [ zsh vim tmux nnn ];
              baseDesktop = baseGUI ++ baseCLI;
              baseDev = [ dev emacs ];
              i3Desktop = baseDesktop ++ baseDev ++ [ i3 rofi picom ];
            };
          };
          users = {
            nixos = { suites, ... }: { imports = suites.base; };
            sam = { suites, ... }: { imports = suites.i3Desktop; };
            darwin = { suites, ... }: { imports = suites.base; };
          }; # digga.lib.importers.rakeLeaves ./users/hm;
        };

        devshell = ./shell;

        homeConfigurations = digga.lib.mergeAny
          (digga.lib.mkHomeConfigurations self.darwinConfigurations)
          (digga.lib.mkHomeConfigurations self.nixosConfigurations)
        ;

        deploy.nodes = digga.lib.mkDeployNodes self.nixosConfigurations { };

      }
  ;
}
