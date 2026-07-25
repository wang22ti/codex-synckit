#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$SKILL_DIR/scripts/bootstrap/init-memory.sh"
LOG_SCRIPT="$SKILL_DIR/scripts/capture/log-memory.sh"
RECALL_SCRIPT="$SKILL_DIR/scripts/recall/recall-memory.sh"
REFLECT_SCRIPT="$SKILL_DIR/scripts/recall/reflect-memory.sh"
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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/closed-loop-e2e-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_ROOT="$TMP_ROOT/home"
PROJECT_ROOT="$TMP_ROOT/project"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$HOME_ROOT/.codex/skills/memory-and-improvement" "$PROJECT_ROOT" "$STATE_ROOT"

env \
    HOME="$HOME_ROOT" \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$INIT_SCRIPT" --scope project --project-root "$PROJECT_ROOT" >/dev/null

for run_no in 1 2; do
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$LOG_SCRIPT" \
            --scope project \
            --type learning \
            --summary "Keep closed-loop audits visible during maintenance" \
            --details "Recurring repo convention for the closed-loop workflow." \
            --suggested-action "Promote this reminder once it recurs." \
            --pattern-key "closed.loop.audit.visible" \
            --git-autocommit false \
            >/dev/null
done

env \
    HOME="$HOME_ROOT" \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$LOG_SCRIPT" \
        --scope project \
        --type error \
        --summary "Nightly maintenance should preserve closed-loop review artifacts" \
        --error-text "review artifact missing" \
        --context "during closed-loop maintenance validation" \
        --suggested-fix "regenerate review artifacts before closing the loop" \
        --pattern-key "closed.loop.maintenance.error" \
        --git-autocommit false \
        >/dev/null

env \
    HOME="$HOME_ROOT" \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$LOG_SCRIPT" \
        --scope project \
        --type feature \
        --summary "Need a richer closed-loop test fixture helper" \
        --capability "Need a richer closed-loop test fixture helper" \
        --user-context "End-to-end testing gets easier with reusable fixtures." \
        --suggested-implementation "Add a fixture helper script for capture/recall/nightly flows." \
        --pattern-key "closed.loop.fixture.request" \
        --git-autocommit false \
        >/dev/null

pre_nightly_recall="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$RECALL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --query "closed-loop audits"
)"

assert_contains "$pre_nightly_recall" "Resolved-Scope: project"
assert_contains "$pre_nightly_recall" "Search:"
assert_contains "$pre_nightly_recall" "Keep closed-loop audits visible during maintenance"

reflect_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$REFLECT_SCRIPT" \
            --project-root "$PROJECT_ROOT" \
            --event decision \
            --summary "Recurring default convention for closed-loop audit visibility"
)"

assert_contains "$reflect_output" "Primary-Action: log_learning"
assert_contains "$reflect_output" "Secondary-Action: consider_summary"
assert_contains "$reflect_output" "Advisory-Only: true"

nightly_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$NIGHTLY_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --writeback true \
            --min-recurrence 2
)"

assert_contains "$nightly_output" "Nightly maintenance complete for scope=project"

PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
assert_contains_file "$PROJECT_MEMORY/REVIEW.md" "Nightly maintenance should preserve closed-loop review artifacts"
assert_contains_file "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" "Keep closed-loop audits visible during maintenance"
assert_contains_file "$PROJECT_MEMORY/SUMMARY.md" "Keep closed-loop audits visible during maintenance"
assert_contains_file "$PROJECT_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"
assert_contains_file "$PROJECT_MEMORY/FEATURE_REQUESTS.md" "Need a richer closed-loop test fixture helper"

post_nightly_recall="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$RECALL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --query "closed-loop audits"
)"

assert_contains "$post_nightly_recall" "Review:"
assert_contains "$post_nightly_recall" "Project summary highlights:"
assert_contains "$post_nightly_recall" "Keep closed-loop audits visible during maintenance"

printf 'closed-loop e2e assertions passed\n'
