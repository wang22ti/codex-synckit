#!/bin/bash
# Safely remove a project memory directory after reviewing promotion candidates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
archive_mode="archive"
archive_root="$self_improving_state_root/removed-project-memory"
allow_unpromoted_candidates="false"
dry_run="false"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--project-root PATH] [--project-memory-dir PATH] [--archive-mode archive|purge] [--archive-root PATH] [--allow-unpromoted-candidates true|false] [--dry-run true|false]
EOF
}

print_candidate_preview() {
    local candidates_tsv="$1"
    local found_preview="false"

    while IFS=$'\t' read -r rank scope_label classification destination id summary reason type_label recurrence status; do
        [[ -n "$rank" && "$rank" != "rank" ]] || continue
        case "$classification" in
            promote_to_summary|promote_to_factual_file|consider_skill) ;;
            *) continue ;;
        esac
        found_preview="true"
        printf -- "- [%s] %s -> %s\n" "$id" "$classification" "$destination"
        printf '  Summary: %s\n' "$summary"
        printf '  Reason: %s\n' "$reason"
    done <<< "$candidates_tsv"

    [[ "$found_preview" == "true" ]]
}

next_archive_destination() {
    local archive_root="$1"
    local base_name="$2"
    local candidate="$archive_root/$base_name"
    local suffix=2

    while [[ -e "$candidate" ]]; do
        candidate="$archive_root/${base_name}-${suffix}"
        suffix=$((suffix + 1))
    done

    printf '%s\n' "$candidate"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            project_root="${2:-}"
            shift 2
            ;;
        --project-memory-dir)
            project_memory_dir="${2:-}"
            shift 2
            ;;
        --archive-mode)
            archive_mode="${2:-}"
            shift 2
            ;;
        --archive-root)
            archive_root="${2:-}"
            shift 2
            ;;
        --allow-unpromoted-candidates)
            allow_unpromoted_candidates="${2:-}"
            shift 2
            ;;
        --dry-run)
            dry_run="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$archive_mode" in
    archive|purge) ;;
    *)
        printf 'Invalid --archive-mode: %s\n' "$archive_mode" >&2
        exit 1
        ;;
esac

case "$allow_unpromoted_candidates" in
    true|false) ;;
    *)
        printf 'Invalid --allow-unpromoted-candidates: %s\n' "$allow_unpromoted_candidates" >&2
        exit 1
        ;;
esac

case "$dry_run" in
    true|false) ;;
    *)
        printf 'Invalid --dry-run: %s\n' "$dry_run" >&2
        exit 1
        ;;
esac

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
archive_root="$(self_improving_normalize_path "$archive_root")"
target_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir")"

if [[ ! -d "$target_memory_dir" ]]; then
    self_improving_unregister_project_memory_dir "$target_memory_dir"
    printf 'Project memory directory does not exist; removed stale registry entry if present: %s\n' "$target_memory_dir"
    exit 0
fi

preview_file="$(mktemp "${TMPDIR:-/tmp}/remove-project-memory-preview.XXXXXX")"
trap 'rm -f "$preview_file"' EXIT

candidates_tsv="$(
    bash "$SCRIPT_DIR/suggest-promotions.sh" \
        --scope project \
        --project-root "$project_root" \
        --project-memory-dir "$target_memory_dir" \
        --limit all \
        --format tsv
)"

has_unpromoted_candidates="false"
if print_candidate_preview "$candidates_tsv" >"$preview_file" 2>&1; then
    has_unpromoted_candidates="true"
fi
preview_output="$(cat "$preview_file")"

if [[ "$has_unpromoted_candidates" == "true" ]]; then
    printf 'Potential promotion candidates found before removing project memory:\n'
    printf '%s\n' "$preview_output"
    if [[ "$allow_unpromoted_candidates" != "true" ]]; then
        printf 'Removal stopped. Re-run with --allow-unpromoted-candidates true after reviewing whether these should be preserved in global memory.\n' >&2
        exit 2
    fi
fi

if [[ "$dry_run" == "true" ]]; then
    printf 'Dry run only. No files changed for project memory: %s\n' "$target_memory_dir"
    exit 0
fi

if [[ "$archive_mode" == "archive" ]]; then
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    destination_name="$(basename "${project_root%/}")"
    if [[ -z "$destination_name" || "$destination_name" == "." || "$destination_name" == "/" ]]; then
        destination_name="project-memory"
    fi
    destination_path="$(next_archive_destination "$archive_root" "${destination_name}-${timestamp}")"
    mkdir -p "$archive_root"
    mv "$target_memory_dir" "$destination_path"
    printf 'Archived project memory to: %s\n' "$destination_path"
else
    rm -rf "$target_memory_dir"
    printf 'Deleted project memory directory: %s\n' "$target_memory_dir"
fi

self_improving_unregister_project_memory_dir "$target_memory_dir"
printf 'Removed project memory registry entry: %s\n' "$target_memory_dir"
