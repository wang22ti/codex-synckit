#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEARCH_SCRIPT="$SKILL_DIR/scripts/recall/search-memory.sh"
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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mixed-type-large-corpus-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_MEMORY/assets" "$STATE_ROOT"

{
    printf '# Project Learnings\n\n'
    for i in $(seq 1 250); do
        printf -- '---\n\n'
        printf '## [LRN-MIX-%03d] insight\n\n' "$i"
        printf '**Logged**: 2026-04-02T00:00:00Z\n'
        printf '**Priority**: medium\n'
        printf '**Status**: pending\n'
        printf '**Area**: docs\n\n'
        if [[ "$i" -eq 120 ]]; then
            summary="Mixed-type large corpus recurring summary candidate"
            recurrence="3"
            pattern_key="mixed.type.summary.candidate"
        else
            summary="Mixed-type learning filler $i"
            recurrence="1"
            pattern_key="mixed.type.learning.$i"
        fi
        printf '### Summary\n%s\n\n' "$summary"
        printf '### Details\nGenerated mixed-type learning entry %d.\n\n' "$i"
        printf '### Suggested Action\nKeep mixed-type maintenance stable.\n\n'
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

{
    printf '# Project Errors\n\n'
    for i in $(seq 1 200); do
        printf -- '---\n\n'
        printf '## [ERR-MIX-%03d] operation\n\n' "$i"
        printf '**Logged**: 2026-04-02T00:00:00Z\n'
        printf '**Priority**: high\n'
        printf '**Status**: pending\n'
        printf '**Area**: docs\n\n'
        if [[ "$i" -eq 150 ]]; then
            summary="Mixed-type large corpus error target"
            pattern_key="mixed.type.error.target"
        else
            summary="Mixed-type error filler $i"
            pattern_key="mixed.type.error.$i"
        fi
        printf '### Summary\n%s\n\n' "$summary"
        printf '### Error\n```\nerror %d\n```\n\n' "$i"
        printf '### Context\nGenerated mixed-type error entry %d.\n\n' "$i"
        printf '### Suggested Fix\nKeep error handling stable.\n\n'
        printf '### Metadata\n'
        printf -- '- Reproducible: yes\n'
        printf -- '- Source: automation\n'
        printf -- '- Related Files: none\n'
        printf -- '- Tags: smoke\n'
        printf -- '- Pattern-Key: %s\n' "$pattern_key"
        printf -- '- Recurrence-Count: 1\n'
        printf -- '- First-Seen: 2026-04-02\n'
        printf -- '- Last-Seen: 2026-04-02\n\n'
    done
} > "$PROJECT_MEMORY/ERRORS.md"

{
    printf '# Project Feature Requests\n\n'
    for i in $(seq 1 150); do
        printf -- '---\n\n'
        printf '## [FEAT-MIX-%03d] capability_request\n\n' "$i"
        printf '**Logged**: 2026-04-02T00:00:00Z\n'
        printf '**Priority**: medium\n'
        printf '**Status**: pending\n'
        printf '**Area**: docs\n\n'
        if [[ "$i" -eq 90 ]]; then
            capability="Mixed-type large corpus feature target"
        else
            capability="Mixed-type feature filler $i"
        fi
        printf '### Requested Capability\n%s\n\n' "$capability"
        printf '### User Context\nGenerated mixed-type feature entry %d.\n\n' "$i"
        printf '### Complexity Estimate\nmedium\n\n'
        printf '### Suggested Implementation\nKeep feature request handling stable.\n\n'
        printf '### Metadata\n'
        printf -- '- Frequency: first_time\n'
        printf -- '- Source: automation\n'
        printf -- '- Related Files: none\n'
        printf -- '- Tags: smoke\n'
        printf -- '- Pattern-Key: mixed.type.feature.%03d\n' "$i"
        printf -- '- Recurrence-Count: 1\n'
        printf -- '- First-Seen: 2026-04-02\n'
        printf -- '- Last-Seen: 2026-04-02\n\n'
    done
} > "$PROJECT_MEMORY/FEATURE_REQUESTS.md"

{
    printf '# Asset Index\n\n'
    for i in $(seq 1 120); do
        printf '## [AST-MIX-%03d] screenshot\n\n' "$i"
        printf -- '- Logged: 2026-04-02T00:00:00Z\n'
        if [[ "$i" -eq 75 ]]; then
            printf -- '- Title: mixed-type-large-corpus-asset-target\n'
            printf -- '- Summary: Mixed-type large corpus asset target\n'
        else
            printf -- '- Title: mixed-type-asset-%03d\n' "$i"
            printf -- '- Summary: Mixed-type asset filler %d\n' "$i"
        fi
        printf -- '- Type: screenshot\n'
        printf -- '- Scope: project\n'
        printf -- '- Namespace: project\n'
        printf -- '- Canonical-Path: /tmp/mixed-asset-%03d.png\n' "$i"
        printf -- '- Source: automation\n'
        printf -- '- Tags: smoke,asset\n'
        printf -- '- Related-Memory-IDs: none\n'
        printf -- '- Status: active\n\n---\n'
    done
} > "$PROJECT_MEMORY/assets/INDEX.md"

learning_search="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "recurring summary candidate"
)"
assert_contains "$learning_search" "[LRN-MIX-120]"

error_search="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type error --query "error target"
)"
assert_contains "$error_search" "[ERR-MIX-150]"

feature_search="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type feature_request --query "feature target"
)"
assert_contains "$feature_search" "[FEAT-MIX-090]"

asset_search="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type asset --query "asset target"
)"
assert_contains "$asset_search" "[AST-MIX-075]"

nightly_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --writeback true --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=project"
assert_contains_file "$PROJECT_MEMORY/SUMMARY.md" "[LRN-MIX-120]"
assert_contains_file "$PROJECT_MEMORY/REVIEW.md" "[ERR-MIX-150]"
assert_contains_file "$PROJECT_MEMORY/REVIEW.md" "[FEAT-MIX-090]"

printf 'mixed-type large-corpus smoke assertions passed\n'
