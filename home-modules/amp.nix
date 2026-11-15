{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  filterPackages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform);
in
{
  options.my.amp = {
    enable = lib.mkEnableOption "Enable the Amp CLI + Desktop app module";
  };

  config = lib.mkIf config.my.amp.enable {
    home.packages = filterPackages [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp-desktop
    ];

    programs.amp = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp;
    };
  };

}
