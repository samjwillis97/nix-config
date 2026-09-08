{
  config,
  lib,
  pkgs,
  ...
}:
let
  editorPackage = if config.my.development.enable then pkgs.neovim-full else pkgs.neovim;
in
{
  home.packages = [ editorPackage ];

  home.sessionVariables = {
    EDITOR = lib.getExe editorPackage;
  };
}
