#!/bin/bash
# Generate maintenance reports and summary candidates for memory scopes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="both"
namespace="$self_improving_global_namespace"
project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
global_memory_dir_override=""
if [[ "$self_improving_global_memory_dir_overridden" == true ]]; then
    global_memory_dir_override="$self_improving_global_memory_dir"
fi
min_recurrence="$self_improving_organize_min_recurrence_default"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--project-root PATH] [--project-memory-dir PATH] [--namespace NAME] [--global-memory-dir PATH] [--min-recurrence N]
EOF
}

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
}

resolve_global_memory_dir() {
    self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override"
}

parse_entries() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    awk -f "$SCRIPT_ROOT/shared/memory-entry-parser.awk" "$dir"/*.md 2>/dev/null
}

ensure_scope_initialized() {
    if [[ "$1" == "project" ]]; then
        if [[ -n "$project_memory_dir" ]]; then
            bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope project --project-root "$project_root" --project-memory-dir "$project_memory_dir" >/dev/null
        else
            bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope project --project-root "$project_root" >/dev/null
        fi
    else
        if [[ -n "$global_memory_dir_override" ]]; then
            bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope global --global-memory-dir "$global_memory_dir_override" >/dev/null
        else
            bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope global --global-namespace "$namespace" >/dev/null
        fi
    fi
}

render_pending_items() {
    local memory_dir="$1"

    parse_entries "$memory_dir" | awk -F '\t' '$4 == "pending" { print "- [" $1 "] " $3 ": " $5 }'
}

render_recurring_items() {
    local memory_dir="$1"
    local threshold="$2"

    parse_entries "$memory_dir" | awk -F '\t' -v min_rec="$threshold" -v status_re="$self_improving_promotable_status_regex" '(($6 + 0) >= min_rec || $4 == "promoted_to_summary") && ($4 ~ status_re) { print "- [" $1 "] x" $6 " (" $3 ", " $4 "): " $5 }'
}

write_report() {
    local scope_name="$1"
    local memory_dir="$2"
    local report_file="$3"
    local candidates_file="$4"
    local pending_items
    local recurring_items

    pending_items="$(render_pending_items "$memory_dir")"
    recurring_items="$(render_recurring_items "$memory_dir" "$min_recurrence")"

    cat > "$report_file" <<EOF
# ${scope_name} Memory Review

**Memory Dir**: $memory_dir

## Pending Items

EOF

    if [[ -n "$pending_items" ]]; then
        printf '%s\n' "$pending_items" >> "$report_file"
    else
        echo "- none" >> "$report_file"
    fi

    cat >> "$report_file" <<'EOF'

## Recurring Candidates

EOF

    if [[ -n "$recurring_items" ]]; then
        printf '%s\n' "$recurring_items" >> "$report_file"
    else
        echo "- none" >> "$report_file"
    fi

    cat > "$candidates_file" <<EOF
# ${scope_name} Summary Candidates

**Threshold**: recurrence >= $min_recurrence
**Policy**: advisory review hints only; not every recurring item should be promoted

EOF

    if [[ -n "$recurring_items" ]]; then
        printf '%s\n' "$recurring_items" >> "$candidates_file"
    else
        echo "- none" >> "$candidates_file"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
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
        --namespace)
            namespace="${2:-}"
            shift 2
            ;;
        --global-memory-dir)
            global_memory_dir_override="${2:-}"
            shift 2
            ;;
        --min-recurrence)
            min_recurrence="${2:-}"
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

case "$scope" in
    project|global|both) ;;
    *)
        echo "Invalid scope: $scope" >&2
        exit 1
        ;;
esac

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
resolved_project_memory_dir="$(resolve_project_memory_dir)"
resolved_global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" || "$scope" == "both" ]]; then
    resolved_global_memory_dir="$(resolve_global_memory_dir)"
fi
if [[ -n "$resolved_global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$resolved_project_memory_dir" "$resolved_global_memory_dir"
fi

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    ensure_scope_initialized "project"
    write_report \
        "Project" \
        "$resolved_project_memory_dir" \
        "$resolved_project_memory_dir/REVIEW.md" \
        "$resolved_project_memory_dir/SUMMARY_CANDIDATES.md"
    printf 'Organized project memory: %s\n' "$resolved_project_memory_dir"
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    ensure_scope_initialized "global"
    global_namespace_dir="${resolved_global_memory_dir%/.learnings}"
    write_report \
        "Global" \
        "$resolved_global_memory_dir" \
        "$resolved_global_memory_dir/REVIEW.md" \
        "$global_namespace_dir/SUMMARY_CANDIDATES.md"
    printf 'Organized global memory: %s\n' "$resolved_global_memory_dir"
fi
