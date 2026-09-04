{
  inputs,
  lib,
  pkgs,
}:
let
  # base on: https://github.com/ehllie/ez-configs/blob/eb320b3a6032a30e5fa67bebbaf381e6552f9441/flake-module.nix#L169
  # scan directory and return an attribute set of nix modules, where the key is the module name and the value is the path to the module.
  readModules =
    {
      dir,
      entryPoint ? "default.nix",
    }:
    if builtins.pathExists dir && builtins.readFileType dir == "directory" then
      lib.concatMapAttrs (
        entry: type:
        let
          dirDefault = dir + "/${entry}/${entryPoint}";
        in
        if type == "regular" && lib.hasSuffix ".nix" entry then
          { ${lib.removeSuffix ".nix" entry} = dir + "/${entry}"; }
        else if builtins.pathExists dirDefault && builtins.readFileType dirDefault == "regular" then
          { ${entry} = dirDefault; }
        else
          { }
      ) (builtins.readDir dir)
    else
      { };

  neovimModules = readModules { dir = ./modules; };
  allNeovimModules = builtins.attrValues neovimModules;

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
      {
        my = {
          git.enable = true;
        };
      }
    ]
    ++ allNeovimModules;

    extraSpecialArgs = {
      inherit inputs;
    };
  };
in
configuration.config.build.package
