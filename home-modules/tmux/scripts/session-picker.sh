session_list=$(tmux-session-list)

if [ -z "$session_list" ]; then
  tmux display-message "No other sessions"
  exit 0
fi

# ctrl-x: kill session, remove tracking file, and reload list (stays in fzf)
# ctrl-r: rename session (exits fzf via --expect, then uses tmux command-prompt)
# ctrl-f: jump to the f selector (same as prefix + f)
# enter: switch to session
fzf_args=(
  --ansi
  --with-nth=1
  --delimiter=$'\t'
  --preview 'tmux-metadata-preview {2}'
  --preview-window=right:60%
  --header=$'enter: switch | ctrl-x: kill | ctrl-r: rename | ctrl-f: find'
  --expect='ctrl-r'
  --bind="ctrl-x:execute-silent(tmux kill-session -t '{2}')+reload(tmux-session-list)"
  --no-sort
  --border=none
)

@findBinding@

if ! selected=$(printf '%s\n' "$session_list" | fzf "${fzf_args[@]}"); then
  exit 0
fi

if [ -z "$selected" ]; then
  exit 0
fi

# Parse fzf output: first line is the key pressed (empty for enter), rest is selected line
key=$(printf '%s' "$selected" | head -n1)
entry=$(printf '%s' "$selected" | tail -n +2)

if [ -z "$entry" ]; then
  exit 0
fi

target=$(printf '%s' "$entry" | cut -f2)

if [ "$key" = "ctrl-r" ]; then
  # Rename: use tmux command-prompt with the current name pre-filled
  tmux command-prompt -I "$target" -p "Rename session:" \
    "rename-session -t '$target' '%%'"
  exit 0
fi

# Default (enter): switch to session
tmux switch-client -t "$target"
