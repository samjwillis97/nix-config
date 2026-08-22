{ pkgs
, config
, lib
, userModules
, userHomeModules
, ...
}:
let
  availableUsers = builtins.attrNames userModules;
  selectedUsers = config.my.users;

  homeManagerUsers = lib.filter (user: builtins.hasAttr user userHomeModules) selectedUsers;
in
{
  options.my.users = lib.mkOption {
    type = with lib.types; listOf (enum availableUsers);
    default = [ ];
    description = "Users to create on the system.";
  };

  config = {
    users.users = lib.genAttrs selectedUsers (
      user:
      import userModules.${user} {
        inherit lib pkgs;
      }
    );

    home-manager.users = lib.genAttrs homeManagerUsers (user: {
      imports = [ userHomeModules.${user} ];
      home.stateVersion = "23.11";
    });
  };
}
