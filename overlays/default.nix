{
  self,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.brew-nix.overlays.default

    (_final: _prev: {
      neovim = self.packages.${system}.neovim;
      neovim-full = self.packages.${system}.neovim-full;
      f = self.packages.${system}.f;
      httpcraft = inputs.httpcraft.packages.${system}.httpcraft;
      nix-auth = inputs.nix-auth.packages.${system}.default;
    })
  ];
}
