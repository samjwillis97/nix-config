{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let

  ompPackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;

  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };

  selectedModelProfiles =
    if config.my.agents.provider == null then
      null
    else
      config.my.agents.modelProfiles.${config.my.agents.provider};

  # OMP roles are harness-specific; map them onto the shared model profiles.
  ompRoles = {
    default = {
      profile = "default";
    };
    advisor = {
      profile = "default";
      thinkingLevel = "max";
    };
    task = {
      profile = "default";
      thinkingLevel = "high";
    };
    smol = {
      profile = "default";
      thinkingLevel = "low";
    };
    slow = {
      profile = "deep";
    };
    plan = {
      profile = "plan";
    };
    tiny = {
      profile = "fast";
    };
    commit = {
      profile = "fast";
    };
  };

  modelRoles =
    if selectedModelProfiles == null then
      { }
    else
      lib.mapAttrs (
        _: role:
        let
          modelProfile = selectedModelProfiles.models.${role.profile};
          thinkingLevel = role.thinkingLevel or (modelProfile.thinkingLevel or null);
        in
        "${selectedModelProfiles.provider.omp}/${modelProfile.model}"
        + lib.optionalString (thinkingLevel != null) ":${thinkingLevel}"
      ) ompRoles;

  contextFile = pkgs.writeText "omp-agents.md" config.my.agents.context;

  dapAdapters = {
    node = {
      command = "${pkgs.vscode-js-debug}/bin/js-debug";
      args = [ "--stdio" ];
      languages = [
        "javascript"
        "typescript"
      ];
      fileTypes = [
        ".cjs"
        ".cts"
        ".js"
        ".jsx"
        ".mjs"
        ".mts"
        ".ts"
        ".tsx"
      ];
      rootMarkers = [
        "package.json"
        "tsconfig.json"
      ];
      launchDefaults = {
        type = "pwa-node";
        request = "launch";
      };
    };
  };

  settings = {
    setupVersion = 1;
    symbolPreset = "nerd";
    theme = {
      dark = "titanium";
      light = "light";
    };
    statusLine = {
      separator = "slash";
    };
    tui = {
      tight = true;
    };
    personality = "pragmatic";
    debug.enabled = true;
    advisor = {
      enabled = config.my.omp.settings.advisor.enable;
      syncBacklog = 3;
    };
    startup = {
      quiet = true;
      setupWizard = false;
      checkUpdate = false;
      changeLogMode = "hidden";
    };
    features = {
      unexpectedStopDetection = true;
    };
    lsp = {
      enabled = true;
      lazy = true;
      shared = false;
      formatOnWrite = false;
      diagnosticsOnWrite = true;
      diagnosticsOnEdit = true;
      diagnosticsDeduplicate = true;
    };
    github = {
      enabled = true;
      cache.enabled = true;
    };
    browser = {
      enabled = true;
    };
    dev = {
      autoqa = false;
    };
    task = {
      eager = "preferred";
      enableEffort = true;
      enableLsp = true;
      maxRecursionDepth = 3;
    };
    skills.enabled = true;
    inherit modelRoles;
  };

  configFile = yamlFormat.generate "omp-config.yml" settings;
  dapFile = jsonFormat.generate "omp-dap.json" {
    adapters = dapAdapters;
  };

in
{
  imports = [ ./agents.nix ];

  options.my.omp = {
    enable = lib.mkEnableOption "Oh-My-Pi coding agent";

    settings = {
      advisor = {
        enable = lib.mkEnableOption "advisor";
      };
    };
  };

  config = lib.mkIf config.my.omp.enable {
    # OMP locks and atomically rewrites its configuration. Home Manager's
    # normal store symlinks are read-only, so install regular writable files.
    home.activation.ompConfig = {
      before = [ ];
      after = [ "writeBoundary" ];
      data = ''
        run mkdir -p "$HOME/.omp/agent"
        run install -m 600 ${configFile} "$HOME/.omp/agent/config.yml"
        run install -m 600 ${dapFile} "$HOME/.omp/agent/dap.json"
        run install -m 600 ${contextFile} "$HOME/.omp/agent/AGENTS.md"
      '';
    };

    home.packages = [
      ompPackage
    ];
  };
}
