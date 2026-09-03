{
  config,
  lib,
  pkgs,
  ...
}:
let
  desktopEnabled = config.my.desktop.enable;
in
{
  options.my.development = {
    enable = lib.mkEnableOption "development environment";

    runtimes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "nodejs"
          "bun"
          "python"
          "go"
        ]
      );
      default = [ ];
      description = "List of development runtimes to install, the latest will be installed";
    };

    platform-clis = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "aws"
          "cloudflare"
        ]
      );
      default = [ ];
      description = "List of platform applications to install (i.e. AWS CLI)";
    };
  };

  config = lib.mkIf config.my.development.enable (
    lib.mkMerge [
      {
        my.f.enable = true;

        home.packages = with pkgs; [
          neovim-full

          # JSON Tooling
          jq
          jless

        ];

        home.sessionVariables = {
          EDITOR = pkgs.lib.getExe pkgs.neovim;
        };

        programs = {
          direnv = {
            enable = true;
            enableZshIntegration = true;
            nix-direnv.enable = true;
            config = {
              hide_env_diff = true;
              warn_timeout = "30s"; # Reduce timeout overhead
            };
          };

          direnv-instant = {
            enable = true;
            enableZshIntegration = true;
          };
        };
      }

      (lib.mkIf desktopEnabled {
        home.packages = with pkgs; [
          insomnia
          dbeaver-bin
        ];
      })

      (lib.mkIf (lib.elem "nodejs" config.my.development.runtimes) {
        home.packages = with pkgs; [
          nodejs
        ];
      })

      (lib.mkIf (lib.elem "bun" config.my.development.runtimes) {
        home.packages = with pkgs; [
          bun
        ];
      })

      (lib.mkIf (lib.elem "python" config.my.development.runtimes) {
        home.packages = with pkgs; [
          python3
        ];
      })

      (lib.mkIf (lib.elem "go" config.my.development.runtimes) {
        home.packages = with pkgs; [
          go
        ];
      })

      (lib.mkIf (lib.elem "aws" config.my.development.platform-clis) {
        home.packages = with pkgs; [
          awscli2
        ];
      })

      (lib.mkIf (lib.elem "cloudflare" config.my.development.platform-clis) {
        home.packages = with pkgs; [
          wrangler
          cloudflared
        ];
      })
    ]
  );
}
