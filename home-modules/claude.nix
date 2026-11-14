{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./agents.nix
  ];

  options.my.claude = {
    enable = lib.mkEnableOption "Enable the Claude CLI + Desktop module";
  };

  config = lib.mkIf config.my.claude.enable {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
    ];

    programs.claude-code = {
      enable = true;
      context = config.my.agents.context;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    };
  };

}
