{ config
, lib
, userModules
, userHomeModules
, ...
}:
let
  availableUsers = lib.unique (
    builtins.attrNames userModules
    ++ builtins.attrNames userHomeModules
  );
  selectedUsers = config.my.users;

  homeManagerUsers = lib.filter (user: builtins.hasAttr user userHomeModules) selectedUsers;
in
{
  options.my = {
    users = lib.mkOption {
      type = with lib.types; listOf (enum availableUsers);
      default = [ ];
      description = "Users to create on the system.";
    };

    home-manager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Home Manager integration.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.home-manager.enable {
      home-manager.users = lib.genAttrs homeManagerUsers (user: {
        imports = [ userHomeModules.${user} ];
      });
    })
  ];
}
