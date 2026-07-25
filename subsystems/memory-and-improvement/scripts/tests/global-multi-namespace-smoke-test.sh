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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/global-multi-namespace-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
GLOBAL_ROOT="$TMP_ROOT/global-memory"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_ROOT" "$STATE_ROOT"

make_namespace_fixture() {
    local namespace="$1"
    local summary_text="$2"
    local pattern_key="$3"
    local namespace_dir="$GLOBAL_ROOT/namespaces/$namespace"
    local memory_dir="$namespace_dir/.learnings"

    mkdir -p "$memory_dir"
    cat > "$namespace_dir/PROFILE.md" <<EOF
# ${namespace} Profile
EOF

    {
        printf '# Global Learnings\n\n'
        for i in $(seq 1 300); do
            printf -- '---\n\n'
            printf '## [GLRN-%s-%03d] insight\n\n' "$(printf '%s' "$namespace" | tr '[:lower:]-' '[:upper:]_')" "$i"
            printf '**Logged**: 2026-04-02T00:00:00Z\n'
            printf '**Priority**: medium\n'
            printf '**Status**: pending\n'
            printf '**Area**: docs\n\n'
            if [[ "$i" -eq 200 ]]; then
                summary="$summary_text"
                recurrence="3"
                current_pattern_key="$pattern_key"
            else
                summary="$namespace filler entry $i"
                recurrence="1"
                current_pattern_key="$namespace.filler.$i"
            fi
            printf '### Summary\n%s\n\n' "$summary"
            printf '### Details\nGenerated namespace smoke-test entry %d for %s.\n\n' "$i" "$namespace"
            printf '### Suggested Action\nKeep multi-namespace nightly maintenance stable.\n\n'
            printf '### Metadata\n'
            printf -- '- Source: automation\n'
            printf -- '- Related Files: none\n'
            printf -- '- Tags: smoke\n'
            printf -- '- Pattern-Key: %s\n' "$current_pattern_key"
            printf -- '- Recurrence-Count: %s\n' "$recurrence"
            printf -- '- First-Seen: 2026-04-02\n'
            printf -- '- Last-Seen: 2026-04-02\n\n'
        done
    } > "$memory_dir/LEARNINGS.md"
}

make_namespace_fixture "user-profile" "User profile large-scale recurring summary candidate" "global.multi.user_profile.summary"
make_namespace_fixture "research-history" "Research history large-scale recurring summary candidate" "global.multi.research_history.summary"
make_namespace_fixture "project" "Project namespace large-scale recurring summary candidate" "global.multi.project.summary"

nightly_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" --scope global --writeback true --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=global"
assert_contains_file "$GLOBAL_ROOT/namespaces/user-profile/SUMMARY.md" "User profile large-scale recurring summary candidate"
assert_contains_file "$GLOBAL_ROOT/namespaces/research-history/SUMMARY.md" "Research history large-scale recurring summary candidate"
assert_contains_file "$GLOBAL_ROOT/namespaces/project/SUMMARY.md" "Project namespace large-scale recurring summary candidate"

printf 'global multi-namespace smoke assertions passed\n'
