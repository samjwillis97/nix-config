current_session=$(tmux display-message -p '#{session_name}' 2>/dev/null)

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
done < <(tmux list-sessions \
  -F '#{session_name}	#{session_windows}	#{session_attached}' 2>/dev/null)

# Output MRU sessions sorted by timestamp descending (most recent first)
if [ ${#mru_entries[@]} -gt 0 ]; then
  printf '%s\n' "${mru_entries[@]}" \
    | sort -t$'\t' -k1,1 -rn \
    | cut -f2-
fi

# Output no-history sessions sorted alphabetically
if [ ${#no_history_entries[@]} -gt 0 ]; then
  printf '%s\n' "${no_history_entries[@]}" \
    | sort -t$'\t' -k1,1
fi
