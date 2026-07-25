#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NIGHTLY_SCRIPT="$SKILL_DIR/scripts/maintenance/nightly-maintenance.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_contains_file() {
    local path="$1"
    local needle="$2"

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'Expected %s to contain: %s\n' "$path" "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multi-project-nightly-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

STATE_ROOT="$TMP_ROOT/state"
PROJECT_ROOT="$TMP_ROOT/project-1"
CODEXKIT_ROOT="$TMP_ROOT/OneDrive/CodexKit"
REGISTRY_FILE="$CODEXKIT_ROOT/memory-system/project-memory-registry.tsv"

mkdir -p "$STATE_ROOT"
mkdir -p "$(dirname "$REGISTRY_FILE")"
printf 'storage\tdevice\tpath\n' > "$REGISTRY_FILE"

make_project_fixture() {
    local root="$1"
    local summary_text="$2"
    local pattern_key="$3"
    local memory_dir="$root/.learnings"

    mkdir -p "$memory_dir"
    cat > "$memory_dir/LEARNINGS.md" <<EOF
# Project Learnings

---

## [LRN-$(basename "$root" | tr '[:lower:]-' '[:upper:]_')-001] insight

**Logged**: 2026-04-03T00:00:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
$summary_text

### Details
Generated project-multi-root smoke fixture.

### Suggested Action
Keep nightly maintenance stable across many registered project memories.

### Metadata
- Source: automation
- Related Files: none
- Tags: smoke
- Pattern-Key: $pattern_key
- Recurrence-Count: 2
- First-Seen: 2026-04-03
- Last-Seen: 2026-04-03

---
EOF
}

for i in $(seq 1 12); do
    project="$TMP_ROOT/project-$i"
    summary="Project $i recurring summary candidate"
    pattern_key="multi.project.$i"
    make_project_fixture "$project" "$summary" "$pattern_key"
    printf 'local\tTEST-DEVICE\t%s/.learnings\n' "$project" >> "$REGISTRY_FILE"
done

nightly_output="$(
    env \
        COMPUTERNAME="TEST-DEVICE" \
        SELF_IMPROVING_CODEXKIT_ROOT="$CODEXKIT_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" --scope project --git-commit false --writeback true --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=project"

for i in $(seq 1 12); do
    project="$TMP_ROOT/project-$i"
    assert_contains_file "$project/.learnings/SUMMARY.md" "Project $i recurring summary candidate"
done

printf 'multi-project nightly smoke assertions passed\n'
