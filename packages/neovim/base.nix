{ inputs, pkgs }:
let
  nixvim = inputs.nixvim.legacyPackages.${pkgs.system};
in
nixvim.makeNixvimWithModule {
  extraSpecialArgs = {
    inherit inputs;
  };

  module = import ./base-config;
}
