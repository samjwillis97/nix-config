{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  provider = config.my.agents.provider;

  selectedModelProfiles =
    if provider == null then null else config.my.agents.modelProfiles.${provider};

  defaultModelProfile =
    if selectedModelProfiles == null then null else selectedModelProfiles.models.default;

  # pi-subagents roles are extension-specific; map them to shared profiles.
  piSubagentRoles = {
    scout = {
      profile = "fast";
      thinkingLevel = "low";
    };
    researcher = {
      profile = "deep";
      thinkingLevel = "medium";
    };
    "evidence-auditor" = {
      profile = "deep";
    };
    worker = {
      profile = "default";
      thinkingLevel = "high";
    };
    reviewer = {
      profile = "default";
      thinkingLevel = "high";
    };
    oracle = {
      profile = "plan";
    };
    delegate = {
      profile = "fast";
      thinkingLevel = "low";
    };
  };

  piDefaults =
    if defaultModelProfile == null then
      { }
    else
      {
        defaultProvider = selectedModelProfiles.provider.pi;
        defaultModel = defaultModelProfile.model;
        defaultThinkingLevel = defaultModelProfile.thinkingLevel;
      };

  piSubagentSettings =
    if selectedModelProfiles == null then
      { }
    else
      {
        defaultModel = defaultModelProfile.model;
        defaultProvider = selectedModelProfiles.provider.pi;
        defaultThinking = defaultModelProfile.thinkingLevel;
        agentOverrides = lib.mapAttrs (
          _: role:
          let
            modelProfile = selectedModelProfiles.models.${role.profile};
            thinkingLevel = role.thinkingLevel or (modelProfile.thinkingLevel or null);
          in
          {
            inherit (modelProfile) model;
            inheritGlobalContext = true;
          }
          // lib.optionalAttrs (thinkingLevel != null) {
            thinking = thinkingLevel;
          }
        ) piSubagentRoles;
      };
in
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

      settings = piDefaults // {
        defaultTools = [ "+codemode" ];
        enableSkillCommands = true;
        skills = config.my.agents.skills;
        packages = [
          "npm:pi-goal-x"
          "npm:pi-subagents"
          "npm:pi-web-access"
        ];

        subagents = piSubagentSettings;
      };

      extraPackages = [
        pkgs.nodejs
        pkgs.bun
        pkgs.python3
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
      ];
    };
  };
}
