#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHORTCUTS_DIR="$SKILL_DIR/scripts/shortcuts"

assert_file_contains() {
    local path="$1"
    local needle="$2"

    grep -Fq -- "$needle" "$path" || {
        printf 'Expected %s to contain: %s\n' "$path" "$needle" >&2
        exit 1
    }
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-shortcuts-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
GLOBAL_ROOT="$TMP_ROOT/global-memory"
STATE_ROOT="$TMP_ROOT/state"
FACT_FILE="$TMP_ROOT/PROFILE.md"
ASSET_FILE="$TMP_ROOT/screenshot.png"

mkdir -p "$PROJECT_ROOT"
mkdir -p "$STATE_ROOT"
printf '# Profile\n' > "$FACT_FILE"
: > "$ASSET_FILE"

COMMON_ENV=(
    "SELF_IMPROVING_PROJECT_ROOT=$PROJECT_ROOT"
    "SELF_IMPROVING_GLOBAL_ROOT=$GLOBAL_ROOT"
    "SELF_IMPROVING_GLOBAL_NAMESPACE=user-profile"
    "XDG_STATE_HOME=$STATE_ROOT"
)

env "${COMMON_ENV[@]}" bash "$SHORTCUTS_DIR/remember-project-fact.sh" \
    --summary "Repo fact" \
    --details "Project-specific detail" \
    --suggested-action "Keep using the local convention" >/dev/null

env "${COMMON_ENV[@]}" bash "$SHORTCUTS_DIR/remember-global-fact.sh" \
    --summary "Cross-project fact" \
    --details "Durable user-level fact" \
    --suggested-action "Load this when profile context matters" >/dev/null

env "${COMMON_ENV[@]}" bash "$SHORTCUTS_DIR/remember-error.sh" \
    --summary "Build failure" \
    --error-text "command exited 1" \
    --context "CI pipeline" \
    --suggested-fix "Regenerate the cache" >/dev/null

env "${COMMON_ENV[@]}" bash "$SHORTCUTS_DIR/index-factual-file.sh" \
    --namespace user-profile \
    --title "Profile" \
    --canonical-path "$FACT_FILE" \
    --summary "Canonical profile file" >/dev/null

env "${COMMON_ENV[@]}" bash "$SHORTCUTS_DIR/index-asset.sh" \
    --title "Screenshot" \
    --type screenshot \
    --canonical-path "$ASSET_FILE" \
    --summary "Project screenshot asset" >/dev/null

PROJECT_LEARNINGS="$PROJECT_ROOT/.learnings/LEARNINGS.md"
PROJECT_ERRORS="$PROJECT_ROOT/.learnings/ERRORS.md"
PROJECT_ASSETS="$PROJECT_ROOT/.learnings/assets/INDEX.md"
GLOBAL_LEARNINGS="$GLOBAL_ROOT/namespaces/user-profile/.learnings/LEARNINGS.md"
GLOBAL_ASSETS="$GLOBAL_ROOT/namespaces/user-profile/assets/INDEX.md"

assert_file_contains "$PROJECT_LEARNINGS" "] insight"
assert_file_contains "$PROJECT_LEARNINGS" "Repo fact"
assert_file_contains "$GLOBAL_LEARNINGS" "] insight"
assert_file_contains "$GLOBAL_LEARNINGS" "Cross-project fact"
assert_file_contains "$PROJECT_ERRORS" "Build failure"
assert_file_contains "$PROJECT_ERRORS" "command exited 1"
assert_file_contains "$GLOBAL_ASSETS" "- Type: structured_fact_file"
assert_file_contains "$GLOBAL_ASSETS" "- Canonical-Path: $FACT_FILE"
assert_file_contains "$PROJECT_ASSETS" "- Type: screenshot"
assert_file_contains "$PROJECT_ASSETS" "- Canonical-Path: $ASSET_FILE"

printf 'shortcut smoke assertions passed\n'
