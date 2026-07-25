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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/user-prompt-recall-reminder-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

AUTO_HOME="$TMP_ROOT/home"
AUTO_STATE_HOME="$TMP_ROOT/state"
AUTO_PROJECT_ROOT="$TMP_ROOT/project"
AUTO_SESSIONS_DIR="$AUTO_HOME/.codex/archived_sessions"
mkdir -p "$AUTO_SESSIONS_DIR" "$AUTO_PROJECT_ROOT" "$AUTO_STATE_HOME"

AUTO_SESSION_ID="sess-auto"
AUTO_SESSION_FILE="$AUTO_SESSIONS_DIR/rollout-2026-04-04T00-00-00-$AUTO_SESSION_ID.jsonl"
cat <<'EOF' > "$AUTO_SESSION_FILE"
{"timestamp":"2026-04-04T00:00:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-001","last_agent_message":"Implemented a durable repo convention change for memory loading and updated tests."}}
EOF

auto_reflect_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-auto","prompt":"Continue with the next task"}' |
        HOME="$AUTO_HOME" \
        XDG_STATE_HOME="$AUTO_STATE_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$AUTO_PROJECT_ROOT" \
        bash "$HOOK_SCRIPT"
)"

assert_contains "$auto_reflect_output" "<memory-reflect-enforcement>"
assert_contains "$auto_reflect_output" "Auto-Reflect: previous completed turn had no recorded reflect check"
assert_contains "$auto_reflect_output" "<memory-reflect>"
assert_contains "$auto_reflect_output" "Advisory-Only: true"

repeat_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-auto","prompt":"Continue with the next task"}' |
        HOME="$AUTO_HOME" \
        XDG_STATE_HOME="$AUTO_STATE_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$AUTO_PROJECT_ROOT" \
        bash "$HOOK_SCRIPT"
)"

assert_not_contains "$repeat_output" "<memory-reflect-enforcement>"

MANUAL_SESSION_ID="sess-manual"
MANUAL_SESSION_FILE="$AUTO_SESSIONS_DIR/rollout-2026-04-04T00-00-01-$MANUAL_SESSION_ID.jsonl"
cat <<'EOF' > "$MANUAL_SESSION_FILE"
{"timestamp":"2026-04-04T00:00:00Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"bash /home/example/.codex/skills/memory-and-improvement/scripts/recall/reflect-memory.sh\"}"}}
{"timestamp":"2026-04-04T00:00:01Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-002","last_agent_message":"Reviewed the prior turn and already ran reflect."}}
EOF

manual_reflect_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-manual","prompt":"Continue with the next task"}' |
        HOME="$AUTO_HOME" \
        XDG_STATE_HOME="$AUTO_STATE_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$AUTO_PROJECT_ROOT" \
        bash "$HOOK_SCRIPT"
)"

assert_not_contains "$manual_reflect_output" "<memory-reflect-enforcement>"

AMBIGUOUS_SESSION_FILE="$AUTO_SESSIONS_DIR/rollout-2026-04-04T00-00-02-sess-auto-extra.jsonl"
cat <<'EOF' > "$AMBIGUOUS_SESSION_FILE"
{"timestamp":"2026-04-04T00:00:02Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-999","last_agent_message":"This file should not be selected for sess-auto."}}
EOF

ambiguous_repeat_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-auto","prompt":"Continue with the next task"}' |
        HOME="$AUTO_HOME" \
        XDG_STATE_HOME="$AUTO_STATE_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$AUTO_PROJECT_ROOT" \
        bash "$HOOK_SCRIPT"
)"

assert_not_contains "$ambiguous_repeat_output" "turn-999"
assert_not_contains "$ambiguous_repeat_output" "This file should not be selected for sess-auto."

FAIL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/user-prompt-recall-reminder-fail.XXXXXX")"
FAIL_HOME="$FAIL_ROOT/home"
FAIL_STATE_HOME="$FAIL_ROOT/state"
FAIL_PROJECT_ROOT="$FAIL_ROOT/project"
FAIL_SESSIONS_DIR="$FAIL_HOME/.codex/archived_sessions"
FAIL_STUB_DIR="$FAIL_ROOT/stubs"
mkdir -p "$FAIL_SESSIONS_DIR" "$FAIL_PROJECT_ROOT" "$FAIL_STATE_HOME" "$FAIL_STUB_DIR"

FAIL_SESSION_FILE="$FAIL_SESSIONS_DIR/rollout-2026-04-04T00-00-03-sess-fail.jsonl"
cat <<'EOF' > "$FAIL_SESSION_FILE"
{"timestamp":"2026-04-04T00:00:03Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-fail","last_agent_message":"Completed a meaningful change but reflect helper will fail in this test."}}
EOF

cat <<'EOF' > "$FAIL_STUB_DIR/bash"
#!/bin/sh
if [ "$1" = "/home/example/.codex/skills/memory-and-improvement/scripts/recall/reflect-memory.sh" ]; then
    echo "stubbed reflect failure for test" >&2
    exit 77
fi
exec /bin/bash "$@"
EOF
chmod +x "$FAIL_STUB_DIR/bash"

failed_auto_reflect_output="$(
    printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-fail","prompt":"Continue with the next task"}' |
        HOME="$FAIL_HOME" \
        PATH="$FAIL_STUB_DIR:$PATH" \
        XDG_STATE_HOME="$FAIL_STATE_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$FAIL_PROJECT_ROOT" \
        bash "$HOOK_SCRIPT"
)"

assert_contains "$failed_auto_reflect_output" "<memory-reflect-enforcement>"
assert_contains "$failed_auto_reflect_output" "reflect-memory.sh failed before continuing"
assert_contains "$failed_auto_reflect_output" "Reflect-Exit-Code: 77"
assert_contains "$failed_auto_reflect_output" "Reflect-Action-Required:"
assert_contains "$failed_auto_reflect_output" "Reflect-Error: stubbed reflect failure for test"

printf 'user-prompt-recall-reminder assertions passed\n'
