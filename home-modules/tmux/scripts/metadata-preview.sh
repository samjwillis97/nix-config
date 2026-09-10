session_target="${1:-}"

if [ -z "$session_target" ]; then
  printf '%s\n' "Usage: tmux-metadata-preview <session>"
  exit 0
fi

session_name=""
windows=""
attached=""
session_path=""
created_at=""
activity_at=""

if ! IFS=$'\t' read -r session_name windows attached session_path created_at activity_at < <(
  tmux display-message -t "$session_target" -p '#{session_name}	#{session_windows}	#{session_attached}	#{session_path}	#{session_created}	#{session_activity}' 2>/dev/null
); then
  session_name=""
fi

relative_time() {
  local timestamp="$1"
  local now delta

  if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    printf '%s' "unknown"
    return
  fi

  now=$(date +%s)
  delta=$((now - timestamp))
  [ "$delta" -lt 0 ] && delta=0

  if [ "$delta" -lt 60 ]; then
    printf '%s' "just now"
  elif [ "$delta" -lt 3600 ]; then
    local minutes=$((delta / 60))
    if [ "$minutes" -eq 1 ]; then
      printf '%s' "1 minute ago"
    else
      printf '%s' "$minutes minutes ago"
    fi
  elif [ "$delta" -lt 86400 ]; then
    local hours=$((delta / 3600))
    if [ "$hours" -eq 1 ]; then
      printf '%s' "1 hour ago"
    else
      printf '%s' "$hours hours ago"
    fi
  else
    local days=$((delta / 86400))
    if [ "$days" -eq 1 ]; then
      printf '%s' "1 day ago"
    else
      printf '%s' "$days days ago"
    fi
  fi
}

if [ -n "$session_name" ]; then
  if [ "$windows" -eq 1 ]; then
    window_label="1 window"
  else
    window_label="$windows windows"
  fi

  if [ "$attached" -eq 1 ]; then
    attached_label="attached"
  else
    attached_label="detached"
  fi

  created_label=$(relative_time "$created_at")
  activity_label=$(relative_time "$activity_at")

  bold=$'\033[1m'
  dim=$'\033[2m'
  green=$'\033[32m'
  cyan=$'\033[36m'
  yellow=$'\033[33m'
  reset=$'\033[0m'

  lines=()
  lines+=("${dim}── tmux session ─────────────────────${reset}")
  lines+=("${dim}Name:     ${reset}${bold}${session_name}${reset}")
  lines+=("${dim}Windows:  ${reset}${cyan}${window_label}${reset}")
  lines+=("${dim}Status:   ${reset}${green}${attached_label}${reset}")
  lines+=("${dim}Path:     ${reset}${session_path}")
  lines+=("${dim}Created:  ${reset}${yellow}${created_label}${reset}")
  lines+=("${dim}Activity: ${reset}${yellow}${activity_label}${reset}")
  lines+=("${dim}──────────────────────────────────────${reset}")
else
  dim=$'\033[2m'
  reset=$'\033[0m'
  lines=("${dim}No session data available${reset}")
fi

content_height=${#lines[@]}
content_width=0
for line in "${lines[@]}"; do
  stripped=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')
  width=${#stripped}
  [ "$width" -gt "$content_width" ] && content_width=$width
done

preview_lines=${FZF_PREVIEW_LINES:-24}
preview_cols=${FZF_PREVIEW_COLUMNS:-80}
top_pad=$(( (preview_lines - content_height) / 2 ))
left_pad=$(( (preview_cols - content_width) / 2 ))
[ "$top_pad" -lt 0 ] 2>/dev/null && top_pad=0
[ "$left_pad" -lt 0 ] 2>/dev/null && left_pad=0

pad_str=""
for (( i=0; i<left_pad; i++ )); do
  pad_str+=" "
done

for (( i=0; i<top_pad; i++ )); do
  printf '\n'
done
for line in "${lines[@]}"; do
  printf '%s%s\n' "$pad_str" "$line"
done
