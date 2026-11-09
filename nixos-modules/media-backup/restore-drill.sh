#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: restore-drill.sh [--websites] [--keep]

  --websites  Boot the Jellyfin, Radarr, Sonarr, Prowlarr, Seerr and Decypharr
              services in the VM and wait for them after the restore.
  --keep      Implies --websites. Leave the VM running with the web ports
              forwarded so the restored interfaces can be checked. Press
              Ctrl-D in the terminal when finished; the VM is then deleted.

The script reads b2-account-id, b2-application-key and restic-password from
$HOME/.config/media-restore-drill by default. Set RESTORE_DRILL_SECRETS to
use another directory.
EOF
}

keep=0
websites=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep)
      keep=1
      websites=1
      ;;
    --websites)
      websites=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$keep" -eq 1 ] && [ ! -t 0 ]; then
  echo "--keep needs an interactive terminal" >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
secrets_dir=${RESTORE_DRILL_SECRETS:-"$HOME/.config/media-restore-drill"}
repository=${RESTORE_DRILL_REPOSITORY:-"b2:swillis-media-backups:teeny"}

for file in b2-account-id b2-application-key restic-password; do
  if [ ! -s "$secrets_dir/$file" ]; then
    echo "Missing $secrets_dir/$file" >&2
    exit 1
  fi
  mode=$(stat -c %a "$secrets_dir/$file")
  if [ "$mode" != "600" ]; then
    echo "Warning: $secrets_dir/$file has mode $mode; expected 600" >&2
  fi
done

export RESTORE_DRILL_SECRETS="$secrets_dir"
export RESTORE_DRILL_REPOSITORY="$repository"
if [ "$websites" -eq 1 ]; then
  export RESTORE_DRILL_WEBSITES=1
fi
if [ "$keep" -eq 1 ]; then
  export RESTORE_DRILL_KEEP=1
fi

run_dir=$(mktemp -d "${RESTORE_DRILL_TMPDIR:-/var/tmp}/media-restore-drill.XXXXXX")
trap 'rm -rf "$run_dir"' EXIT
install -d -m 0700 "$run_dir/out"

available=$(df -Pk "$run_dir" | awk 'NR == 2 { print $4 }')
if [ "$available" -lt 20971520 ]; then
  echo "Need about 20 GiB free in $run_dir" >&2
  exit 1
fi

driver=$(nix build --no-link --print-out-paths --impure --expr "
  let
    flake = builtins.getFlake \"$repo_root\";
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  in (import \"$repo_root/nixos-modules/media-backup/restore-drill.nix\" {
    inherit pkgs;
    self = flake;
    inputs = flake.inputs;
  }).driver
")

echo "Starting a temporary restore VM. This downloads the latest snapshot from B2."
if [ "$keep" -eq 1 ]; then
  echo "The VM will stay running. Press Ctrl-D in this terminal when finished."
  if ! TMPDIR="$run_dir" "$driver/bin/nixos-test-driver" -o "$run_dir/out" 2>&1 | tee "$run_dir/driver.log"; then
    echo "Restore drill FAILED." >&2
    grep -aE 'RequestedAssertionFailed|Class B|cap exceeded|Traceback|error:' "$run_dir/driver.log" | tail -20 >&2 || true
    exit 1
  fi
else
  if ! TMPDIR="$run_dir" "$driver/bin/nixos-test-driver" -o "$run_dir/out" > "$run_dir/driver.log" 2>&1; then
    echo "Restore drill FAILED." >&2
    grep -aE 'RequestedAssertionFailed|Class B|cap exceeded|Traceback|error:' "$run_dir/driver.log" | tail -20 >&2 || true
    exit 1
  fi
fi

grep -aE 'Restored sizes:|RESTORE_DRILL_OK|test script finished|Restore drill VM is still running|http://127.0.0.1:' "$run_dir/driver.log" | tail -20
echo "Restore drill PASSED. The temporary VM and its disk were deleted."
