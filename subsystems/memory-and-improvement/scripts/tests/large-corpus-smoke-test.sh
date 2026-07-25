#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEARCH_SCRIPT="$SKILL_DIR/scripts/recall/search-memory.sh"
ORGANIZE_SCRIPT="$SKILL_DIR/scripts/maintenance/organize-memory.sh"
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

assert_not_contains_file() {
    local path="$1"
    local needle="$2"

    if grep -Fq -- "$needle" "$path"; then
        printf 'Expected %s not to contain: %s\n' "$path" "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/large-corpus-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_MEMORY" "$STATE_ROOT"

{
    printf '# Project Learnings\n\n'
    for i in $(seq 1 1000); do
        printf -- '---\n\n'
        printf '## [LRN-LARGE-%04d] insight\n\n' "$i"
        printf '**Logged**: 2026-04-02T00:00:00Z\n'
        printf '**Priority**: medium\n'
        printf '**Status**: pending\n'
        printf '**Area**: docs\n\n'
        if [[ "$i" -eq 500 ]]; then
            summary="Large corpus recurring summary candidate"
            recurrence="3"
            pattern_key="large.corpus.recurring.candidate"
            details="Generated smoke-test entry 500 for large corpus coverage."
            suggested_action="Keep search and writeback stable at larger scale."
        elif [[ "$i" -eq 600 ]]; then
            summary="Second large corpus recurring summary candidate"
            recurrence="2"
            pattern_key="large.corpus.second.summary.candidate"
            details="Generated smoke-test entry 600 as a second recurring summary candidate."
            suggested_action="Keep multiple summary promotions stable at larger scale."
        elif [[ "$i" -eq 750 ]]; then
            summary="Large corpus reusable checklist workflow"
            recurrence="5"
            pattern_key="large.corpus.skill.candidate"
            details="After schema changes, regenerate then validate then rerun tests. This checklist should become a reusable workflow."
            suggested_action="Consider extracting a reusable skill instead of promoting this summary hint."
        elif [[ "$i" -eq 1000 ]]; then
            summary="Large corpus unique search target"
            recurrence="1"
            pattern_key="large.corpus.unique.search.target"
            details="Generated smoke-test entry 1000 for large corpus coverage."
            suggested_action="Keep search and writeback stable at larger scale."
        else
            summary="Large corpus filler entry $i"
            recurrence="1"
            pattern_key="large.corpus.filler.$i"
            details="Generated smoke-test entry $i for large corpus coverage."
            suggested_action="Keep search and writeback stable at larger scale."
        fi
        printf '### Summary\n%s\n\n' "$summary"
        printf '### Details\n%s\n\n' "$details"
        printf '### Suggested Action\n%s\n\n' "$suggested_action"
        printf '### Metadata\n'
        printf -- '- Source: automation\n'
        printf -- '- Related Files: none\n'
        printf -- '- Tags: smoke\n'
        printf -- '- Pattern-Key: %s\n' "$pattern_key"
        printf -- '- Recurrence-Count: %s\n' "$recurrence"
        printf -- '- First-Seen: 2026-04-02\n'
        printf -- '- Last-Seen: 2026-04-02\n\n'
    done
} > "$PROJECT_MEMORY/LEARNINGS.md"

cat > "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" <<'EOF'
# Project Summary Candidates

**Threshold**: recurrence >= 2
**Policy**: advisory review hints only; not every recurring item should be promoted

- [LRN-LARGE-0500] x3 (insight, pending): Large corpus recurring summary candidate
- [LRN-LARGE-0600] x2 (insight, pending): Second large corpus recurring summary candidate
EOF

search_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "unique search target"
)"

assert_contains "$search_output" "<memory-search>"
assert_contains "$search_output" "[LRN-LARGE-1000]"
assert_contains "$search_output" "Large corpus unique search target"

organize_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$ORGANIZE_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --min-recurrence 2
)"

assert_contains "$organize_output" "Organized project memory:"
assert_contains_file "$PROJECT_MEMORY/REVIEW.md" "[LRN-LARGE-0500]"
assert_contains_file "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" "[LRN-LARGE-0500]"

nightly_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --writeback true --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=project"

assert_contains_file "$PROJECT_MEMORY/SUMMARY.md" "[LRN-LARGE-0500]"
assert_contains_file "$PROJECT_MEMORY/SUMMARY.md" "[LRN-LARGE-0600]"
assert_not_contains_file "$PROJECT_MEMORY/SUMMARY.md" "[LRN-LARGE-0750]"
assert_not_contains_file "$PROJECT_MEMORY/SUMMARY.md" "[LRN-LARGE-1000]"
assert_contains_file "$PROJECT_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"

printf 'large-corpus smoke assertions passed\n'
