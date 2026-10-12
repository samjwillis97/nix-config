{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  provider = config.my.omp.settings.provider;

  defaultModelRole =
    if provider == "github-copilot" then
      "github-copilot/gpt-5.6-luna:xhigh"
    else if provider == "openai-codex" then
      "openai/gpt-5.6-luna:xhigh"
    else
      null;

  modelRoleParts = lib.splitString "/" defaultModelRole;
  modelAndThinkingParts = lib.splitString ":" (lib.elemAt modelRoleParts 1);

  piDefaults = lib.optionalAttrs (defaultModelRole != null) {
    defaultProvider = lib.elemAt modelRoleParts 0;
    defaultModel = lib.elemAt modelAndThinkingParts 0;
    defaultThinkingLevel = lib.elemAt modelAndThinkingParts 1;
  };
in
{
  imports = [
    ./agents.nix
    "${inputs.home-manager-source}/modules/programs/pi-coding-agent.nix"
  ];

  options.my.pi = {
    enable = lib.mkEnableOption "Enable the Pi Agent module";

    provider = lib.mkOption {
      type = lib.types.enum [
        "openai-codex"
        "github-copilot"
      ];
      default = null;
      description = "The provider to use for the Pi agent.";
    };
  };

  config = lib.mkIf config.my.pi.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

      configDir = "${config.xdg.configHome}/pi/agent";

      context = config.my.agents.context;

      settings = piDefaults // {
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
