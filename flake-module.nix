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
    if builtins.pathExists dir && builtins.readFileType dir == "directory" then
      lib.concatMapAttrs
        (
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

  darwinUserModules = readModules {
    dir = ./users;
    entryPoint = "darwin.nix";
  };

  secretModules = readModules { dir = ./secrets; };

  nixosHosts = readModules { dir = ./nixos-hosts; };
  darwinHosts = readModules { dir = ./darwin-hosts; };

  nixosModules = readModules { dir = ./nixos-modules; };
  darwinModules = readModules { dir = ./darwin-modules; };
  homeModules = readModules { dir = ./home-modules; };
  mkUnstable =
    pkgs:
    import inputs.unstable {
      inherit (pkgs) system config;
    };

  unstablePackageModule =
    { pkgs, ... }:
    {
      _module.args.unstable = mkUnstable pkgs;
    };

  allNixosModules = builtins.attrValues nixosModules;
  allDarwinModules = builtins.attrValues darwinModules;
  allHomeModules = builtins.attrValues homeModules;

  # The Home Manager module must be imported unconditionally so its options
  # exist; only its configuration can depend on a NixOS option.
  homeManagerIntegrationModule =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      sharedHostHomeModule = {
        config.my.desktop.enable = lib.mkForce config.my.desktop.enable;
        config.my.work.enable = lib.mkForce config.my.work.enable;
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
            unstable = mkUnstable pkgs;
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
              unstablePackageModule
              inputs.home-manager.nixosModules.home-manager
              inputs.sops-nix.nixosModules.sops
              inputs.nixflix.nixosModules.default
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
                darwinUserModules
                ;
            };

            modules = allDarwinModules ++ [
              unstablePackageModule
              inputs.home-manager.darwinModules.home-manager
              inputs.brew-nix.darwinModules.default
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

    githubActions =
      let
        deployConfigurations = lib.filterAttrs
          (
            _name: host: host.config.my.deploy-rs.githubActions.enable
          )
          nixosConfigurations;
        deployChecks = builtins.foldl'
          (
            checks: name:
              let
                host = deployConfigurations.${name};
                system = host.config.nixpkgs.hostPlatform.system;
              in
              checks
              // {
                ${system} = (checks.${system} or { }) // {
                  ${name} = deploy.nodes.${name}.profiles.system.path;
                };
              }
          )
          { }
          (builtins.attrNames deployConfigurations);
        homeConfigurations = self.homeConfigurations or { };
        dixChecks =
          let
            entries =
              (lib.mapAttrsToList
                (name: host: {
                  system = host.config.nixpkgs.hostPlatform.system;
                  name = "nixosConfiguration-${name}";
                  drv = host.config.system.build.toplevel;
                })
                (lib.filterAttrs (_name: host: host.config.my.dix.enable) nixosConfigurations))
              ++ (lib.mapAttrsToList
                (name: host: {
                  system = host.pkgs.stdenv.hostPlatform.system;
                  name = "homeConfiguration-${name}";
                  drv = host.activationPackage;
                })
                (
                  lib.filterAttrs
                    (
                      _name: host: lib.attrByPath [ "config" "my" "dix" "enable" ] false host
                    )
                    homeConfigurations
                )
              )
              ++ (lib.mapAttrsToList
                (name: host: {
                  system = host.config.nixpkgs.hostPlatform.system;
                  name = "darwinConfiguration-${name}";
                  drv = host.system;
                })
                (lib.filterAttrs (_name: host: host.config.my.dix.enable) darwinConfigurations));
          in
          builtins.foldl'
            (
              checks: check:
                checks
                // {
                  ${check.system} = (checks.${check.system} or { }) // {
                    ${check.name} = check.drv;
                  };
                }
            )
            { }
            entries;
      in
      (inputs.nix-github-actions.lib.mkGithubMatrix {
        checks = lib.getAttrs [
          "x86_64-linux"
        ]
          self.checks;
      })
      // {
        deploy = inputs.nix-github-actions.lib.mkGithubMatrix {
          checks = deployChecks;
          attrPrefix = "githubActions.deploy.checks";
        };
        dix = inputs.nix-github-actions.lib.mkGithubMatrix {
          checks = dixChecks;
          attrPrefix = "githubActions.dix.checks";
        };
      };
  };
}
