#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SCRIPT="$SKILL_DIR/scripts/hooks/user-prompt-recall-reminder.sh"

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

output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-123","prompt":"Please help me debug the recall flow"}' |
        XDG_STATE_HOME=/tmp bash "$HOOK_SCRIPT"
)"

nightly_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-124","prompt":"Please update memory-and-improvement defaults.toml nightly schedule"}' |
        XDG_STATE_HOME=/tmp bash "$HOOK_SCRIPT"
)"

defaults_only_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-125","prompt":"Please explain the defaults.toml loader and TOML parsing contract"}' |
        XDG_STATE_HOME=/tmp bash "$HOOK_SCRIPT"
)"

crontab_only_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-126","prompt":"Please review the live crontab entry format"}' |
        XDG_STATE_HOME=/tmp bash "$HOOK_SCRIPT"
)"

non_matching_output="$(
    printf '%s' '{"hook_event_name":"SessionStart"}' |
        XDG_STATE_HOME=/tmp bash "$HOOK_SCRIPT"
)"

assert_contains "$output" "<memory-turn-reminder>"
assert_contains "$output" "Hook: UserPromptSubmit"
assert_contains "$output" "Trigger-Only: false"
assert_contains "$output" "Main-Session-Decision-Required: true"
assert_contains "$output" "Before replying, make an explicit recall decision."
assert_contains "$output" "Default to running recall for every non-trivial turn."
assert_contains "$output" "If recall is skipped, record why the skip is safe for this turn without forcing a user-visible no-op message."
assert_contains "$output" "Safe-skip recall only for narrow trivial turns such as casual chat, pure rewriting, pure summarization of user-provided text, or pure translation."
assert_contains "$output" "If the turn involves repo work, debugging, planning, implementation, review, memory operations, or user/profile/history-dependent answers, run recall instead of skipping it."
assert_contains "$output" "After any meaningful work product, default to running reflect-memory.sh unless the turn is clearly too small to produce a durable candidate."
assert_contains "$output" "Treat implementation, debugging, testing, review, documentation changes, planning that changes execution, and memory operations as default reflect cases."
assert_contains "$output" "Hooks do not decide whether recall is needed; the main session does."
assert_contains "$output" "Helpful entrypoint:"
assert_contains "$output" "Helpful reflect entrypoint:"
assert_not_contains "$output" "If recall is skipped, explicitly state why the skip is safe for this turn."
assert_not_contains "$output" "install-nightly-maintenance.sh --apply"
assert_contains "$nightly_output" "install-nightly-maintenance.sh --apply"
assert_contains "$nightly_output" "If this turn changes nightly/interval defaults in"
assert_contains "$nightly_output" "config/defaults.toml"
assert_contains "$nightly_output" "live crontab stays in sync"
assert_not_contains "$defaults_only_output" "install-nightly-maintenance.sh --apply"
assert_not_contains "$defaults_only_output" "live crontab stays in sync"
assert_not_contains "$crontab_only_output" "install-nightly-maintenance.sh --apply"
assert_not_contains "$crontab_only_output" "live crontab stays in sync"

if [[ -n "$non_matching_output" ]]; then
    printf 'Expected non-matching hook event to produce no output\n' >&2
    exit 1
fi

assert_not_contains "$output" "<memory-reflect-enforcement>"
assert_not_contains "$output" "<memory-reflect>"

printf 'user-prompt-recall-reminder assertions passed\n'
