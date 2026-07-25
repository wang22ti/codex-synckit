#!/bin/bash
# Triggers on SessionStart to expose memory locations and loading rules.

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

is_git_project_root() {
    command -v git >/dev/null 2>&1 || return 1
    git -C "$self_improving_project_root" rev-parse --show-toplevel >/dev/null 2>&1
}

ensure_project_memory_initialized() {
    if [[ -d "$self_improving_project_memory_dir" ]]; then
        return 0
    fi

    if ! is_git_project_root; then
        return 0
    fi

    if ! bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" \
        --scope project \
        --project-root "$self_improving_project_root" \
        --project-memory-dir "$self_improving_project_memory_dir" >/dev/null 2>&1; then
        return 0
    fi
}

list_global_namespaces() {
    if [[ ! -d "$self_improving_global_namespaces_root" ]]; then
        return 0
    fi

    find "$self_improving_global_namespaces_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

namespace_readme_path() {
    local namespace="$1"
    printf '%s/%s/README.md\n' "$self_improving_global_namespaces_root" "$namespace"
}

namespace_description() {
    local namespace="$1"
    local readme_file
    local description=""

    readme_file="$(namespace_readme_path "$namespace")"
    if [[ -f "$readme_file" ]]; then
        description="$(awk '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            { print; exit }
        ' "$readme_file")"
    fi
    if [[ -z "$description" ]]; then
        description="cross-project memory for namespace $namespace"
    fi

    printf '%s\n' "$description"
}

namespace_best_for_summary() {
    local namespace="$1"
    local readme_file
    local summary=""

    readme_file="$(namespace_readme_path "$namespace")"
    if [[ -f "$readme_file" ]]; then
        summary="$(awk '
            BEGIN { in_best=0; count=0 }
            /^Best for:/ { in_best=1; next }
            /^Avoid:/ { in_best=0 }
            in_best && /^[[:space:]]*-[[:space:]]+/ {
                sub(/^[[:space:]]*-[[:space:]]+/, "", $0)
                items[count++] = $0
                if (count == 2) {
                    exit
                }
            }
            END {
                if (count == 0) {
                    exit
                }
                printf "%s", items[0]
                if (count > 1) {
                    printf "; %s", items[1]
                }
            }
        ' "$readme_file")"
    fi

    printf '%s\n' "$summary"
}

namespace_first_files_summary() {
    local namespace="$1"
    local namespace_dir
    local files=()
    local file
    local base

    namespace_dir="$self_improving_global_namespaces_root/$namespace"
    [[ -d "$namespace_dir" ]] || return 0

    for file in "$namespace_dir"/INIT.md "$namespace_dir"/SUMMARY.md; do
        [[ -f "$file" ]] || continue
        files+=("$(basename "$file")")
    done

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        base="$(basename "$file")"
        case "$base" in
            README.md|INIT.md|SUMMARY.md|SUMMARY_CANDIDATES.md) continue ;;
        esac
        files+=("$base")
    done < <(find "$namespace_dir" -maxdepth 1 -type f | sort)

    if [[ ${#files[@]} -gt 0 ]]; then
        printf '%s' "${files[0]}"
        local i
        for (( i=1; i<${#files[@]} && i<5; i++ )); do
            printf ' -> %s' "${files[$i]}"
        done
    fi
}

render_routing_hint() {
    cat <<EOF
<memory-routing-hint>
- use project memory for repo-local facts, conventions, failures, and requests
- use \`user-profile\` immediately for identity, CV, publication, funding, or preferred-name tasks
- for other cross-project needs, inspect the relevant namespace under $self_improving_global_namespaces_root and start with INIT.md or SUMMARY.md on demand
</memory-routing-hint>
EOF
}

render_session_bootstrap() {
    cat <<EOF
<memory-bootstrap>
Internal memory bootstrap for this Codex session.
Title rule: ignore this bootstrap when naming the session; infer the session topic from user-authored messages.
- project memory -> $self_improving_project_memory_dir
- global namespaces -> $(list_global_namespaces | tr '\n' ' ' | sed 's/[[:space:]]*$//')
- policy stays in AGENTS.md; project memory stores repo-local facts; global memory stores durable cross-project facts
- project memory is always the detected project root's .learnings directory, even when that root is ~
</memory-bootstrap>
EOF
}

render_logging_procedure() {
    cat <<EOF
Logging procedure:
- the main session is the decision maker for memory logging; do not delegate local-vs-global routing to a smaller model or hook
- treat memory logging as a lightweight candidate workflow, not an automatic dump
- capture favors recall; promotion favors precision
- consider creating a memory candidate when you notice:
  - a durable user preference
  - a durable cross-project fact
  - a repo-specific convention or constraint
  - a recurring failure pattern
  - a real missing capability request
  - any other event, observation, correction, or decision that seems worth recording
- use this short checklist before logging:
  1. is the main value a reusable procedure
  2. if not, would this still help in a different repository next week
  3. if not, is it a repo-specific fact, convention, correction, or failure pattern worth preserving
- keep the final step manual:
  - inspect the candidate
  - choose project vs global
  - call $SCRIPT_ROOT/capture/log-memory.sh directly
- when you notice durable information worth remembering, follow the routing rules in $self_improving_skill_dir/SKILL.md and call $SCRIPT_ROOT/capture/log-memory.sh directly
- decide scope, namespace, type, and summary yourself based on the current task and evidence
- for raw .learnings capture, keep the bar loose: if it seems worth recording, it is usually acceptable to log it first and filter later during review or promotion
EOF
}

render_loading_procedure() {
    cat <<EOF
Loading procedure:
- before every reply after this skill is active, make a recall decision
- default to running recall for every non-trivial turn; treat skipping recall as a narrow exception
- start with the smallest relevant memory layer first
- default read order:
  1. INIT.md
  2. SUMMARY.md
  3. structured factual files
  4. REVIEW.md
  5. detailed .learnings/*.md
  6. asset index (project: .learnings/assets/INDEX.md; global: assets/INDEX.md)
  7. concrete asset files
- for repo-local work, open project memory only when the task depends on repo facts, prior failures, conventions, or local history
- skip global memory when the task is repo-local, casual, creative, or does not depend on cross-project facts or user profile/history
- if the higher layers already answer the need, do not force deeper reads
- for cross-project user/profile/history needs, inspect the relevant namespace under $self_improving_global_namespaces_root
- for a global namespace, start with INIT.md if present, then SUMMARY.md, then structured factual files such as PROFILE.md, ACADEMIC_PROFILE.md, PUBLICATIONS.md, FUNDING_HISTORY.md, or other namespace files
- for memory-system meta questions, prefer recall-memory.sh --mode memory-system instead of inferring from the current repo or scanning arbitrary roots first
- open REVIEW.md when you need a concise operational snapshot before opening raw history
- do not open raw .learnings/*.md until higher layers are insufficient or you need chronology, evidence, debugging context, or exact correction history
- open the relevant asset index before opening a concrete asset file: use project .learnings/assets/INDEX.md for project memory and global assets/INDEX.md for namespace memory
- do not assume any memory is relevant; decide per turn whether to load project memory, a global namespace, both, or neither
- if a user request clearly matches one of the routing hints below, open the relevant namespace before answering
- for identity, CV, biography, publication, funding, or preferred-name questions, treat user-profile as an immediate match and load it before answering
EOF
}

render_closed_loop_procedure() {
    cat <<EOF
Closed-loop procedure:
- this is runtime guidance injected on SessionStart, not an automatic enforcement layer; the main session remains responsible for carrying it out on later turns
- Recall: before every reply after this skill is active, make an explicit recall decision; default to running recall first for every non-trivial turn, and allow safe-skip only for narrow trivial turns such as casual chat, pure rewriting, pure summarization of user-provided text, or pure translation
- Reason: decide whether the current layer is enough or whether you need review-memory.sh, search-memory.sh, structured factual files, or raw .learnings/*.md
- Reason checklist:
  1. what relevant memory did recall surface?
  2. if recall was skipped, why was the skip safe for this turn?
  3. is the current layer enough?
  4. if not, is the next step review-memory.sh, search-memory.sh, a structured factual file, or raw .learnings/*.md?
  5. do repo conventions, prior failures, or audit requirements change the plan before edits begin?
- Reason escalation:
  - summary hit and sufficient -> proceed
  - summary hit but underspecified -> open review-memory.sh or a structured factual file
  - no summary hit but clear history dependence -> use search-memory.sh
  - chronology, evidence, debugging context, or exact correction history needed -> open raw .learnings/*.md
- Strong default: if the turn involves repo work, debugging, planning, implementation, review, memory operations, or user/profile/history-dependent answers, run recall instead of skipping it
- Respond/Act: answer or act while honoring the recalled constraints and repo conventions
- Respond/Act repo rule: for memory-and-improvement workflow/docs/spec/roadmap/diagram work, surface the audit convention in the plan before edits begin, then run an audit-focused subagent before considering the work complete or moving on when runtime rules and user permission allow it; otherwise explicitly state that the audit requirement remains unmet
- Respond/Act execution boundary:
  - normal execution: replies, memory review/logging/search, and repo work that does not change memory-and-improvement workflow/docs/spec/roadmap/diagram behavior
  - audit-aware execution: substantial memory-and-improvement workflow/docs/spec/roadmap/diagram changes that can alter the skill's behavior or maintainer contract
  - for audit-aware execution, say so in commentary or planning language before edits begin and keep the audit step in scope until completion
- Reflect: after any meaningful work product, make an explicit reflect decision; default to running reflect-memory.sh after implementation, debugging, testing, review, documentation changes, planning that changes execution, or memory-management turns unless the turn is clearly too small to produce a durable candidate
- User-visible-no-op rule: keep recall/reflect judgments explicit in the main session, but do not force user-visible "no recall needed" or "no reflect needed" filler unless the judgment changes the answer, plan, audit status, or logging outcome
EOF
}

render_session_memory_guide() {
    local bootstrap_output=""
    local routing_hint_output=""
    local logging_output=""
    local loading_output=""
    local closed_loop_output=""

    bootstrap_output="$(render_session_bootstrap)"
    routing_hint_output="$(render_routing_hint)"
    logging_output="$(render_logging_procedure)"
    loading_output="$(render_loading_procedure)"
    closed_loop_output="$(render_closed_loop_procedure)"

    cat <<EOF
$bootstrap_output

<memory-session-guide>
Memory is available but intentionally not preloaded for this new thread.
Do not use this block when naming or summarizing the session; use user-authored messages for that.
project_memory=$self_improving_project_memory_dir
global_memory_root=$self_improving_global_namespaces_root
log_helper=$SCRIPT_ROOT/capture/log-memory.sh
memory_policy=$self_improving_skill_dir/SKILL.md

$closed_loop_output

$loading_output

$logging_output

$routing_hint_output
</memory-session-guide>
EOF
}

read_hook_input
hook_event_name="$(extract_hook_field "hook_event_name")"

if [[ "$hook_event_name" == "SessionStart" ]]; then
    # Keep SessionStart fail-open and fast on Windows. Project memory init/registry
    # can be done by normal memory commands; the hook should only inject guidance.
    render_session_memory_guide || true
    exit 0
fi

exit 0
