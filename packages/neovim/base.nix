{ inputs, pkgs }:
let
  nixvim = inputs.nixvim.legacyPackages.${pkgs.system};
in
nixvim.makeNixvimWithModule {
  inherit pkgs;

  extraSpecialArgs = {
    inherit inputs;
  };

  module = import ./base-config;
}
