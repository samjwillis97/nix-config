{
  description = "My main nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # inputs.home-manager.flakeModules.home-manager
        inputs.git-hooks.flakeModule
        ./flake-module.nix
      ];

      # Supported OS'
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { config
        , pkgs
        , ...
        }:
        {
          pre-commit.settings.hooks = {
            nixpkgs-fmt.enable = true;
            deadnix.enable = true;
          };
          devShells.default = pkgs.mkShell {
            shellHook = ''
              ${config.pre-commit.shellHook}
              echo 1>&2 "Welcome to the development shell!"
            '';

            # Equivalent to self.checks.${system}.pre-commit-check.enabledPackages;
            packages = config.pre-commit.settings.enabledPackages;
          };
        };
    };
}
