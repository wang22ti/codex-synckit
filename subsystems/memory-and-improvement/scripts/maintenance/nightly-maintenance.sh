#!/bin/bash
# Run nightly memory organization, advisory-informed writeback, and optional git commits.

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

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--project-root PATH] [--project-memory-dir PATH] [--namespace NAME] [--global-memory-dir PATH] [--min-recurrence N] [--git-commit true|false] [--writeback true|false] [--skill-policy-writeback true|false]
EOF
}

maybe_add_project_target() {
    local memory_dir="$1"
    local key=""

    [[ -n "$memory_dir" ]] || return 0
    memory_dir="$(self_improving_normalize_path "$memory_dir")"
    if [[ ! -d "$memory_dir" ]]; then
        self_improving_unregister_project_memory_dir "$memory_dir"
        printf 'Nightly maintenance pruned missing project memory registry entry: %s\n' "$memory_dir"
        return 0
    fi

    key="${memory_dir%/}"
    if [[ -z "${project_target_seen[$key]:-}" ]]; then
        project_target_seen["$key"]=1
        project_targets+=("$key")
    fi
}

list_global_namespace_targets() {
    if [[ -n "$global_memory_dir_override" ]]; then
        [[ -d "$resolved_global_memory_dir" ]] && printf '%s\t%s\n' "$namespace" "$resolved_global_memory_dir"
        return 0
    fi

    if [[ -d "$self_improving_global_namespaces_root" ]]; then
        find "$self_improving_global_namespaces_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | while IFS= read -r discovered_namespace; do
            [[ -n "$discovered_namespace" ]] || continue
            discovered_memory_dir="$(self_improving_resolve_global_memory_dir "$discovered_namespace")"
            [[ -d "$discovered_memory_dir" ]] || continue
            printf '%s\t%s\n' "$discovered_namespace" "$discovered_memory_dir"
        done
        return 0
    fi

    [[ -d "$resolved_global_memory_dir" ]] && printf '%s\t%s\n' "$namespace" "$resolved_global_memory_dir"
}

project_root_for_memory_dir() {
    local memory_dir="$1"

    if [[ "$memory_dir" == */.learnings ]]; then
        printf '%s\n' "${memory_dir%/.learnings}"
    else
        dirname "$memory_dir"
    fi
}

run_project_maintenance() {
    local memory_dir="$1"
    local target_root
    local writeback_args
    local organize_args
    local git_args

    target_root="$(project_root_for_memory_dir "$memory_dir")"
    writeback_args=(--scope project --project-root "$target_root" --project-memory-dir "$memory_dir" --min-recurrence "$min_recurrence")
    organize_args=(--scope project --project-root "$target_root" --project-memory-dir "$memory_dir" --min-recurrence "$min_recurrence")
    git_args=(--scope project --project-root "$target_root" --project-memory-dir "$memory_dir" --message "memory: nightly maintenance $(date +%F)")

    if [[ "$writeback" == "true" ]]; then
        bash "$SCRIPT_DIR/writeback-memory.sh" "${writeback_args[@]}"
    fi

    bash "$SCRIPT_DIR/organize-memory.sh" "${organize_args[@]}"

    if [[ "$git_commit" == "true" ]]; then
        bash "$SCRIPT_ROOT/maintenance/git-memory.sh" commit "${git_args[@]}"
    fi
}

run_global_maintenance_for_namespace() {
    local target_namespace="$1"
    local target_memory_dir="$2"
    local writeback_args=(--scope global --namespace "$target_namespace" --min-recurrence "$min_recurrence")
    local organize_args=(--scope global --namespace "$target_namespace" --min-recurrence "$min_recurrence")
    local git_args=(--scope global --namespace "$target_namespace" --message "memory: nightly maintenance $(date +%F)")

    if [[ -n "$target_memory_dir" ]]; then
        writeback_args+=(--global-memory-dir "$target_memory_dir")
        organize_args+=(--global-memory-dir "$target_memory_dir")
        git_args+=(--global-memory-dir "$target_memory_dir")
    fi

    if [[ "$writeback" == "true" ]]; then
        bash "$SCRIPT_DIR/writeback-memory.sh" "${writeback_args[@]}"
    fi

    bash "$SCRIPT_DIR/organize-memory.sh" "${organize_args[@]}"

    if [[ "$git_commit" == "true" ]]; then
        bash "$SCRIPT_ROOT/maintenance/git-memory.sh" commit "${git_args[@]}"
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

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
resolved_project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir")"
resolved_global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" || "$scope" == "both" ]]; then
    resolved_global_memory_dir="$(self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override")"
fi
if [[ -n "$resolved_global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$resolved_project_memory_dir" "$resolved_global_memory_dir"
fi

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

declare -A project_target_seen=()
project_targets=()

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    if [[ -n "$project_memory_dir" ]]; then
        maybe_add_project_target "$project_memory_dir"
    else
        maybe_add_project_target "$resolved_project_memory_dir"
    fi

    while IFS= read -r memory_dir; do
        [[ -n "$memory_dir" ]] || continue
        maybe_add_project_target "$memory_dir"
    done < <(self_improving_list_registered_project_memory_dirs)

    if [[ ${#project_targets[@]} -eq 0 ]]; then
        printf 'Nightly maintenance skipped project scope: no existing project memory directories found\n'
    else
        for memory_dir in "${project_targets[@]}"; do
            run_project_maintenance "$memory_dir"
        done
    fi
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    global_targets=()
    while IFS= read -r target_line; do
        [[ -n "$target_line" ]] || continue
        global_targets+=("$target_line")
    done < <(list_global_namespace_targets)

    if [[ ${#global_targets[@]} -eq 0 ]]; then
        printf 'Nightly maintenance skipped global scope: no existing global memory directories found\n'
    else
        for target_line in "${global_targets[@]}"; do
            target_namespace="${target_line%%$'\t'*}"
            target_memory_dir="${target_line#*$'\t'}"
            run_global_maintenance_for_namespace "$target_namespace" "$target_memory_dir"
        done
    fi
fi

if [[ "$skill_policy_writeback" == "true" && ("$scope" == "project" || "$scope" == "both") ]]; then
    if [[ -d "$resolved_project_memory_dir" ]]; then
        skill_policy_args=(--project-root "$project_root")
        if [[ -n "$project_memory_dir" ]]; then
            skill_policy_args+=(--project-memory-dir "$project_memory_dir")
        fi
        bash "$SCRIPT_DIR/update-skill-policy.sh" "${skill_policy_args[@]}"
    else
        printf 'Nightly maintenance skipped skill policy writeback: no existing project memory directory found\n'
    fi
fi

printf 'Nightly maintenance complete for scope=%s\n' "$scope"
