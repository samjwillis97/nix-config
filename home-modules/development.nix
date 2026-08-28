{ config
, lib
, pkgs
, ...
}:
let
  desktopEnabled = config.my.desktop.enable;
in
{
  options.my.development = {
    enable = lib.mkEnableOption "development environment";
  };

  config = lib.mkIf config.my.development.enable lib.mkMerge [
    {
      my.f.enable = true;

      home.packages = with pkgs; [
        neovim

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
  ];
}
