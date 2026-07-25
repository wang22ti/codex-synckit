#!/bin/bash
# Triggers on UserPromptSubmit to remind the main session to make an explicit recall decision.

set -euo pipefail

ensure_minimal_path() {
    local candidate
    local defaults=(
        "/opt/homebrew/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
    )

    PATH="${PATH:-}"
    for candidate in "${defaults[@]}"; do
        case ":$PATH:" in
            *":$candidate:"*) ;;
            *) PATH="${PATH:+$PATH:}$candidate" ;;
        esac
    done

    export PATH
}

ensure_minimal_path

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
. "$SCRIPT_DIR/hook-utils.sh"

hook_event_name=""
prompt_text=""
session_id=""

find_session_rollout_file() {
    local current_session_id="$1"
    local sessions_dir="$self_improving_codex_home/archived_sessions"

    [[ -n "$current_session_id" && -d "$sessions_dir" ]] || return 1

    find "$sessions_dir" -maxdepth 1 -type f -name "*-$current_session_id.jsonl" | sort | tail -n 1
}

latest_turn_reflect_status() {
    local session_file="$1"
    local python_cmd=""

    [[ -f "$session_file" ]] || return 1
    python_cmd="$(hook_find_python)" || return 1

    "$python_cmd" - "$session_file" <<'PY'
import json
import sys

session_file = sys.argv[1]
entries = []
with open(session_file, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except Exception:
            continue

task_completes = []
for idx, entry in enumerate(entries):
    if entry.get("type") != "event_msg":
        continue
    payload = entry.get("payload") or {}
    if payload.get("type") != "task_complete":
        continue
    task_completes.append(
        {
            "idx": idx,
            "turn_id": payload.get("turn_id", ""),
            "last_agent_message": payload.get("last_agent_message", ""),
        }
    )

if not task_completes:
    raise SystemExit(0)

latest = task_completes[-1]
previous_idx = task_completes[-2]["idx"] if len(task_completes) > 1 else -1
manual_reflected = False

for entry in entries[previous_idx + 1 : latest["idx"] + 1]:
    if entry.get("type") != "response_item":
        continue
    payload = entry.get("payload") or {}
    if payload.get("type") != "function_call":
        continue
    if payload.get("name") != "exec_command":
        continue
    arguments = payload.get("arguments", "")
    if "reflect-memory.sh" in arguments:
        manual_reflected = True
        break

message = latest["last_agent_message"].replace("\t", " ").replace("\n", " ").strip()
print(f'{latest["turn_id"]}\t{"true" if manual_reflected else "false"}\t{message}')
PY
}

auto_reflect_previous_turn_if_needed() {
    local current_session_id="$1"
    local session_file=""
    local status_line=""
    local latest_turn_id=""
    local manual_reflected=""
    local last_agent_message=""
    local reflect_state_dir=""
    local reflect_state_file=""
    local last_reflected_turn_id=""
    local reflect_output=""
    local reflect_stderr_file=""
    local reflect_status=0
    local reflect_error_message=""

    session_file="$(find_session_rollout_file "$current_session_id")" || return 0
    [[ -n "$session_file" ]] || return 0

    status_line="$(latest_turn_reflect_status "$session_file")" || return 0
    [[ -n "$status_line" ]] || return 0

    latest_turn_id="${status_line%%$'\t'*}"
    status_line="${status_line#*$'\t'}"
    manual_reflected="${status_line%%$'\t'*}"
    last_agent_message="${status_line#*$'\t'}"

    [[ -n "$latest_turn_id" ]] || return 0

    reflect_state_dir="$self_improving_state_root/hook-state/reflect"
    reflect_state_file="$reflect_state_dir/$current_session_id.last_turn_id"
    mkdir -p "$reflect_state_dir"

    if [[ -f "$reflect_state_file" ]]; then
        last_reflected_turn_id="$(cat "$reflect_state_file" 2>/dev/null)"
    fi

    if [[ "$manual_reflected" == "true" ]]; then
        printf '%s\n' "$latest_turn_id" > "$reflect_state_file"
        return 0
    fi

    if [[ "$last_reflected_turn_id" == "$latest_turn_id" ]]; then
        return 0
    fi

    last_agent_message="$(truncate_chars "$(trim_whitespace "$last_agent_message")" 1200)"
    [[ -n "$last_agent_message" ]] || return 0
    reflect_stderr_file="$(mktemp "${TMPDIR:-/tmp}/memory-reflect-hook.XXXXXX")"

    reflect_output="$(
        bash "$SCRIPT_ROOT/recall/reflect-memory.sh" \
            --project-root "$self_improving_project_root" \
            --event other \
            --summary "$last_agent_message" \
            --details "Automatically triggered on UserPromptSubmit because the previous completed turn did not record a reflect check." \
            2>"$reflect_stderr_file"
    )" || reflect_status=$?

    if [[ "$reflect_status" -ne 0 ]]; then
        reflect_error_message="$(tr '\n' ' ' < "$reflect_stderr_file" 2>/dev/null)"
        reflect_error_message="$(truncate_chars "$(trim_whitespace "$reflect_error_message")" 400)"
        rm -f "$reflect_stderr_file"

        cat <<EOF
<memory-reflect-enforcement>
Auto-Reflect: previous completed turn had no recorded reflect check, but reflect-memory.sh failed before continuing.
Reflect-Exit-Code: $reflect_status
Reflect-Action-Required: run $SCRIPT_ROOT/recall/reflect-memory.sh manually for the previous turn before relying on the hook to cover it.
${reflect_error_message:+Reflect-Error: $reflect_error_message}
</memory-reflect-enforcement>
EOF
        return 0
    fi

    rm -f "$reflect_stderr_file"

    printf '%s\n' "$latest_turn_id" > "$reflect_state_file"

    cat <<EOF
<memory-reflect-enforcement>
Auto-Reflect: previous completed turn had no recorded reflect check, so reflect-memory.sh was run before continuing.
</memory-reflect-enforcement>
$reflect_output
EOF
}


prompt_matches_user_profile() {
    local prompt_lower="$1"

    case "$prompt_lower" in
        *"who am i"*|*"whoami"*|*"do you know me"*|*"what do you know about me"*|*"my name"*|*"my profile"*|*"my identity"*|*"我的名字"*|*"我是谁"*|*"你知道我是谁"*|*"你认识我"*|*"你了解我"*|*"我的身份"*|*"我的档案"*|*"我的个人资料"*)
            return 0
            ;;
    esac

    return 1
}

emit_user_profile_recall_if_needed() {
    local prompt_lower="$1"
    local summary_file="$self_improving_global_namespaces_root/user-profile/SUMMARY.md"

    prompt_matches_user_profile "$prompt_lower" || return 0

    cat <<EOF
<memory-auto-recall>
Reason: user-profile cue matched the submitted prompt.
Namespace: user-profile
Source: $summary_file
EOF

    if [[ -f "$summary_file" ]]; then
        sed -n '1,32p' "$summary_file" 2>/dev/null || true
    else
        cat <<EOF
Recall-Status: missing-summary
Fallback: inspect $summary_file before answering identity/profile questions.
EOF
    fi

    cat <<'EOF'
</memory-auto-recall>
EOF
}
should_emit_nightly_crontab_reminder() {
    local prompt_lower="$1"

    [[ "$prompt_lower" == *"memory-and-improvement"* || "$prompt_lower" == *"defaults.toml"* ]] || return 1

    case "$prompt_lower" in
        *nightly*|*interval*|*crontab*|*"install-nightly-maintenance.sh"*|*"maintenance.schedule"*)
            return 0
            ;;
    esac

    return 1
}

read_hook_input
hook_event_name="$(extract_hook_field "hook_event_name")"
prompt_text="$(extract_hook_field "prompt")"
session_id="$(extract_hook_field "session_id")"

if [[ "$hook_event_name" != "UserPromptSubmit" ]]; then
    exit 0
fi

cat <<EOF
<memory-turn-reminder>
Hook: UserPromptSubmit
Trigger-Only: false
Main-Session-Decision-Required: true
- Before replying, make an explicit recall decision.
- Default to running recall for every non-trivial turn.
- If recall is needed, start with the smallest relevant memory layer first.
- Safe-skip recall only for narrow trivial turns such as casual chat, pure rewriting, pure summarization of user-provided text, or pure translation.
- If the turn involves repo work, debugging, planning, implementation, review, memory operations, or user/profile/history-dependent answers, run recall instead of skipping it.
- If the user is asking a memory-system meta question, prefer recall-memory.sh --mode memory-system before inferring from the current repo.
- If recall is skipped, record why the skip is safe for this turn without forcing a user-visible no-op message.
- After any meaningful work product, default to running reflect-memory.sh unless the turn is clearly too small to produce a durable candidate.
- Treat implementation, debugging, testing, review, documentation changes, planning that changes execution, and memory operations as default reflect cases.
- Hooks do not decide whether recall is needed; the main session does.
- Helpful entrypoint: $SCRIPT_ROOT/recall/recall-memory.sh --scope auto
- Helpful memory-system entrypoint: $SCRIPT_ROOT/recall/recall-memory.sh --mode memory-system
- Helpful reflect entrypoint: $SCRIPT_ROOT/recall/reflect-memory.sh
- Project memory: $self_improving_project_memory_dir
- Project memory registry: $self_improving_project_registry_file
EOF

# Disabled in hook path: can be slow or block on Windows; run reflect-memory.sh from the main session when needed.

prompt_lower="$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')"
emit_user_profile_recall_if_needed "$prompt_lower"
if should_emit_nightly_crontab_reminder "$prompt_lower"; then
    cat <<EOF
- If this turn changes nightly/interval defaults in \`config/defaults.toml\`, also run \`$SCRIPT_ROOT/maintenance/install-nightly-maintenance.sh --apply\` so the live crontab stays in sync.
EOF
fi

cat <<'EOF'
</memory-turn-reminder>
EOF

exit 0
