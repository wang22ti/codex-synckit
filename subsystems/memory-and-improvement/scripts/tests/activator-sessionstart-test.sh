#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACTIVATOR="$SKILL_DIR/scripts/hooks/activator.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'Expected output not to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_exists() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        printf 'Expected path to exist: %s\n' "$path" >&2
        exit 1
    fi
}

output="$(
    printf '%s' '{"hook_event_name":"SessionStart"}' |
        XDG_STATE_HOME=/tmp bash "$ACTIVATOR"
)"

minimal_path_output="$(
    env -i HOME="$HOME" PATH="/tmp" XDG_STATE_HOME=/tmp /bin/bash "$ACTIVATOR" <<'EOF'
{"hook_event_name":"SessionStart"}
EOF
)"

fallback_hook_field="$(
    bash -lc '
        source "'"$SKILL_DIR"'/scripts/hooks/hook-utils.sh"
        hook_input='"'"'{"hook_event_name":"SessionStart"}'"'"'
        hook_find_python() { return 1; }
        extract_hook_field hook_event_name
    '
)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/activator-sessionstart-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
STATE_ROOT="$TMP_ROOT/state"
mkdir -p "$PROJECT_ROOT" "$STATE_ROOT"
git -C "$PROJECT_ROOT" init >/dev/null 2>&1

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$ACTIVATOR" <<'EOF' >/dev/null
{"hook_event_name":"SessionStart"}
EOF

if [[ -d "$PROJECT_ROOT/.learnings" ]]; then
    printf 'Expected fail-open SessionStart not to initialize %s\n' "$PROJECT_ROOT/.learnings" >&2
    exit 1
fi

NON_REPO_ROOT="$TMP_ROOT/non-repo"
NON_REPO_STATE_ROOT="$TMP_ROOT/non-repo-state"
mkdir -p "$NON_REPO_ROOT" "$NON_REPO_STATE_ROOT"

env \
    SELF_IMPROVING_PROJECT_ROOT="$NON_REPO_ROOT" \
    XDG_STATE_HOME="$NON_REPO_STATE_ROOT" \
    bash "$ACTIVATOR" <<'EOF' >/dev/null
{"hook_event_name":"SessionStart"}
EOF

if [[ -d "$NON_REPO_ROOT/.learnings" ]]; then
    printf 'Expected non-repo SessionStart not to initialize %s\n' "$NON_REPO_ROOT/.learnings" >&2
    exit 1
fi

READ_ONLY_ROOT="$TMP_ROOT/read-only-project"
READ_ONLY_STATE_ROOT="$TMP_ROOT/read-only-state"
mkdir -p "$READ_ONLY_ROOT" "$READ_ONLY_STATE_ROOT"
git -C "$READ_ONLY_ROOT" init >/dev/null 2>&1
chmod 0555 "$READ_ONLY_ROOT"

read_only_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$READ_ONLY_ROOT" \
        XDG_STATE_HOME="$READ_ONLY_STATE_ROOT" \
        bash "$ACTIVATOR" <<'EOF'
{"hook_event_name":"SessionStart"}
EOF
)"

chmod 0755 "$READ_ONLY_ROOT"

assert_contains "$read_only_output" "<memory-session-guide>"
if [[ -d "$READ_ONLY_ROOT/.learnings" ]]; then
    printf 'Expected read-only SessionStart not to initialize %s\n' "$READ_ONLY_ROOT/.learnings" >&2
    exit 1
fi

assert_contains "$output" "<memory-session-guide>"
assert_contains "$minimal_path_output" "<memory-session-guide>"
assert_contains "$fallback_hook_field" "SessionStart"
assert_contains "$output" "Closed-loop procedure:"
assert_contains "$output" "this is runtime guidance injected on SessionStart, not an automatic enforcement layer"
assert_contains "$output" "the main session remains responsible for carrying it out on later turns"
assert_contains "$output" "Recall: before every reply after this skill is active"
assert_contains "$output" "default to running recall first for every non-trivial turn"
assert_contains "$output" "pure summarization of user-provided text"
assert_contains "$output" "Reason: decide whether the current layer is enough"
assert_contains "$output" "Reason checklist:"
assert_contains "$output" "what relevant memory did recall surface?"
assert_contains "$output" "if recall was skipped, why was the skip safe for this turn?"
assert_contains "$output" "is the next step review-memory.sh, search-memory.sh, a structured factual file, or raw .learnings/*.md?"
assert_contains "$output" "summary hit and sufficient -> proceed"
assert_contains "$output" "summary hit but underspecified -> open review-memory.sh or a structured factual file"
assert_contains "$output" "no summary hit but clear history dependence -> use search-memory.sh"
assert_contains "$output" "chronology, evidence, debugging context, or exact correction history needed -> open raw .learnings/*.md"
assert_contains "$output" "if the turn involves repo work, debugging, planning, implementation, review, memory operations, or user/profile/history-dependent answers, run recall instead of skipping it"
assert_contains "$output" "surface the audit convention in the plan before edits begin"
assert_contains "$output" "run an audit-focused subagent before considering the work complete or moving on"
assert_contains "$output" "Respond/Act execution boundary:"
assert_contains "$output" "normal execution: replies, memory review/logging/search"
assert_contains "$output" "audit-aware execution: substantial memory-and-improvement workflow/docs/spec/roadmap/diagram changes"
assert_contains "$output" "say so in commentary or planning language before edits begin"
assert_contains "$output" "otherwise explicitly state that the audit requirement remains unmet"
assert_contains "$output" "Reflect: after any meaningful work product"
assert_contains "$output" "default to running reflect-memory.sh after implementation, debugging, testing, review, documentation changes, planning that changes execution, or memory-management turns"
assert_contains "$output" "make an explicit reflect decision"
assert_contains "$output" "do not force user-visible \"no recall needed\" or \"no reflect needed\" filler"
assert_not_contains "$output" "explicitly state why skipping recall is safe for this turn"
assert_not_contains "$output" "explicitly state why there is no durable candidate to log yet"
assert_contains "$output" "Logging procedure:"
assert_contains "$output" "<memory-routing-hint>"
assert_contains "$output" "default read order:"
assert_contains "$output" "before every reply after this skill is active, make a recall decision"
assert_contains "$output" "default to running recall for every non-trivial turn"
assert_contains "$output" "start with the smallest relevant memory layer first"
assert_contains "$output" "1. INIT.md"
assert_contains "$output" "6. asset index (project: .learnings/assets/INDEX.md; global: assets/INDEX.md)"
assert_contains "$output" "skip global memory when the task is repo-local, casual, creative"
assert_contains "$output" "if the higher layers already answer the need, do not force deeper reads"
assert_contains "$output" "do not open raw .learnings/*.md until higher layers are insufficient"
assert_contains "$output" "open the relevant asset index before opening a concrete asset file"
assert_contains "$output" "treat memory logging as a lightweight candidate workflow"
assert_contains "$output" "capture favors recall; promotion favors precision"
assert_contains "$output" "a durable user preference"
assert_contains "$output" "a real missing capability request"
assert_contains "$output" "any other event, observation, correction, or decision that seems worth recording"
assert_contains "$output" "is the main value a reusable procedure"
assert_contains "$output" "would this still help in a different repository next week"
assert_contains "$output" "choose project vs global"
assert_contains "$output" "for raw .learnings capture, keep the bar loose"
assert_contains "$output" "use \`user-profile\` immediately for identity, CV, publication, funding, or preferred-name tasks"
assert_contains "$output" 'call '"$SKILL_DIR"'/scripts/capture/log-memory.sh directly'

printf 'activator SessionStart output assertions passed\n'
