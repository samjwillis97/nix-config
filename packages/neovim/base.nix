{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;

  nvimPkgs = import inputs.unstable {
    inherit system;
    config.allowUnfree = true;
  };

  nixvim = inputs.nixvim.legacyPackages.${system};
in
nixvim.makeNixvimWithModule {
  pkgs = nvimPkgs;

  extraSpecialArgs = {
    inherit inputs;
  };

  module = import ./base-config;
}
