{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  hostname = config.networking.hostName;

  currentSystemContext = "";
in
{
  imports = [
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

      context = ''
        # Host: persona-(NixOS)

        This machine runs **NixOS** with a flake-based configuration. Adjust your
        defaults accordingly — it is not a typical FHS Linux box.

        ## NixOS specifics
        - **Do not install tools imperatively.** `pip install`, `npm -g`,
          `cargo install`, `apt`, etc. do not belong here and often won't work.
          For a one-off tool, run it ephemerally: `nix run nixpkgs#<pkg> -- ...`
          or `nix shell nixpkgs#<pkg> -c <cmd>`. For something permanent, tell me
          to add it to the Nix config rather than installing it yourself.
          If working on a project, you likely want a `shell.nix` or `flake.nix`
          for that repo, not a global install.
        - **Pre-built/downloaded binaries won't likely run out of the box.** NixOS
          is not FHS: there is no `/lib/ld-linux…` and libraries aren't in standard paths,
          so foreign ELF binaries fail on the dynamic linker. Prefer a nixpkgs
          build; if a foreign binary is unavoidable, use `nix run nixpkgs#steam-run
          -- ./binary` or patch it with `patchelf`.
          We leverage nix-ld so some downloaded binaries may work but it's not ideal.
        - `/usr/bin/env` exists, but almost nothing else lives in `/usr/bin` or
          `/bin` (except `/bin/sh`). Tools live in the Nix store (/nix/store) and on PATH.

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

        ## This machine's configuration
        - The NixOS + home-manager config lives at
          **`/home/fmzakari/code/github.com/fzakaria/nix-home`** (a flake).
        - Apply changes:
          `sudo nixos-rebuild switch --flake ~/code/github.com/fzakaria/nix-home#nyx`
        - Validate *without* switching (prefer this while iterating):
          - `nix flake check`
          - `nix build .#nixosConfigurations.nyx.config.system.build.toplevel`
          - home-manager pieces: `nix build .#homeConfigurations.fmzakari.activationPackage`
        - Run `nix fmt` on `.nix` files you touch, and keep the existing formatting/comment style.
      '';

      extraPackages = [
        pkgs.nodejs
        pkgs.bun
      ];
    };
  };
}
