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
