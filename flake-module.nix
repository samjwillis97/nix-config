{ self
, inputs
, lib
, ...
}:
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

  groupModules = readModules { dir = ./groups; };

  userHomeModules = readModules {
    dir = ./users;
    entryPoint = "home.nix";
  };

  secretModules = readModules { dir = ./secrets; };

  nixosHosts = readModules { dir = ./nixos-hosts; };
  darwinHosts = readModules { dir = ./darwin-hosts; };

  nixosModules = readModules { dir = ./nixos-modules; };
  darwinModules = readModules { dir = ./darwin-modules; };
  homeModules = readModules { dir = ./home-modules; };

  allNixosModules = builtins.attrValues nixosModules;
  allDarwinModules = builtins.attrValues darwinModules;
  allHomeModules = builtins.attrValues homeModules;

  # The Home Manager module must be imported unconditionally so its options
  # exist; only its configuration can depend on a NixOS option.
  homeManagerIntegrationModule =
    { config, lib, ... }:
    let
      sharedHostHomeModule = {
        config.my.desktop.enable = lib.mkForce config.my.desktop.enable;
      };
    in
    {
      config = lib.mkIf config.my.home-manager.enable {
        home-manager = {
          sharedModules = allHomeModules ++ [
            sharedHostHomeModule
            inputs.sops-nix.homeManagerModules.sops
            inputs.direnv-instant.homeModules.direnv-instant
          ];

          useGlobalPkgs = true;
          useUserPackages = true;

          extraSpecialArgs = {
            inherit inputs secretModules;
          };
        };
      };
    };
in
{
  config.flake = rec {
    inherit nixosModules darwinModules homeModules;

    nixosConfigurations = builtins.mapAttrs
      (
        name: hostModule:
          inputs.nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit
                self
                inputs
                userHomeModules
                userModules
                groupModules
                secretModules
                ;
            };

            modules = allNixosModules ++ [
              inputs.home-manager.nixosModules.home-manager
              inputs.sops-nix.nixosModules.sops
              inputs.stylix.nixosModules.stylix
              inputs.base16.nixosModule
              homeManagerIntegrationModule
              hostModule
              {
                imports = [
                  ./overlays
                ];
                networking.hostName = name;
              }
            ];
          }
      )
      nixosHosts;

    darwinConfigurations = builtins.mapAttrs
      (
        _name: hostModule:
          inputs.nix-darwin.lib.darwinSystem {
            specialArgs = {
              inherit
                self
                inputs
                userHomeModules
                ;
            };

            modules = allDarwinModules ++ [
              inputs.home-manager.darwinModules.home-manager
              inputs.stylix.darwinModules.stylix
              inputs.base16.nixosModule
              homeManagerIntegrationModule
              hostModule
              {
                imports = [
                  ./overlays
                ];
              }
            ];
          }
      )
      darwinHosts;

    cloudflareHosts = builtins.mapAttrs
      (_name: host: {
        routes = lib.mapAttrs
          (name: route: {
            inherit (route) subdomain;
            internalHost = name;
          })
          host.config.my.ingress.routes;
      })
      (lib.filterAttrs (_name: host: host.config.my.cloudflared.enable) nixosConfigurations);

    deploy.nodes = builtins.mapAttrs
      (
        name: host:
          let
            system = host.config.nixpkgs.hostPlatform.system;
          in
          {
            hostname = name;

            profiles.system = {
              sshUser = "deploy";
              user = "root";

              path = inputs.deploy-rs.lib.${system}.activate.nixos host;
            };
          }
      )
      (lib.filterAttrs (_name: host: host.config.my.deploy-rs.enable) nixosConfigurations);

    githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
      checks = lib.getAttrs [
        "x86_64-linux"
      ]
        self.checks;
    };
  };
}
