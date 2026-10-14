{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
{
  options.my.amp = {
    enable = lib.mkEnableOption "amp coding agent";
  };

  config = lib.mkMerge [
    (lib.mkIf config.my.amp.enable {
      environment.systemPackages = [
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
      ];
    })
  ];
}
