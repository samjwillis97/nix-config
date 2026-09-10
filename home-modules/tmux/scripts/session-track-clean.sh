# shellcheck shell=bash
cache_dir=$(session_cache_dir)
session_name="${1:-}"
if [ -z "$session_name" ]; then
  exit 0
fi

encoded=$(encode_session_name "$session_name")
rm -f "$cache_dir/$encoded"
