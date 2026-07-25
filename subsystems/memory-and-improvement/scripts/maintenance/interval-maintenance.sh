#!/bin/bash
# Run nightly maintenance only when the configured interval has elapsed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="$self_improving_maintenance_scope_default"
project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
namespace="$self_improving_global_namespace"
global_memory_dir_override=""
if [[ "$self_improving_global_memory_dir_overridden" == true ]]; then
    global_memory_dir_override="$self_improving_global_memory_dir"
fi
min_recurrence="$self_improving_organize_min_recurrence_default"
git_commit="$self_improving_git_autocommit_default"
writeback="$self_improving_nightly_writeback_default"
skill_policy_writeback="$self_improving_skill_policy_writeback_default"
interval_minutes=""
state_file="$self_improving_state_root/interval-maintenance.last-run"
declare -A watch_path_seen=()
watch_paths=()
stale_registered_project_memory=false
interval_lock_mode=""
interval_lock_dir=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --interval-minutes N [--scope project|global|both] [--project-root PATH] [--project-memory-dir PATH] [--namespace NAME] [--global-memory-dir PATH] [--min-recurrence N] [--git-commit true|false] [--writeback true|false] [--skill-policy-writeback true|false] [--state-file PATH]
EOF
}

acquire_interval_lock() {
    local lock_file="${state_file}.lock"

    if command -v flock >/dev/null 2>&1; then
        touch "$lock_file"
        exec 8>>"$lock_file"
        flock 8
        interval_lock_mode="flock"
        return 0
    fi

    interval_lock_dir="${lock_file}.d"
    if mkdir "$interval_lock_dir" 2>/dev/null; then
        interval_lock_mode="mkdir"
        return 0
    fi

    printf 'Interval maintenance skipped: another run holds fallback lock %s\n' "$interval_lock_dir"
    return 1
}

release_interval_lock() {
    case "$interval_lock_mode" in
        flock)
            flock -u 8
            exec 8>&-
            ;;
        mkdir)
            rmdir "$interval_lock_dir" 2>/dev/null || true
            ;;
    esac
    interval_lock_mode=""
}

add_watch_path() {
    local path="$1"
    local normalized=""

    [[ -n "$path" ]] || return 0
    normalized="$(self_improving_normalize_path "$path")"
    [[ -e "$normalized" ]] || return 0

    if [[ -z "${watch_path_seen[$normalized]:-}" ]]; then
        watch_path_seen["$normalized"]=1
        watch_paths+=("$normalized")
    fi
}

collect_project_watch_paths() {
    local resolved_project_memory_dir="$1"
    local registered_memory_dir=""

    if [[ -d "$resolved_project_memory_dir" ]]; then
        add_watch_path "$resolved_project_memory_dir"
    fi

    while IFS= read -r registered_memory_dir; do
        [[ -n "$registered_memory_dir" ]] || continue
        registered_memory_dir="$(self_improving_normalize_path "$registered_memory_dir")"
        if [[ -d "$registered_memory_dir" ]]; then
            add_watch_path "$registered_memory_dir"
        else
            stale_registered_project_memory=true
        fi
    done < <(self_improving_list_registered_project_memory_dirs)
}

collect_global_watch_paths() {
    local resolved_global_memory_dir="$1"
    local discovered_namespace_dir=""

    if [[ -n "$global_memory_dir_override" ]]; then
        add_watch_path "$(dirname "${resolved_global_memory_dir%/.learnings}")"
        add_watch_path "${resolved_global_memory_dir%/.learnings}"
        return 0
    fi

    if [[ -d "$self_improving_global_namespaces_root" ]]; then
        add_watch_path "$self_improving_global_namespaces_root"
        while IFS= read -r discovered_namespace_dir; do
            [[ -n "$discovered_namespace_dir" ]] || continue
            add_watch_path "$discovered_namespace_dir"
        done < <(find "$self_improving_global_namespaces_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
        return 0
    fi

    add_watch_path "${resolved_global_memory_dir%/.learnings}"
}

watch_paths_changed_since_epoch() {
    local since_epoch="$1"
    local marker_file=""
    local path=""

    if [[ "$stale_registered_project_memory" == true ]]; then
        return 0
    fi

    [[ ${#watch_paths[@]} -gt 0 ]] || return 1

    marker_file="$(mktemp "${TMPDIR:-/tmp}/interval-maintenance-marker.XXXXXX")"
    touch -d "@$since_epoch" "$marker_file"
    trap 'rm -f "$marker_file"' RETURN

    for path in "${watch_paths[@]}"; do
        if [[ "$path" -nt "$marker_file" ]]; then
            return 0
        fi
        if [[ -d "$path" ]]; then
            if find "$path" -type f -newer "$marker_file" -print -quit 2>/dev/null | grep -q .; then
                return 0
            fi
        fi
    done

    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interval-minutes)
            interval_minutes="${2:-}"
            shift 2
            ;;
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
        --git-commit)
            git_commit="${2:-}"
            shift 2
            ;;
        --writeback)
            writeback="${2:-}"
            shift 2
            ;;
        --skill-policy-writeback)
            skill_policy_writeback="${2:-}"
            shift 2
            ;;
        --state-file)
            state_file="${2:-}"
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

case "$skill_policy_writeback" in
    true|false) ;;
    *)
        echo "Invalid --skill-policy-writeback: $skill_policy_writeback" >&2
        exit 1
        ;;
esac

[[ -n "$interval_minutes" ]] || {
    echo "--interval-minutes is required" >&2
    exit 1
}

[[ "$interval_minutes" =~ ^[0-9]+$ ]] || {
    echo "--interval-minutes must be a positive integer" >&2
    exit 1
}

if [[ "$interval_minutes" -le 0 ]]; then
    echo "--interval-minutes must be greater than 0" >&2
    exit 1
fi

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
state_file="$(self_improving_normalize_path "$state_file")"
resolved_project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir")"
resolved_global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" || "$scope" == "both" ]]; then
    resolved_global_memory_dir="$(self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override")"
fi

mkdir -p "$(dirname "$state_file")"
acquire_interval_lock || exit 0
trap 'release_interval_lock' EXIT

last_run="0"
if [[ -f "$state_file" ]]; then
    last_run="$(tr -d '[:space:]' < "$state_file" 2>/dev/null || printf '0')"
fi

if [[ ! "$last_run" =~ ^[0-9]+$ ]]; then
    last_run="0"
fi

interval_seconds="$((interval_minutes * 60))"
check_epoch="$(date +%s)"

if (( last_run > 0 )); then
    elapsed_seconds="$((check_epoch - last_run))"
    if (( elapsed_seconds < interval_seconds )); then
        remaining_seconds="$((interval_seconds - elapsed_seconds))"
        printf 'Interval maintenance skipped: %ss elapsed; need %ss (%s min interval), %ss remaining\n' \
            "$elapsed_seconds" "$interval_seconds" "$interval_minutes" "$remaining_seconds"
        release_interval_lock
        exit 0
    fi
fi

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    collect_project_watch_paths "$resolved_project_memory_dir"
fi
if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    collect_global_watch_paths "$resolved_global_memory_dir"
fi

if (( last_run > 0 )) && ! watch_paths_changed_since_epoch "$last_run"; then
    printf 'Interval maintenance skipped: no relevant memory changes since epoch=%s\n' "$last_run"
    release_interval_lock
    exit 0
fi

nightly_args=(
    --scope "$scope"
    --project-root "$project_root"
    --namespace "$namespace"
    --min-recurrence "$min_recurrence"
    --git-commit "$git_commit"
    --writeback "$writeback"
    --skill-policy-writeback "$skill_policy_writeback"
)

if [[ -n "$project_memory_dir" ]]; then
    nightly_args+=(--project-memory-dir "$project_memory_dir")
fi

if [[ -n "$global_memory_dir_override" ]]; then
    nightly_args+=(--global-memory-dir "$global_memory_dir_override")
fi

bash "$SCRIPT_DIR/nightly-maintenance.sh" "${nightly_args[@]}"
completed_epoch="$(date +%s)"
printf '%s\n' "$completed_epoch" > "$state_file"
printf 'Interval maintenance marked successful completion at epoch=%s using state file %s\n' "$completed_epoch" "$state_file"

release_interval_lock
