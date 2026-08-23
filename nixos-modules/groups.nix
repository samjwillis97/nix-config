{ lib
, groupModules
, ...
}:
{
  users.groups = lib.genAttrs (builtins.attrNames groupModules) (group: import groupModules.${group});
}
