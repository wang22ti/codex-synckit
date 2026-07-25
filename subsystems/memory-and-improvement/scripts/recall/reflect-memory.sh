#!/bin/bash
# Advisory reflect helper for substantial turns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="auto"
namespace="$self_improving_global_namespace"
namespace_explicit=false
project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
global_memory_dir_override=""
if [[ "$self_improving_global_memory_dir_overridden" == true ]]; then
    global_memory_dir_override="$self_improving_global_memory_dir"
fi
summary=""
details=""
event="other"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope auto|project|global] [--namespace NAME] [--summary TEXT] [--details TEXT] [--event correction|failure|feature_request|implementation|decision|other] [--project-root PATH] [--project-memory-dir PATH] [--global-memory-dir PATH]
EOF
}

validate_one_of() {
    local name="$1"
    local value="$2"
    shift 2
    local allowed

    for allowed in "$@"; do
        if [[ "$value" == "$allowed" ]]; then
            return 0
        fi
    done

    printf 'Invalid %s: %s\n' "$name" "$value" >&2
    printf 'Allowed values: %s\n' "$*" >&2
    exit 1
}

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

infer_namespace_from_text() {
    local text
    text="$(lowercase "$1")"

    if [[ "$text" == *"preferred name"* || "$text" == *"academic profile"* || "$text" == *"publication list"* || "$text" == *"publications list"* || "$text" == *"publication record"* || "$text" == *"funding history"* || "$text" == *"fellowship history"* || "$text" == *"grant history"* || "$text" == *"award history"* || "$text" == *"advisor"* || "$text" == *"degree"* || "$text" == *"curriculum vitae"* || "$text" == *"cv"* ]]; then
        printf 'user-profile\n'
    elif [[ "$text" == *"proposal"* || "$text" == *"submission"* || "$text" == *"milestone"* || "$text" == *"under review"* ]]; then
        printf 'research-history\n'
    elif [[ "$text" == *"proxy"* || "$text" == *"latexmk"* || "$text" == *"bibtex"* || "$text" == *"tooling"* || "$text" == *"campus"* ]]; then
        printf 'research-ops\n'
    else
        printf '\n'
    fi
}

resolve_scope_and_namespace() {
    local text="$1"
    local resolved_scope="$scope"
    local resolved_namespace="$namespace"

    if [[ "$scope" == "auto" ]]; then
        if [[ "$namespace_explicit" == true ]]; then
            resolved_scope="global"
        else
            local inferred_namespace
            inferred_namespace="$(infer_namespace_from_text "$text")"
            if [[ -n "$inferred_namespace" ]]; then
                resolved_scope="global"
                resolved_namespace="$inferred_namespace"
            else
                resolved_scope="project"
            fi
        fi
    fi

    printf '%s\t%s\n' "$resolved_scope" "$resolved_namespace"
}

contains_any() {
    local haystack
    haystack="$(lowercase "$1")"
    shift
    local needle

    for needle in "$@"; do
        if [[ "$haystack" == *"$needle"* ]]; then
            return 0
        fi
    done

    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --namespace)
            namespace="${2:-}"
            namespace_explicit=true
            shift 2
            ;;
        --summary)
            summary="${2:-}"
            shift 2
            ;;
        --details)
            details="${2:-}"
            shift 2
            ;;
        --event)
            event="${2:-}"
            shift 2
            ;;
        --project-root)
            project_root="${2:-}"
            shift 2
            ;;
        --project-memory-dir)
            project_memory_dir="${2:-}"
            shift 2
            ;;
        --global-memory-dir)
            global_memory_dir_override="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

validate_one_of "scope" "$scope" auto project global
validate_one_of "event" "$event" correction failure feature_request implementation decision other

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
else
    project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "")"
fi

if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi

combined_text="$summary"
if [[ -n "$details" ]]; then
    combined_text+=$'\n'"$details"
fi
combined_text_lower="$(lowercase "$combined_text")"

resolved_fields="$(resolve_scope_and_namespace "$combined_text")"
resolved_scope="${resolved_fields%%$'\t'*}"
resolved_namespace="${resolved_fields#*$'\t'}"
namespace="$resolved_namespace"

if [[ "$resolved_scope" == "global" ]]; then
    global_memory_dir="$(self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override")"
    self_improving_validate_memory_isolation_or_die "$project_memory_dir" "$global_memory_dir"
fi

primary_action="log_learning"
secondary_action="none"
promotion_hint="none"
reason="Substantial turns often deserve permissive raw capture in .learnings."
suggested_type="learning"

if [[ -z "${combined_text//[$' \t\r\n']/}" ]] || contains_any "$combined_text_lower" "no durable info" "no durable information" "nothing durable" "nothing worth remembering" "no memory candidate" "no follow-up memory" "transient only"; then
    primary_action="no_action"
    reason="No durable information was supplied, so reflect can stay quiet."
    suggested_type="none"
elif [[ "$event" == "failure" ]]; then
    primary_action="log_error"
    reason="Failures are high-recall candidates and usually belong in raw error history."
    suggested_type="error"
elif [[ "$event" == "feature_request" ]]; then
    primary_action="log_feature_request"
    reason="Feature requests should stay visible as deliberate requests rather than silent learnings."
    suggested_type="feature_request"
elif contains_any "$combined_text_lower" "reusable workflow" "reusable process" "repeatable workflow" "repeatable process" "procedure" "playbook" "runbook" "checklist" "template" "skill candidate" "extract a skill"; then
    primary_action="consider_skill"
    secondary_action="log_learning"
    reason="The main value looks procedural and reusable, so it may belong in a skill."
    suggested_type="learning"
elif [[ "$event" == "correction" ]]; then
    primary_action="log_learning"
    reason="Corrections are strong candidates for permissive raw capture so the same miss is easier to avoid next time."
    suggested_type="learning"
elif [[ "$event" == "decision" || "$event" == "implementation" || "$event" == "other" ]]; then
    primary_action="log_learning"
    reason="This turn looks like a repo-local lesson, convention, or durable implementation note."
    suggested_type="learning"
fi

if [[ "$primary_action" != "no_action" ]] && contains_any "$combined_text_lower" "recurring" "recur" "repeat" "repeated" "always" "default" "policy" "convention" "high-priority" "summary candidate"; then
    if [[ "$secondary_action" == "none" ]]; then
        secondary_action="consider_summary"
    else
        promotion_hint="consider_summary"
    fi
fi

echo "<memory-reflect>"
printf 'Requested-Scope: %s\n' "$scope"
printf 'Resolved-Scope: %s\n' "$resolved_scope"
if [[ "$resolved_scope" == "global" ]]; then
    printf 'Resolved-Namespace: %s\n' "$namespace"
fi
printf 'Event: %s\n' "$event"
printf 'Primary-Action: %s\n' "$primary_action"
printf 'Secondary-Action: %s\n' "$secondary_action"
printf 'Suggested-Type: %s\n' "$suggested_type"
printf 'Reason: %s\n' "$reason"
echo "Advisory-Only: true"
echo "Main-Session-Decision-Required: true"
if [[ "$primary_action" == "consider_skill" ]]; then
    echo "Skill-Hint: consider extracting a reusable procedure instead of only logging raw memory"
fi
if [[ "$promotion_hint" == "consider_summary" ]]; then
    echo "Promotion-Hint: the wording suggests a stable or recurring pattern worth later summary review"
fi
echo "</memory-reflect>"
