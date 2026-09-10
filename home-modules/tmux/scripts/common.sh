cache_dir="$HOME/.cache/tmux-session-history"

encode_session_name() {
  local name="$1"
  name="${name//%/%25}"
  name="${name//\//%2F}"
  printf '%s' "$name"
}
