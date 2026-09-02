{ inputs
, config
, lib
, pkgs
, ...
}:
let
  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };

  agentSandbox = import inputs.agent-sandbox { inherit pkgs; };

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
      enabled = !config.my.omp.sandbox;
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
      if config.my.omp.settings.provider == "github-copilot" then
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
      else if config.my.omp.settings.provider == "openai-codex" then
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

  allowedGetDomains = [
    "githubusercontent.com"
    "npmjs.org"
    "nodejs.org"
    "developer.mozilla.org"
    "omp.sh"
    "html.duckduckgo.com"
    "typescriptlang.org"
    "tanstack.com"
    "shadcn.com"
    "supabase.com"
    "nextjs.org"
    "react.dev"
    "docs.aws.amazon.com"
    "channels.nixos.org"
    "cache.nixos.org"
    "raw.githubusercontent.com"
  ];

  sandboxGetDomainsMapped = builtins.listToAttrs (
    map
      (domain: {
        name = domain;
        value = [
          "GET"
          "HEAD"
        ];
      })
      allowedGetDomains
  );

  omp-sandboxed = agentSandbox.mkSandbox {
    pkg = pkgs.llm-agents.omp;
    binName = "omp";
    outName = "omp";
    allowedPackages = with pkgs; [
      curl
      wget
      file
      coreutils
      which
      git
      ripgrep
      fd
      gnused
      gnugrep
      findutils
      jq
      nodejs
      vscode-js-debug
      python3
      openssh
      difftastic
      gnused
      nix
      man
      llm-agents.omp
      bun
      gh
    ];
    rwDirs = [
      "$HOME/.omp"
      "$HOME/.npm"
      "$HOME/.cache"
      "$HOME/.config/gh"
      "$HOME/.config/git"
      "$HOME/.config/httpcraft"
      "/nix/var/nix/daemon-socket"
    ];
    roFiles = [
      "$TMPDIR/agenix/ssh-key"
      "$TMPDIR/agenix/ssh-key.pub"
    ];
    roDirs = [
      "$HOME/code"
    ];
    allowNix = true;
    allowUnixSockets = true;
    allowedLocatPorts = null;
    allowedDomains = {
      # Copilot required domains (MITM-filtered)
      "githubcopilot.com" = "*";

      "github.com" = "*";
      "api.github.com" = "*";
    }
    // sandboxGetDomainsMapped;
    env = {
      # Keep the OAuth callback on the host loopback interface, rather than
      # routing it through the sandbox's outbound filtering proxy.
      NO_PROXY = "localhost,127.0.0.1,::1";
      no_proxy = "localhost,127.0.0.1,::1";
    };
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

      (lib.mkIf (!config.my.omp.sandbox) {
        home.packages = [
          pkgs.llm-agents.omp
        ];
      })

      (lib.mkIf config.my.omp.sandbox {
        home.packages = [
          omp-sandboxed
        ];
      })
    ]
  );
}
