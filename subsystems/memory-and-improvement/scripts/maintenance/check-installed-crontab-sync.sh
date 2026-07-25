#!/bin/bash
# Verify that the installed nightly maintenance cron block matches the current resolved config/defaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
begin_marker="# BEGIN memory-and-improvement nightly maintenance"
end_marker="# END memory-and-improvement nightly maintenance"

extract_managed_block() {
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { in_block=1 }
        in_block { print }
        $0 == end && in_block { exit }
    '
}

expected_output="$(bash "$SCRIPT_DIR/install-nightly-maintenance.sh" "$@")"
expected_block="$(printf '%s\n' "$expected_output" | extract_managed_block)"

installed_crontab="$(crontab -l 2>/dev/null || true)"
installed_block="$(printf '%s\n' "$installed_crontab" | extract_managed_block)"

if [[ -z "$installed_block" ]]; then
    echo "No installed memory-and-improvement cron block found." >&2
    exit 1
fi

if [[ "$installed_block" != "$expected_block" ]]; then
    echo "Installed memory-and-improvement cron block is out of sync with the current resolved defaults/config." >&2
    echo "Re-run install-nightly-maintenance.sh --apply after changing installed automation defaults." >&2
    exit 1
fi

echo "Installed memory-and-improvement cron block is in sync."
