{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.my._1password = {
    enable = lib.mkEnableOption "1Password features/applications";
  };

  config = lib.mkIf config.my._1password.enable (
    lib.mkMerge [
      {
        home.packages = with pkgs; [
          _1password-cli
        ];
      }

      (lib.mkIf config.my.desktop.enable {
        home.packages = with pkgs; [
          _1password-gui
        ];
      })
    ]
  );
}
