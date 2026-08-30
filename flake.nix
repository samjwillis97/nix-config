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

    nur = {
      url = "github:nix-community/NUR";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # PRE-COMMIT HOOKS
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # SECRETS
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # REMOTE DEPLOYMENT
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    # TERRAFORM
    terranix = {
      url = "github:terranix/terranix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

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

    # Dev Tools
    my-neovim.url = "github:samjwillis97/modular-neovim-flake";
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # Media Server
    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.home-manager.flakeModules.home-manager
        inputs.git-hooks.flakeModule
        inputs.terranix.flakeModule
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
          packages.f = pkgs.callPackage ./packages/f { };
          apps.deploy = inputs.deploy-rs.apps.${pkgs.stdenv.hostPlatform.system}.default;

          terranix.terranixConfigurations.cloudflare = {
            modules = [
              ./terranix/cloudflare.nix
            ];

            extraArgs = {
              inherit (self) cloudflareHosts;
              cloudflareSettings = {
                accountId = "75eabfce45add00e729e977b056ea024";
                zoneId = "4a5b0bb6db200785f5dfe66b28f971e0";
                zoneName = "williscloud.org";
              };
            };

            workdir = ".terranix/cloudflare";

            terraformWrapper = {
              package = pkgs.opentofu;

              extraRuntimeInputs = [
                pkgs.sops
              ];

              prefixText = ''
                CLOUDFLARE_API_TOKEN="$(
                  sops \
                    --decrypt \
                    --extract '["api-token"]' \
                    ${./secrets/terranix/cloudflare.yaml}
                )"
                export CLOUDFLARE_API_TOKEN
              '';
            };
          };

          pre-commit.settings.hooks = {
            nixpkgs-fmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            flake-checker.enable = true;
            prettier.enable = true;
            actionlint.enable = true;
            detect-aws-credentials.enable = true;
            detect-private-keys.enable = true;

            zizmor = {
              enable = true;
              name = "zizmor";
              entry = "${pkgs.lib.getExe pkgs.zizmor} --persona=auditor --no-ignores";
              files = "^\\.github/workflows/.*\\.(yml|yaml)$";
              pass_filenames = true;
            };
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

                # github action checks
                zizmor

                # Remote deployment
                deploy-rs
              ]);
          };
        };
    };
}
