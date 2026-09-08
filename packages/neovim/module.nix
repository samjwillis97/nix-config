{
  lib,
  ...
}:
let
  # Scan the implementation modules while keeping aggregate and profile modules
  # outside this directory so they are never imported as implementations.
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
in
{
  imports = builtins.attrValues (readModules {
    dir = ./modules;
  });
}
