{
  config,
  lib,
  pkgs,
  ...
}:
let
  fEnabled = config.my.f.enable;

  # MRU tracking cache directory. Also referenced in tmux-metadata-preview.nix.
  cache_dir = "$HOME/.cache/tmux-session-history";

  # Encode a session name for use as a flat filename.
  # Replaces % with %25 first, then / with %2F, so names like
  # "samjwillis97/nix-config-v2/main" become safe filenames.
  # Pure bash -- no subprocess spawns.
  # Must be kept in sync across tmux-session-track, tmux-session-list,
  # tmux-metadata-preview, and the ctrl-x kill binding.
  encode_name = ''
    encode_session_name() {
      local name="$1"
      name="''${name//%/%25}"
      name="''${name//\//%2F}"
      printf '%s' "$name"
    }
  '';

  # Small script called by the tmux client-session-changed hook.
  # Records the epoch timestamp for the session that was just left.
  tmux-session-track = pkgs.writeShellScriptBin "tmux-session-track" ''
    ${encode_name}

    session_name="$1"
    if [ -z "$session_name" ]; then
      exit 0
    fi

    cache_dir="${cache_dir}"
    ${pkgs.coreutils}/bin/mkdir -p "$cache_dir"
    encoded=$(encode_session_name "$session_name")
    printf '%s' "$(${pkgs.coreutils}/bin/date +%s)" > "$cache_dir/$encoded"
  '';

  # Called by the session-closed hook to remove the tracking file for a destroyed session.
  tmux-session-track-clean = pkgs.writeShellScriptBin "tmux-session-track-clean" ''
    ${encode_name}

    session_name="$1"
    if [ -z "$session_name" ]; then
      exit 0
    fi

    cache_dir="${cache_dir}"
    encoded=$(encode_session_name "$session_name")
    rm -f "$cache_dir/$encoded"
  '';

  # Helper script to generate session list for fzf (used for initial load and reload)
  # Outputs sessions sorted by most-recently-used (sessions without history at the bottom).
  tmux-session-list = pkgs.writeShellScriptBin "tmux-session-list" ''
    ${encode_name}

    current_session=$(${pkgs.tmux}/bin/tmux display-message -p '#{session_name}' 2>/dev/null)
    cache_dir="${cache_dir}"

    # Two arrays: sessions with MRU history and sessions without
    mru_entries=()
    no_history_entries=()

    while IFS=$'\t' read -r name windows attached; do
      # Skip the current session
      if [ "$name" = "$current_session" ]; then
        continue
      fi

      if [ "$attached" = "1" ]; then
        indicator="(attached)"
      else
        indicator=""
      fi

      if [ "$windows" = "1" ]; then
        win_label="1 window"
      else
        win_label="$windows windows"
      fi

      label="$name  $win_label $indicator"

      # Check for MRU tracking file
      encoded=$(encode_session_name "$name")
      if [ -f "$cache_dir/$encoded" ]; then
        ts=$(< "$cache_dir/$encoded")
        if [ -n "$ts" ]; then
          mru_entries+=("$ts"$'\t'"$label"$'\t'"$name")
        else
          no_history_entries+=("$label"$'\t'"$name")
        fi
      else
        no_history_entries+=("$label"$'\t'"$name")
      fi
    done < <(${pkgs.tmux}/bin/tmux list-sessions \
      -F '#{session_name}	#{session_windows}	#{session_attached}' 2>/dev/null)

    # Output MRU sessions sorted by timestamp descending (most recent first)
    if [ ''${#mru_entries[@]} -gt 0 ]; then
      printf '%s\n' "''${mru_entries[@]}" \
        | ${pkgs.coreutils}/bin/sort -t$'\t' -k1,1 -rn \
        | ${pkgs.coreutils}/bin/cut -f2-
    fi

    # Output no-history sessions sorted alphabetically
    if [ ''${#no_history_entries[@]} -gt 0 ]; then
      printf '%s\n' "''${no_history_entries[@]}" \
        | ${pkgs.coreutils}/bin/sort -t$'\t' -k1,1
    fi
  '';

  tmux-session-picker = pkgs.writeShellScriptBin "tmux-session-picker" ''
    session_list=$(${lib.getExe tmux-session-list})

    if [ -z "$session_list" ]; then
      ${pkgs.tmux}/bin/tmux display-message "No other sessions"
      exit 0
    fi

    # ctrl-x: kill session, remove tracking file, and reload list (stays in fzf)
    # ctrl-r: rename session (exits fzf via --expect, then uses tmux command-prompt)
    # ctrl-f: jump to the f selector (same as prefix + f)
    # enter: switch to session
    selected=$(printf '%s\n' "$session_list" | \
      ${pkgs.fzf}/bin/fzf \
        --ansi \
        --with-nth=1 \
        --delimiter=$'\t' \
        --preview 'tmux-metadata-preview {2}' \
        --preview-window=right:60% \
        --header=$'enter: switch | ctrl-x: kill | ctrl-r: rename | ctrl-f: find' \
        --expect='ctrl-r' \
        ${lib.optionalString fEnabled ''--bind="ctrl-f:become(${pkgs.f}/bin/f -l)" \''}
        --bind="ctrl-x:execute-silent(${pkgs.tmux}/bin/tmux kill-session -t '{2}')+reload(${lib.getExe tmux-session-list})" \
        --no-sort \
        --border=none)

    if [ -z "$selected" ]; then
      exit 0
    fi

    # Parse fzf output: first line is the key pressed (empty for enter), rest is selected line
    key=$(printf '%s' "$selected" | ${pkgs.coreutils}/bin/head -n1)
    entry=$(printf '%s' "$selected" | ${pkgs.coreutils}/bin/tail -n +2)

    if [ -z "$entry" ]; then
      exit 0
    fi

    target=$(printf '%s' "$entry" | ${pkgs.coreutils}/bin/cut -f2)

    if [ "$key" = "ctrl-r" ]; then
      # Rename: use tmux command-prompt with the current name pre-filled
      ${pkgs.tmux}/bin/tmux command-prompt -I "$target" -p "Rename session:" \
        "rename-session -t '$target' '%%'"
      exit 0
    fi

    # Default (enter): switch to session
    ${pkgs.tmux}/bin/tmux switch-client -t "$target"
  '';
in
{
  options.my.tmux = {
    enable = lib.mkEnableOption "tmux";
  };

  config = lib.mkIf config.my.tmux.enable {
    programs.tmux = {
      enable = true;
      sensibleOnTop = false;
      package = pkgs.tmux;

      aggressiveResize = true;
      baseIndex = 1;
      historyLimit = 10000;
      newSession = false;

      prefix = "C-b";
      terminal = "screen-256color";

      plugins = with pkgs; [
        tmuxPlugins.tmux-fzf
      ];

      extraConfig = with config.lib.stylix.colors; ''
        # Clear MRU session tracking cache on server start / config reload
        # run-shell 'rm -rf $HOME/.cache/tmux-session-history && mkdir -p $HOME/.cache/tmux-session-history'

        # Better splitting
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"

        # Smart pane switching with awareness of Vim splits.
        # See: https://github.com/christoomey/vim-tmux-navigator
        is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
            | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
        bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h'  'select-pane -L'
        bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j'  'select-pane -D'
        bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k'  'select-pane -U'
        bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l'  'select-pane -R'
        tmux_version='$(tmux -V | sed -En "s/^tmux ([0-9]+(.[0-9]+)?).*/\1/p")'
        if-shell -b '[ "$(echo "$tmux_version < 3.0" | bc)" = 1 ]' \
            "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\'  'select-pane -l'"
        if-shell -b '[ "$(echo "$tmux_version >= 3.0" | bc)" = 1 ]' \
            "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\\\'  'select-pane -l'"

        bind-key -T copy-mode-vi 'C-h' select-pane -L
        bind-key -T copy-mode-vi 'C-j' select-pane -D
        bind-key -T copy-mode-vi 'C-k' select-pane -U
        bind-key -T copy-mode-vi 'C-l' select-pane -R
        bind-key -T copy-mode-vi 'C-\' select-pane -l

        set-window-option -g mode-keys vi
        bind -T copy-mode-vi v send-keys -X begin-selection
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'

        # Better sessions
        ${
          if fEnabled then
            ''
              bind-key -r f display-popup -E -w 80% -h 80% "${pkgs.f}/bin/f -l"
            ''
          else
            ""
        }

        # Enabled 256 Color
        set -g default-terminal "tmux-256color"
        set-option -ga terminal-overrides ',xterm-256color:Tc'

        # Track session usage (MRU) - records timestamp when switching to a session
        set-hook -g client-session-changed 'run-shell "${lib.getExe tmux-session-track} \"#{session_name}\""'

        # Clean up MRU tracking file when a session is destroyed
        set-hook -g session-closed 'run-shell "${lib.getExe tmux-session-track-clean} \"#{hook_session}\""'

        # fzf session picker
        bind s display-popup -E -w 80% -h 80% "${lib.getExe tmux-session-picker}"

        # Enable scrolling
        set -g mouse on

        # Passing through enter properly
        set -g extended-keys on
        set -g extended-keys-format csi-u

        # Pass through title
        set -g set-titles-string '#{pane_title}'

        # Fix switching delay
        set -sg escape-time 0

        # easy reload
        bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "~/.tmux.conf reloaded"

        # default statusbar colors

        thm_bg="#${base00}"
        thm_fg="#${base05}"
        thm_cyan="#${base0C}"
        thm_black="#${base00}"
        thm_gray="#${base02}"
        thm_magenta="#${base0E}"
        thm_pink="#${base0F}"
        thm_red="#${base08}"
        thm_green="#${base0B}"
        thm_yellow="#${base0A}"
        thm_blue="#${base0D}"
        thm_orange="#${base09}"
        thm_black4="#${base03}"

        # Refresh status bar every 5 seconds for notification indicator
        set-option -gq status-interval 5

        # --------=== Statusline

        set-option -gq status-left ""
        set-option -gq status-right "#[fg=$thm_yellow,bg=$thm_bg]#(tmux-oc-notification-status)#[default] #[fg=$thm_pink,bg=$thm_bg,nobold,nounderscore,noitalics]#[fg=$thm_bg,bg=$thm_pink,nobold,nounderscore,noitalics] #[fg=$thm_fg,bg=$thm_gray] #{b:pane_current_path} #{?client_prefix,#[fg=$thm_red],#[fg=$thm_green]}#[bg=$thm_gray]#{?client_prefix,#[bg=$thm_red],#[bg=$thm_green]}#[fg=$thm_bg] #[fg=$thm_fg,bg=$thm_gray] #S "

        # current_application
        set-window-option -gq window-status-format "#[fg=$thm_bg,bg=$thm_blue] #I #[fg=$thm_fg,bg=$thm_gray] #W "
        set-window-option -gq window-status-current-format "#[fg=$thm_bg,bg=$thm_orange] #I #[fg=$thm_fg,bg=$thm_bg] #W "

        # --------=== Modes
        set-window-option -gq clock-mode-colour "''${thm_blue}"
        set-window-option -gq mode-style "fg=''${thm_pink} bg=''${thm_black4} bold"

        # Pane number display
        set-option -g display-panes-active-colour colour33
        set-option -g display-panes-colour colour166
      '';
    };
  };
}
