{ self
, inputs
, pkgs
, ...
}:
let
  inherit (pkgs) system;
in
{
  nixpkgs.overlays = [
    inputs.nur.overlays.default

    (_final: _prev: {
      neovim = inputs.my-neovim.packages.${system}.default;
      f = self.packages.${system}.f;
    })
  ];
}
