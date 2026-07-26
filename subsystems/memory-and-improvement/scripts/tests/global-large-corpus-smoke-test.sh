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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/global-large-corpus-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
GLOBAL_ROOT="$TMP_ROOT/global-memory"
STATE_ROOT="$TMP_ROOT/state"
NAMESPACE="user-profile"
NAMESPACE_DIR="$GLOBAL_ROOT/namespaces/$NAMESPACE"
GLOBAL_MEMORY="$NAMESPACE_DIR/.learnings"

mkdir -p "$PROJECT_ROOT" "$GLOBAL_MEMORY" "$STATE_ROOT" "$NAMESPACE_DIR"

cat > "$NAMESPACE_DIR/PROFILE.md" <<'EOF'
# Profile
EOF

{
    printf '# Global Learnings\n\n'
    for i in $(seq 1 1000); do
        printf -- '---\n\n'
        printf '## [GLRN-LARGE-%04d] insight\n\n' "$i"
        printf '**Logged**: 2026-04-02T00:00:00Z\n'
        printf '**Priority**: medium\n'
        printf '**Status**: pending\n'
        printf '**Area**: docs\n\n'
        if [[ "$i" -eq 400 ]]; then
            summary="Preferred name remains Zitai at scale"
            recurrence="4"
            pattern_key="global.large.profile.fact"
            details="This is stable profile information that should favor a factual file instead of summary promotion."
            suggested_action="Keep durable profile facts structured."
        elif [[ "$i" -eq 800 ]]; then
            summary="Global large corpus recurring summary candidate"
            recurrence="3"
            pattern_key="global.large.summary.candidate"
            details="This is a durable cross-project reminder worth summary promotion."
            suggested_action="Keep cross-project summary promotion stable."
        elif [[ "$i" -eq 1000 ]]; then
            summary="Global large corpus unique search target"
            recurrence="1"
            pattern_key="global.large.unique.search.target"
            details="This unique target proves global search still works at larger scale."
            suggested_action="Keep global search stable at larger scale."
        else
            summary="Global large corpus filler entry $i"
            recurrence="1"
            pattern_key="global.large.filler.$i"
            details="Generated global smoke-test entry $i."
            suggested_action="Keep global maintenance stable at larger scale."
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
} > "$GLOBAL_MEMORY/LEARNINGS.md"

search_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="$NAMESPACE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --namespace "$NAMESPACE" --query "unique search target"
)"

assert_contains "$search_output" "<memory-search>"
assert_contains "$search_output" "[GLRN-LARGE-1000]"
assert_contains "$search_output" "Global large corpus unique search target"

organize_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="$NAMESPACE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$ORGANIZE_SCRIPT" --scope global --namespace "$NAMESPACE" --min-recurrence 2
)"

assert_contains "$organize_output" "Organized global memory:"
assert_contains_file "$GLOBAL_MEMORY/REVIEW.md" "[GLRN-LARGE-0800]"
assert_contains_file "$NAMESPACE_DIR/SUMMARY_CANDIDATES.md" "[GLRN-LARGE-0800]"

nightly_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="$NAMESPACE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" --scope global --namespace "$NAMESPACE" --writeback true --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=global"
assert_contains_file "$NAMESPACE_DIR/SUMMARY.md" "[GLRN-LARGE-0800]"
assert_not_contains_file "$NAMESPACE_DIR/SUMMARY.md" "[GLRN-LARGE-0400]"
assert_not_contains_file "$NAMESPACE_DIR/SUMMARY.md" "[GLRN-LARGE-1000]"
assert_contains_file "$GLOBAL_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"

printf 'global large-corpus smoke assertions passed\n'
