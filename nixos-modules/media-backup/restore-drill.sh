#!/usr/bin/env bash
set -euo pipefail

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
  in (import \"$repo_root/nixos-modules/media-backup/restore-drill.nix\" { inherit pkgs; }).driver
")

echo "Starting a temporary restore VM. This downloads the latest snapshot from B2."
if ! TMPDIR="$run_dir" "$driver/bin/nixos-test-driver" -o "$run_dir/out" > "$run_dir/driver.log" 2>&1; then
  echo "Restore drill FAILED." >&2
  grep -aE 'RequestedAssertionFailed|Class B|cap exceeded|Traceback|error:' "$run_dir/driver.log" | tail -20 >&2 || true
  exit 1
fi

grep -aE 'Restored sizes:|RESTORE_DRILL_OK|test script finished' "$run_dir/driver.log" | tail -10
echo "Restore drill PASSED. The temporary VM and its disk were deleted."
