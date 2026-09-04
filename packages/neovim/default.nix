{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;

  nvimPkgs = import inputs.unstable {
    inherit system;
    config.allowUnfree = true;
  };

  configuration = inputs.nixvim.lib.evalNixvim {
    inherit system;

    modules = [
      {
        nixpkgs.pkgs = nvimPkgs;
      }
      (import ./full-config)
    ];

    extraSpecialArgs = {
      inherit inputs;
    };
  };
in
configuration.config.build.package
