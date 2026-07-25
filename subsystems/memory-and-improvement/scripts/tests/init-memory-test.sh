#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$SKILL_DIR/scripts/bootstrap/init-memory.sh"

assert_contains_file() {
    local path="$1"
    local needle="$2"

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'Expected %s to contain: %s\n' "$path" "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/init-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
GLOBAL_MEMORY_DIR="$TMP_ROOT/custom-global-memory/.learnings"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_ROOT" "$STATE_ROOT"

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$INIT_SCRIPT" --scope global --global-memory-dir "$GLOBAL_MEMORY_DIR" >/dev/null

SUMMARY_FILE="${GLOBAL_MEMORY_DIR%/.learnings}/SUMMARY.md"

assert_contains_file "$SUMMARY_FILE" "Current high-priority principles:"
assert_contains_file "$SUMMARY_FILE" "- none recorded yet"
assert_contains_file "$SUMMARY_FILE" "## Auto Promoted Summary"
assert_contains_file "$SUMMARY_FILE" "<!-- memory-auto-summary:start -->"
assert_contains_file "$SUMMARY_FILE" "- none promoted yet"

printf 'init-memory assertions passed\n'
