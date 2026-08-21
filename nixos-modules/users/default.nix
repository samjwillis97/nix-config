{ config
, lib
, pkgs
, ...
}:
let
  discoverDirs =
    dir: builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));

  loadUser = user: import (./. + "/${user}") { inherit pkgs; };

  availableUsers = discoverDirs ./.;
  selectedUsers = config.my.users;
in
{
  options.my.users = lib.mkOption {
    type = with lib.types; listOf (enum availableUsers);
    default = [ ];
    description = "Users to create on the system.";
  };

  config = {
    users.users = lib.genAttrs selectedUsers loadUser;

    # home-manager here maybe
  };
}
