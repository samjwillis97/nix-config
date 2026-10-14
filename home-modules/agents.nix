{
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isNonEmptyString = value: builtins.isString value && value != "";

  # Keep provider IDs and reusable model profiles agent-agnostic. Harnesses
  # decide how their own roles map onto these profiles.
  modelProfiles = {
    "openai-codex" = {
      # Pi exposes the Codex OAuth backend through its `openai` provider ID.
      provider = {
        omp = "openai-codex";
        pi = "openai";
      };
      models = {
        default = {
          model = "gpt-6-luna";
          thinkingLevel = "xhigh";
        };
        fast = {
          model = "gpt-5-nano";
        };
        deep = {
          model = "gpt-6-sol";
          thinkingLevel = "high";
        };
        plan = {
          model = "gpt-6-astra";
          thinkingLevel = "high";
        };
      };
    };
    "github-copilot" = {
      provider = {
        omp = "github-copilot";
        pi = "github-copilot";
      };
      models = {
        default = {
          model = "gpt-6-luna";
          thinkingLevel = "xhigh";
        };
        fast = {
          model = "gemini-3.8-flash";
        };
        deep = {
          model = "gpt-6.1-sol";
          thinkingLevel = "high";
        };
        plan = {
          model = "gpt-6-astra";
          thinkingLevel = "high";
        };
      };
    };
  };

  networkingValue =
    name:
    if osConfig != null && osConfig ? networking && builtins.hasAttr name osConfig.networking then
      builtins.getAttr name osConfig.networking
    else
      null;

  configuredHostName =
    if isNonEmptyString (networkingValue "hostName") then
      networkingValue "hostName"
    else if isNonEmptyString (networkingValue "localHostName") then
      networkingValue "localHostName"
    else if isNonEmptyString (networkingValue "computerName") then
      networkingValue "computerName"
    else
      "unknown";

  hostname = configuredHostName;

  currentSystemContext = "
    ${lib.optionalString isDarwin ''
        # Host: ${hostname} (nix-darwin)

        This machine runs nix-darwin, with a flake-based configuration.
        Adjust your defaults accordingly — it is not a typical MacOS box.

        ## This machine's configuration
        - The nix-darwin + home-manager config lives at
          **`~/code/github.com/samjwillis97/nix-config/{BRANCH}`** (a flake).
        - Apply changes:
          `sudo darwin-rebuild switch --flake ~/code/github.com/samjwillis97/nix-config/{BRANCH}#.{CONFIG_NAME}`
        - Validate *without* switching (prefer this while iterating):
          - `nix flake check`
          - `nix build .#darwinConfigurations.{CONFIG_NAME}...
        - Run `nix fmt` on `.nix` files you touch, and keep the existing formatting/comment style.

        ## nix-darwin specifics
      ''}
    ${lib.optionalString (!isDarwin)
        ''
          # Host: ${hostname} (NixOS)

          This machine runs NixOS, with a flake-based configuration.
          Adjust your defaults accordingly — it is not a typical FHS Linux box.

          ## This machine's configuration
          - The NixOS + home-manager config lives at
            **`~/code/github.com/samjwillis97/nix-config/main`** (a flake).
          - Apply changes:
            `sudo nixos-rebuild switch --flake ~/code/github.com/samjwillis97/nix-config/{BRANCH}#${hostname}`
          - Validate *without* switching (prefer this while iterating):
            - `nix flake check`
            - `nix build .#nixosConfigurations.${hostname}.config.system.build.toplevel`
          - Run `nix fmt` on `.nix` files you touch, and keep the existing formatting/comment style.

          ## NixOS specifics
          - **Pre-built/downloaded binaries won't likely run out of the box.** NixOS
            is not FHS: there is no `/lib/ld-linux…` and libraries aren't in standard paths,
            so foreign ELF binaries fail on the dynamic linker. Prefer a nixpkgs
            build; if a foreign binary is unavoidable, use `nix run nixpkgs#steam-run
            -- ./binary` or patch it with `patchelf`.
            We leverage nix-ld so some downloaded binaries may work but it's not ideal.
        ''
      }
        - **Do not install tools imperatively.** `pip install`, `npm -g`,
          `cargo install`, `apt`, etc. do not belong here and often won't work.
          For a one-off tool, run it ephemerally: `nix run nixpkgs#<pkg> -- ...`
          or `nix shell nixpkgs#<pkg> -c <cmd>`. For something permanent, tell me
          to add it to the Nix config rather than installing it yourself.
          If working on a project, you likely want a `shell.nix` or `flake.nix`
          for that repo, not a global install.
        - `/usr/bin/env` exists, but almost nothing else lives in `/usr/bin` or
          `/bin` (except `/bin/sh`). Tools live in the Nix store (/nix/store) and on PATH.
  ";

  codeStyle = ''
    ## Code style

    - Always use braces after `if`, even for a single-line body. The only exception
      is if you are working in a codebase that has a strong, well-documented style
      guide that explicitly prefers or allows omitting braces for single-line bodies.
    - No magic numbers or strings. Hoist them into named constants, or better,
      an enum.
    - Prefer enums over booleans for function parameters — a call site should
      read as what it means, not `true`/`false`.
    - Use early returns and `continue` aggressively to keep indentation shallow.
    - Let the reader breathe: separate logical blocks with a blank line, and put
      a short, to-the-point comment above each block explaining what it does.
    - Only delete a comment when it is obsolete. When you change code, re-read
      the comment above it and make sure it is still correct.
    - Avoid bare pronouns in comments ("it", "this", "those"). Name the thing:
      not "It serves those file migration methods" but "This method serves x, y,
      and any method that has set up a migration source and sink".

    ## Tests

    - When working on a patch, write the test first. Watch it fail. Then write
      the code. Then watch it pass.
    - Open every test class and test function with a short comment saying what
      it tests and how it tests it.

    ## Tone

    - Talk to me like an engineer. Be direct and to the point, not verbose.
    - No superlatives and no praise. Give me the cold hard truth.
  '';
in
{
  options.my.agents = {
    provider = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames modelProfiles));
      default = null;
      description = "The provider to use for all configured coding agents.";
    };

    modelProfiles = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Provider and model profiles shared by all configured coding agents.";
    };

    context = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      description = "Agent-agnostic system prompt / context, shared by all coding agents.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Agent-agnostic skill directories (each containing a SKILL.md), shared by all coding agents.";
    };
  };

  config.my.agents = {
    inherit modelProfiles;

    context = ''

      ${currentSystemContext}

      ## Fetching pages behind Anubis / Cloudflare (lore.kernel.org, GNOME, ...)
      Many sites sit behind **Anubis**, a JS proof-of-work bot-wall (some behind
      Cloudflare). Plain `curl`/WebFetch just get a 403 "Access Denied" page.
      Use **`anubis-fetch <url>`** (on PATH; my own tool at
      github.com/fzakaria/anubis-fetch, wired in as a flake input):
      - Cheapest step first: a saved auth cookie → solving Anubis' SHA-256 PoW
        in-process over a Chrome-impersonating HTTP client (which also clears
        Cloudflare *passive* TLS/JA3 fingerprinting) → a headless-Chromium
        fallback for the preact/metarefresh methods, too-high difficulty, or a
        Cloudflare *active* JS challenge. Fast on the common case, general on the
        tail.
      - Cookies persist per host under `$XDG_CACHE_HOME/anubis-fetch/`, so a
        revisit skips the challenge entirely (like a browser).
      - Flags: `--text` (readable plain text), `--timeout <ms>` (default 30000),
        `--ua <str>`, `--browser` (force browser), `--no-browser` (never browser;
        exit 3 if it can't solve), `--no-cache`.
      - For **lore.kernel.org specifically** there's an even lighter path needing
        no PoW at all: public-inbox exposes machine-readable endpoints a plain
        (non-browser) UA passes straight through — append `/t.mbox.gz` to a
        thread URL (`curl -A curl ... | gunzip`) or `/raw` to a message URL.
        Prefer this for bulk/patch work.

      ## General preferences
      - Match the surrounding code's style; don't reformat unrelated lines.

      ## My personal setup
      - I have code checked out at ~/code/<host>/<org>/<repo>/<branch> (e.g. ~/code/github.com/samjwillis97/nix-config/main).
      - You can use `f` to check out code. Check here often if I have the source already when you are searching
        for something.

      ${codeStyle}
    '';

    skills = [
      ./skills/agent-browser
    ];
  };
}
