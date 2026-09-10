# shellcheck shell=bash
cache_dir=$(session_cache_dir)
session_name="${1:-}"
if [ -z "$session_name" ]; then
  exit 0
fi

mkdir -p "$cache_dir"
encoded=$(encode_session_name "$session_name")
printf '%s' "$(date +%s)" > "$cache_dir/$encoded"
