{ nixvim }:
{
  mkNeovim =
    {
      pkgs,
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      configuration = nixvim.lib.evalNixvim {
        inherit system extraSpecialArgs;
        modules = [
          ./module.nix
          { nixpkgs.pkgs = pkgs; }
        ]
        ++ modules;
      };
    in
    configuration.config.build.package;
}
