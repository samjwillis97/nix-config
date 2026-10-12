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
    "${inputs.home-manager-source}/modules/programs/pi-coding-agent.nix"
  ];

  options.my.pi = {
    enable = lib.mkEnableOption "Enable the Pi Agent module";
  };

  config = lib.mkIf config.my.pi.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

      configDir = "${config.xdg.configHome}/pi/agent";

      context = config.my.agents.context;

      settings = {
        defaultTools = [ "+codemode" ];
        enableSkillCommands = true;
        skills = config.my.agents.skills;
      };

      extraPackages = [
        pkgs.nodejs
        pkgs.bun
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
      ];
    };
  };
}
