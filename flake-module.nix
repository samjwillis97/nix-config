{ inputs, lib, ... }:
let
  # from: https://github.com/ehllie/ez-configs/blob/eb320b3a6032a30e5fa67bebbaf381e6552f9441/flake-module.nix#L169
  # scan directory and return an attribute set of nix modules, where the key is the module name and the value is the path to the module.
  readModules =
    { dir
    , entryPoint ? "default.nix"
    ,
    }:
    if builtins.pathExists "${dir}.nix" && builtins.readFileType "${dir}.nix" == "regular" then
      { default = dir; }
    else if builtins.pathExists dir && builtins.readFileType dir == "directory" then
      lib.concatMapAttrs
        (
          entry: type:
          let
            dirDefault = "${dir}/${entry}/${entryPoint}";
          in
          if type == "regular" && lib.hasSuffix ".nix" entry then
            { ${lib.removeSuffix ".nix" entry} = "${dir}/${entry}"; }
          else if builtins.pathExists dirDefault && builtins.readFileType dirDefault == "regular" then
            { ${entry} = dirDefault; }
          else
            { }
        )
        (builtins.readDir dir)
    else
      { };

  userModules = readModules { dir = ./users; };

  userHomeModules = readModules {
    dir = ./users;
    entryPoint = "home.nix";
  };

  nixosHosts = readModules { dir = ./nixos-hosts; };

  nixosModules = readModules { dir = ./nixos-modules; };
  homeModules = readModules { dir = ./home-modules; };

  allNixosModules = builtins.attrValues nixosModules;
  allHomeModules = builtins.attrValues homeModules;

  # Shared NixOS/nix-darwin module.
  homeManagerIntegrationModule = {
    home-manager = {
      sharedModules = allHomeModules;

      extraSpecialArgs = {
        inherit inputs;
      };
    };
  };
in
{
  options.my.users = lib.mkOption {
    type = with lib.types; listOf (enum users);
    default = [ ];
    description = "Users to create on OS configurations.";
  };

  config.flake = {
    inherit nixosModules homeModules;

    nixosConfigurations = builtins.mapAttrs
      (
        _name: hostModule:
          inputs.nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit inputs userHomeModules userModules;
            };

            modules = allNixosModules ++ [
              inputs.home-manager.nixosModules.home-manager
              homeManagerIntegrationModule
              hostModule
            ];
          }
      )
      nixosHosts;

    # darwinConfigurations = {
    #   test-mac = inputs.nix-darwin.lib.darwinSystem {
    #   };
    # };
  };
}
