#!/bin/bash
# Promote recurring memory into managed SUMMARY.md sections and update source status.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
. "$SCRIPT_ROOT/shared/file-lock.sh"

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
dry_run=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--project-root PATH] [--project-memory-dir PATH] [--namespace NAME] [--global-memory-dir PATH] [--min-recurrence N] [--dry-run]
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

scope_lock_file_for_dir() {
    local memory_dir="$1"
    printf '%s/.memory-write.lock\n' "$memory_dir"
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

summary_file_for_scope() {
    local target_scope="$1"
    local memory_dir="$2"

    if [[ "$target_scope" == "project" ]]; then
        printf '%s\n' "$memory_dir/SUMMARY.md"
    else
        printf '%s\n' "${memory_dir%/.learnings}/SUMMARY.md"
    fi
}

create_summary_if_missing() {
    local target_scope="$1"
    local summary_file="$2"
    local namespace_label

    if [[ -f "$summary_file" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$summary_file")"

    if [[ "$target_scope" == "project" ]]; then
        cat > "$summary_file" <<'EOF'
# Project Summary

Load this file before opening detailed project memory when you want the shortest useful summary for this repository.

Use this file for repo facts, constraints, and distilled lessons.
Do not store repo-local agent instructions, prompt policy, or routing policy here; keep those in `AGENTS.md` or explicit repo config.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
EOF
    else
        namespace_label="$(basename "$(dirname "$summary_file")")"
        cat > "$summary_file" <<EOF
# ${namespace_label} Summary

Load this file before opening `.learnings/` when you want the shortest useful summary.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
EOF
    fi
}

collect_promotions() {
    local target_scope="$1"
    local memory_dir="$2"
    local threshold="$3"
    local suggest_output=""
    local suggest_args=(--scope "$target_scope" --project-root "$project_root" --limit all --format tsv)

    if [[ -n "$project_memory_dir" ]]; then
        suggest_args+=(--project-memory-dir "$project_memory_dir")
    fi
    if [[ "$target_scope" == "global" ]]; then
        suggest_args+=(--namespace "$namespace")
        if [[ -n "$global_memory_dir_override" ]]; then
            suggest_args+=(--global-memory-dir "$global_memory_dir_override")
        fi
    fi

    suggest_output="$(bash "$SCRIPT_DIR/suggest-promotions.sh" "${suggest_args[@]}")"

    if ! grep -Fq -- "# promotion-suggestions-tsv-v1" <<< "$suggest_output"; then
        echo "writeback-memory.sh expected promotion-suggestions-tsv-v1 output" >&2
        return 1
    fi

    awk -F '\t' -v min_rec="$threshold" '
        /^#/ { next }
        $1 == "rank" { next }
        $10 == "promoted_to_summary" || ($3 == "promote_to_summary" && ($9 + 0) >= min_rec) {
            print $5 "\t" "advisory" "\t" $10 "\t" $9 "\t" $6
        }
    ' <<< "$suggest_output"
}

replace_or_append_block() {
    local summary_file="$1"
    local block_content="$2"

    if self_improving_contains_fixed "<!-- memory-auto-summary:start -->" "$summary_file"; then
        BLOCK_CONTENT="$block_content" perl -0pi -e '
            s{<!-- memory-auto-summary:start -->\n[\s\S]*?<!-- memory-auto-summary:end -->\n?}{$ENV{BLOCK_CONTENT}}g
        ' "$summary_file"
    else
        printf '\n## Auto Promoted Summary\n\n%s' "$block_content" >> "$summary_file"
    fi
}

update_statuses() {
    local memory_dir="$1"
    shift
    local ids=("$@")
    local file
    local entry_id

    for file in "$memory_dir/LEARNINGS.md" "$memory_dir/ERRORS.md" "$memory_dir/FEATURE_REQUESTS.md"; do
        [[ -f "$file" ]] || continue
        for entry_id in "${ids[@]}"; do
            ENTRY_ID="$entry_id" perl -0pi -e '
                my $id = quotemeta $ENV{ENTRY_ID};
                s{(## \[$id\][\s\S]*?\n\*\*Status\*\*: )(pending|in_progress)\b}{$1promoted_to_summary}g;
            ' "$file"
        done
    done
}

write_back_scope() {
    local target_scope="$1"
    local memory_dir="$2"
    local summary_file
    local scope_lock_file
    local promotions
    local promotion_lines=()
    local promoted_ids=()
    local block_lines
    local id
    local priority
    local status
    local recurrence
    local summary

    scope_lock_file="$(scope_lock_file_for_dir "$memory_dir")"
    self_improving_lock_acquire writeback_scope "$scope_lock_file" 8

    summary_file="$(summary_file_for_scope "$target_scope" "$memory_dir")"
    create_summary_if_missing "$target_scope" "$summary_file"
    promotions="$(collect_promotions "$target_scope" "$memory_dir" "$min_recurrence")"

    if [[ -n "$promotions" ]]; then
        while IFS=$'\t' read -r id priority status recurrence summary; do
            [[ -n "$id" ]] || continue
            promotion_lines+=("- [$id] x$recurrence ($priority): $summary")
            promoted_ids+=("$id")
        done <<< "$promotions"
    fi

    if [[ ${#promotion_lines[@]} -eq 0 ]]; then
        block_lines="- none promoted yet"
    else
        printf -v block_lines '%s\n' "${promotion_lines[@]}"
        block_lines="${block_lines%$'\n'}"
    fi

    managed_block="<!-- memory-auto-summary:start -->
$block_lines
<!-- memory-auto-summary:end -->
"

    if [[ "$dry_run" == true ]]; then
        self_improving_lock_release writeback_scope
        printf 'Would update %s with %d promoted entries\n' "$summary_file" "${#promoted_ids[@]}"
        return 0
    fi

    replace_or_append_block "$summary_file" "$managed_block"
    if [[ ${#promoted_ids[@]} -gt 0 ]]; then
        update_statuses "$memory_dir" "${promoted_ids[@]}"
    fi
    self_improving_lock_release writeback_scope
    printf 'Wrote back summary for %s: %s\n' "$target_scope" "$summary_file"
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
        --dry-run)
            dry_run=true
            shift
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
    write_back_scope "project" "$resolved_project_memory_dir"
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    ensure_scope_initialized "global"
    write_back_scope "global" "$resolved_global_memory_dir"
fi
