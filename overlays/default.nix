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

    (_final: prev: {
      neovim = self.packages.${system}.neovim;
      neovim-full = self.packages.${system}.neovim-full;
      f = self.packages.${system}.f;
      httpcraft = self.packages.${system}.httpcraft;
      unreal-agent = self.packages.${system}.unreal-agent;
      nix-auth = inputs.nix-auth.packages.${system}.default;
      sidra = inputs.sidra.packages.${system}.default;
      # Upstream advertises Darwin even though anubis-fetch is not supported there.
      anubis-fetch = inputs.anubis-fetch.packages.${system}.default.overrideAttrs (oldAttrs: {
        meta = oldAttrs.meta // {
          badPlatforms = (oldAttrs.meta.badPlatforms or [ ]) ++ prev.lib.platforms.darwin;
        };
      });
    })
  ];
}
