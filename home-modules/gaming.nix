{
  config,
  pkgs,
  lib,
  ...
}:
let
  filterPackages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform);
in
{
  config = lib.mkIf config.my.gaming.enable (
    lib.mkMerge [
      {
        home.packages = filterPackages (
          with pkgs;
          [
            runelite
            bolt-launcher
          ]
        );
      }
    ]
  );
}
