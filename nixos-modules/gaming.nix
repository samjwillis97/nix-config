{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.my.gaming.enable (
    lib.mkMerge [
      {
        programs.steam = {
          enable = true;
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
        };
      }
    ]
  );
}
