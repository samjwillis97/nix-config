{
  description = "My main nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nur = {
      url = "github:nix-community/NUR";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs = {
        brew-api.follows = "brew-api";
        nix-darwin.follows = "nix-darwin";
        nixpkgs.follows = "nixpkgs";
      };
    };

    # MICROVM
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
      url = "github:nix-community/stylix/release-26.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        base16.follows = "base16";
        nur.follows = "nur";
      };
    };

    base16.url = "github:SenchoPens/base16.nix";

    tt-schemes.url = "github:tinted-theming/schemes";
    tt-schemes.flake = false;

    # Dev Tools
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    agent-sandbox = {
      url = "github:archie-judd/agent-sandbox.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        nixpkgs.follows = "unstable";
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
          packages = {
            f = pkgs.callPackage ./packages/f { };
            neovim-full = pkgs.callPackage ./packages/neovim/full.nix {
              inherit inputs;
            };
            neovim = pkgs.callPackage ./packages/neovim/base.nix {
              inherit inputs;
            };
          };

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

                # diff nix ouputs
                dix

                # github action checks
                zizmor

                # Remote deployment
                deploy-rs
              ]);
          };
        };
    };
}
