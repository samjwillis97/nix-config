{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
{
  options.my.amp = {
    enable = lib.mkEnableOption "Enable the Amp CLI + Desktop app module";
  };

  config = lib.mkIf config.my.amp.enable {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp-desktop
    ];

    programs.amp = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp;
    };
  };

}
