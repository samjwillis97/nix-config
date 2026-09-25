# shellcheck shell=bash
cache_dir=$(session_cache_dir)
session_name="${1:-}"
if [ -z "$session_name" ]; then
  exit 0
fi

mkdir -p "$cache_dir"
encoded=$(encode_session_name "$session_name")
# Nanosecond precision keeps rapid session switches ordered deterministically.
printf '%s' "$(date +%s%N)" > "$cache_dir/$encoded"
