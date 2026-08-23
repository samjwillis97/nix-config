{
  description = "My main nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # PRE-COMMIT HOOKS
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # SECRETS
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # REMOTE DEPLOYMENT
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    # GITHUB ACTIONS
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    # THEMEING
    stylix = {
      url = "github:nix-community/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        base16.follows = "base16";
      };
    };

    base16.url = "github:SenchoPens/base16.nix";

    tt-schemes.url = "github:tinted-theming/schemes";
    tt-schemes.flake = false;
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.home-manager.flakeModules.home-manager
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
            statix.enable = true;
            flake-checker.enable = true;
            prettier.enable = true;
            actionlint.enable = true;
            detect-aws-credentials.enable = true;
            detect-private-keys.enable = true;
          };
          devShells.default = pkgs.mkShell {
            shellHook = ''
              ${config.pre-commit.shellHook}
              echo 1>&2 "Welcome to the development shell!"
            '';

            packages =
              config.pre-commit.settings.enabledPackages
              ++ (with pkgs; [
                # Secrets
                age
                ssh-to-age
                sops

                # Remote deployment
                deploy-rs
              ]);
          };
        };
    };
}
