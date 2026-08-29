{ config, lib, ... }:
let
  # Get all the modules in this folder besides default.nix
  mediaModules = map (v: ./. + "/${v}") (
    lib.filter (file: file != "default.nix") (builtins.attrNames (builtins.readDir ./.))
  );
in
{
  imports = mediaModules;

  options.my.media = {
    enable = lib.mkEnableOption "media server";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.media.enable {
      nixflix = {
        enable = true;

        # mediaDir = "/data/media";
        # stateDir = "/data/.state";

        postgres.enable = true;
      };
    })
  ];
}
