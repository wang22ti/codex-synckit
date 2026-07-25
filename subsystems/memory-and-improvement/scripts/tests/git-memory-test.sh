#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_MEMORY_SCRIPT="$SKILL_DIR/scripts/maintenance/git-memory.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

NO_GIT_BIN="$TMP_ROOT/no-git-bin"
PROJECT_ROOT="$TMP_ROOT/project"
HOME_ROOT="$TMP_ROOT/home"
mkdir -p "$NO_GIT_BIN" "$PROJECT_ROOT" "$HOME_ROOT"

for cmd_name in bash basename dirname realpath grep awk find sort head tr sed cat mktemp mkdir date pwd touch; do
    ln -s "$(command -v "$cmd_name")" "$NO_GIT_BIN/$cmd_name"
done

set +e
missing_git_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$NO_GIT_BIN" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        /bin/bash "$GIT_MEMORY_SCRIPT" status --scope project --project-root "$PROJECT_ROOT" 2>&1
)"
missing_git_status=$?
set -e

if [[ "$missing_git_status" -eq 0 ]]; then
    printf 'Expected git-memory to fail clearly when git is unavailable\n' >&2
    exit 1
fi

assert_contains "$missing_git_output" "The git-memory workflow requires the git command in PATH."

printf 'git-memory assertions passed\n'
