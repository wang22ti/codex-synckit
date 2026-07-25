#!/bin/bash
# Verify that the installed cron block matches the currently resolved installer output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-nightly-maintenance.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [installer arguments...]

Pass the same optional arguments you would give to install-nightly-maintenance.sh
when you want to verify a non-default installed cron entry.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

begin_marker="# BEGIN memory-and-improvement nightly maintenance"
end_marker="# END memory-and-improvement nightly maintenance"

extract_block() {
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { in_block=1 }
        in_block { print }
        $0 == end && in_block { exit }
    '
}

expected_block="$(
    bash "$INSTALL_SCRIPT" "$@" | extract_block
)"

installed_crontab="$(crontab -l 2>/dev/null || true)"
installed_block="$(printf '%s\n' "$installed_crontab" | extract_block)"

if [[ -z "$installed_block" ]]; then
    printf 'Crontab sync check failed: installed memory-and-improvement cron block is missing.\n' >&2
    exit 1
fi

if [[ "$installed_block" != "$expected_block" ]]; then
    printf 'Crontab sync check failed: installed cron block does not match current resolved installer output.\n' >&2
    exit 1
fi

printf 'Crontab sync check passed.\n'
