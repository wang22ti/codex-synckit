#!/bin/bash
# Git integration for project/global memory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

command_name=""
scope="both"
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
message="memory: update"

usage() {
    cat <<EOF
Usage: $(basename "$0") <init|status|commit> [options]

Options:
  --scope project|global|both
  --project-root PATH
  --project-memory-dir PATH
  --namespace NAME
  --global-memory-dir PATH
  --message TEXT              Commit message for commit mode

Examples:
  $(basename "$0") init --scope both
  $(basename "$0") status --scope global
  $(basename "$0") commit --scope project --message "memory(project): update"
EOF
}

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
}

resolve_global_memory_dir() {
    self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override"
}

ensure_git_available() {
    if ! command -v git >/dev/null 2>&1; then
        echo "The git-memory workflow requires the git command in PATH." >&2
        exit 1
    fi
}

is_within_path() {
    local child="$1"
    local parent="$2"
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

ensure_git_repo() {
    local repo_root="$1"
    if [[ ! -d "$repo_root/.git" ]]; then
        git -C "$repo_root" init >/dev/null
    fi
    if ! git -C "$repo_root" config user.name >/dev/null 2>&1; then
        git -C "$repo_root" config user.name "Codex Memory"
    fi
    if ! git -C "$repo_root" config user.email >/dev/null 2>&1; then
        git -C "$repo_root" config user.email "codex-memory@local"
    fi
}

resolve_scope_repo() {
    local target_scope="$1"
    local memory_dir="$2"
    local preferred_repo_root="${3:-}"
    local repo_root=""
    local status_kind=""

    if git -C "$memory_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
        repo_root="$(git -C "$memory_dir" rev-parse --show-toplevel)"
        status_kind="existing"
    else
        if [[ -n "$preferred_repo_root" ]]; then
            repo_root="$preferred_repo_root"
        elif [[ "$target_scope" == "global" ]]; then
            repo_root="$self_improving_global_root"
        else
            repo_root="$memory_dir"
        fi
        mkdir -p "$repo_root"
        ensure_git_repo "$repo_root"
        status_kind="initialized"
    fi

    printf '%s\t%s\n' "$repo_root" "$status_kind"
}

relative_to_repo() {
    local repo_root="$1"
    local path="$2"

    if [[ "$path" == "$repo_root" ]]; then
        printf '.\n'
    else
        printf '%s\n' "${path#$repo_root/}"
    fi
}

commit_paths() {
    local repo_root="$1"
    local commit_message="$2"
    shift 2

    local rel_paths=()
    local rel_lock_paths=()
    local author_name=""
    local author_email=""
    local path
    for path in "$@"; do
        if is_within_path "$path" "$repo_root"; then
            rel_paths+=("$(relative_to_repo "$repo_root" "$path")")
            while IFS= read -r lock_file; do
                [[ -n "$lock_file" ]] || continue
                rel_lock_paths+=("$(relative_to_repo "$repo_root" "$lock_file")")
            done < <(find "$path" -type f -name '*.lock' 2>/dev/null || true)
        fi
    done

    if [[ ${#rel_paths[@]} -eq 0 ]]; then
        echo "No committable paths under $repo_root"
        return 0
    fi

    git -C "$repo_root" add -- "${rel_paths[@]}"

    if [[ ${#rel_lock_paths[@]} -gt 0 ]]; then
        local rel_lock
        for rel_lock in "${rel_lock_paths[@]}"; do
            if git -C "$repo_root" ls-files --error-unmatch -- "$rel_lock" >/dev/null 2>&1; then
                git -C "$repo_root" rm --cached -q -- "$rel_lock"
            fi
        done
    fi

    if git -C "$repo_root" diff --cached --quiet -- "${rel_paths[@]}"; then
        echo "No changes to commit in $repo_root"
        return 0
    fi

    author_name="$(git -C "$repo_root" config user.name 2>/dev/null || true)"
    author_email="$(git -C "$repo_root" config user.email 2>/dev/null || true)"
    if [[ -z "$author_name" ]]; then
        author_name="Codex Memory"
    fi
    if [[ -z "$author_email" ]]; then
        author_email="codex-memory@local"
    fi

    if [[ ${#rel_paths[@]} -eq 1 && "${rel_paths[0]}" == "." ]]; then
        GIT_AUTHOR_NAME="$author_name" \
        GIT_AUTHOR_EMAIL="$author_email" \
        GIT_COMMITTER_NAME="$author_name" \
        GIT_COMMITTER_EMAIL="$author_email" \
        git -C "$repo_root" commit -m "$commit_message" >/dev/null
    else
        GIT_AUTHOR_NAME="$author_name" \
        GIT_AUTHOR_EMAIL="$author_email" \
        GIT_COMMITTER_NAME="$author_name" \
        GIT_COMMITTER_EMAIL="$author_email" \
        git -C "$repo_root" commit -m "$commit_message" -- "${rel_paths[@]}" >/dev/null
    fi
    printf 'Committed memory changes in %s\n' "$repo_root"
}

handle_project_scope() {
    local action="$1"
    local memory_dir
    local repo_info
    local repo_root
    local status_kind

    memory_dir="$(resolve_project_memory_dir)"
    bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope project --project-root "$project_root" ${project_memory_dir:+--project-memory-dir "$project_memory_dir"} >/dev/null
    repo_info="$(resolve_scope_repo "project" "$memory_dir")"
    repo_root="${repo_info%%$'\t'*}"
    status_kind="${repo_info##*$'\t'}"

    case "$action" in
        init)
            printf 'Project memory git: %s (%s)\n' "$repo_root" "$status_kind"
            ;;
        status)
            printf 'Project memory dir: %s\n' "$memory_dir"
            printf 'Project memory git: %s (%s)\n' "$repo_root" "$status_kind"
            git -C "$repo_root" status --short -- "$(relative_to_repo "$repo_root" "$memory_dir")" || true
            ;;
        commit)
            commit_paths "$repo_root" "$message" "$memory_dir"
            ;;
    esac
}

handle_global_scope() {
    local action="$1"
    local memory_dir
    local status_path
    local commit_paths_list=()
    local repo_info
    local repo_root
    local status_kind
    local preferred_repo_root
    local namespace_dir
    local namespaces_root
    local global_root_readme

    memory_dir="$(resolve_global_memory_dir)"
    namespace_dir="$(self_improving_resolve_global_namespace_dir "$namespace" "$global_memory_dir_override")"
    namespaces_root="$self_improving_global_namespaces_root"
    preferred_repo_root="$self_improving_global_root"
    if [[ -n "$global_memory_dir_override" ]]; then
        preferred_repo_root="$namespace_dir"
    fi
    if [[ -n "$global_memory_dir_override" ]]; then
        bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope global --global-memory-dir "$global_memory_dir_override" >/dev/null
    else
        bash "$SCRIPT_ROOT/bootstrap/init-memory.sh" --scope global --global-namespace "$namespace" >/dev/null
    fi
    repo_info="$(resolve_scope_repo "global" "$memory_dir" "$preferred_repo_root")"
    repo_root="${repo_info%%$'\t'*}"
    status_kind="${repo_info##*$'\t'}"
    status_path="$(relative_to_repo "$repo_root" "$namespace_dir")"
    commit_paths_list=("$namespace_dir")
    if [[ -z "$global_memory_dir_override" && "$repo_root" == "$self_improving_global_root" && -d "$namespaces_root" ]]; then
        status_path="$(relative_to_repo "$repo_root" "$namespaces_root")"
        commit_paths_list=("$namespaces_root")
    fi
    global_root_readme="$self_improving_global_root/README.md"
    if [[ "$global_memory_dir_override" == "" && "$repo_root" == "$self_improving_global_root" && -f "$global_root_readme" ]]; then
        commit_paths_list+=("$global_root_readme")
    fi

    case "$action" in
        init)
            printf 'Global memory git: %s (%s)\n' "$repo_root" "$status_kind"
            ;;
        status)
            printf 'Global memory dir: %s\n' "$memory_dir"
            printf 'Global memory git: %s (%s)\n' "$repo_root" "$status_kind"
            git -C "$repo_root" status --short -- "$status_path" || true
            if [[ ${#commit_paths_list[@]} -gt 1 ]]; then
                git -C "$repo_root" status --short -- "$(relative_to_repo "$repo_root" "$global_root_readme")" || true
            fi
            ;;
        commit)
            commit_paths "$repo_root" "$message" "${commit_paths_list[@]}"
            ;;
    esac
}

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

command_name="$1"
shift

case "$command_name" in
    init|status|commit) ;;
    *)
        echo "Unknown command: $command_name" >&2
        usage >&2
        exit 1
        ;;
esac

ensure_git_available

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
        --message)
            message="${2:-}"
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
    handle_project_scope "$command_name"
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    handle_global_scope "$command_name"
fi
