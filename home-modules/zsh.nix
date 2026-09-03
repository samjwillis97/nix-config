{
  config,
  pkgs,
  lib,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;

  initExtra = ''
    export NOSYSZSHRC=1

    fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
    eval "$(${pkgs.zsh-patina}/bin/zsh-patina activate)"

    setopt INC_APPEND_HISTORY   # Write to history file immediate, not on exit
    setopt HIST_SAVE_NO_DUPS    # Do no write a duplicate event
    setopt HIST_VERIFY          # Do not execute immediately
    setopt HIST_NO_STORE        # Do not store the history command
    setopt HIST_REDUCE_BLANKS   # Remove leading and trailing blanks

    export PATH="$PATH:${homeDirectory}/.dotnet/tools"
    export PATH="$PATH:${homeDirectory}/go/bin"
    export PATH="$PATH:${homeDirectory}/.local/bin"
    export PATH="$PATH:${homeDirectory}/.npm-packages/bin"

    if [[ -t 0 && -t 1 ]]; then
      [[ -r ${pkgs.fzf}/share/fzf/key-bindings.zsh ]] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      [[ -r ${pkgs.fzf}/share/fzf/completion.zsh ]] && source ${pkgs.fzf}/share/fzf/completion.zsh
    fi

    ${
      if config.my.f.enable then
        ''
          if [[ -t 0 && -t 1 ]]; then
            bindkey -s ^f "${pkgs.f}/bin/f -l\n\n"
          fi
        ''
      else
        ""
    }

    export CDPATH="$CDPATH:../:../../"

    # See: https://discourse.nixos.org/t/brew-not-on-path-on-m1-mac/26770/4
    # Cache brew shellenv to avoid repeated subprocess calls
    ${
      if pkgs.stdenv.hostPlatform.isDarwin then
        ''
          if [[ ! -f ~/.cache/brew_shellenv.zsh ]] || [[ /opt/homebrew/bin/brew -nt ~/.cache/brew_shellenv.zsh ]]; then
            mkdir -p ~/.cache
            /opt/homebrew/bin/brew shellenv > ~/.cache/brew_shellenv.zsh
          fi
          source ~/.cache/brew_shellenv.zsh
        ''
      else
        ""
    }

    if [[ -t 0 && -t 1 ]]; then
      # Seems to be a problem once I removed oh-mh-zsh, delete key would enter a ~
      bindkey "^[[3~" delete-char

      # Use emacs keybindings (^A, ^E, ^K, etc.)
      bindkey -e

      # better history completion
      autoload -U up-line-or-beginning-search
      autoload -U down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search
      # Also bind application cursor keys (sent by some terminals in DECCKM mode)
      bindkey "^[OA" up-line-or-beginning-search
      bindkey "^[OB" down-line-or-beginning-search
    fi

    autoload -U promptinit; promptinit
    prompt pure
  '';
  completionInit = ''
    # Optimized compinit with caching
    autoload -Uz compinit

    # Only regenerate compdump once per day
    local zcompdump="${homeDirectory}/.zcompdump"
    if [[ -n $zcompdump(#qNmh-24) ]]; then
      compinit -C
    else
      compinit
    fi
  '';
in
{
  programs.zsh = {
    inherit completionInit;

    initContent = lib.mkMerge [
      (lib.mkOrder 880 ''
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
      '')
      (lib.mkOrder 1000 initExtra)
    ];

    enable = true;

    zprof.enable = false;

    syntaxHighlighting.enable = false;
    autosuggestion.enable = false;

    enableCompletion = true;

    history = {
      extended = true;
      save = 1000000;
      size = 1000000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      share = true;
    };

    shellAliases = {
      l = "ls -l";
      ll = "ls -alFh";
      lt = "ls --human-readable --size -1 -S --classify";
      untar = "tar -zxvf";
    };

    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];
  };
}
