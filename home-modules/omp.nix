{ config
, lib
, pkgs
, ...
}:
let
  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };

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
      enabled = !config.my.omp.settings.sandbox;
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
    modelRoles =
      if config.my.omp.settings.provider.type == "openai-codex" then
        {
          default = "github-copilot/gpt-5.6-luna:xhigh";
          advisor = "github-copilot/gpt-5.6-luna:max";
          task = "github-copilot/gpt-5.6-luna:high";
          smol = "github-copilot/gpt-5.6-luna:low";
          slow = "github-copilot/gpt-5.6-terra:high";
          plan = "github-copilot/gpt-5.6-sol:high";
          tiny = "github-copilot/gemini-3.5-flash";
          commit = "github-copilot/claude-haiku-4.5";
        }
      else if config.my.omp.settings.provider.type == "github-copilot" then
        {
          default = "openai-codex/gpt-5.6-luna:xhigh";
          advisor = "openai-codex/gpt-5.6-luna:max";
          task = "openai-codex/gpt-5.6-luna:high";
          smol = "openai-codex/gpt-5.6-luna:low";
          slow = "openai-codex/gpt-5.6-terra:high";
          plan = "openai-codex/gpt-5.6-terra:high";
          tiny = "openai-codex/gpt-5.4-nano";
          commit = "openai-codex/gpt-5.4-nano";
        }
      else
        { };
  };
in
{

  options.my.omp = {
    enable = lib.mkEnableOption "Oh-My-Pi coding agent";

    sandbox = lib.mkEnableOption "sandbox the Oh-My-Pi agent";

    settings = {
      provider = lib.mkOption {
        type = lib.types.enum [
          "openai-codex"
          "github-copilot"
        ];
        default = null;
        description = "The provider to use for the Oh-My-Pi agent.";
      };

      advisor = {
        enable = lib.mkEnableOption "advisor";
      };
    };
  };

  config = lib.mkIf config.my.omp.enable (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.llm-agents.omp
        ];

        home.file = {
          ".omp/agent/config.yml".source = yamlFormat.generate "omp-config.yml" settings;
          ".omp/agent/dap.json".source = jsonFormat.generate "omp-dap.json" {
            adapters = dapAdapters;
          };
        };
      }
    ]
  );
}
