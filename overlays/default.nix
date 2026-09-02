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
    inputs.llm-agents.overlays.shared-nixpkgs
    inputs.brew-nix.overlays.default

    (_final: _prev: {
      neovim = self.packages.${system}.neovim;
      neovim-full = self.packages.${system}.neovim-full;
      f = self.packages.${system}.f;
    })
  ];
}
