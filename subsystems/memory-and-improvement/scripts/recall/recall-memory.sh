#!/bin/bash
# Summary-first recall helper for the current turn.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="auto"
mode="default"
mode_explicit=false
memory_system_view="auto"
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
query=""
search_type=""
status_filter=""
max_items=3
max_items_explicit=false
max_hits=8
deeper="false"
include_project_registry="false"
registry_existing_only="false"
project_registry_max_items=""
registry_only_recall="false"
review_mode="default"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope auto|project|global|both] [--mode default|memory-system|project-registry] [--memory-system-view auto|overview|project-registry] [--namespace NAME] [--query TEXT] [--type learning|error|feature_request|asset] [--status STATUS] [--project-root PATH] [--project-memory-dir PATH] [--global-memory-dir PATH] [--max-items N] [--max-hits N] [--deeper true|false]
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

normalize_type() {
    case "$1" in
        "") printf '\n' ;;
        learning) printf 'learning\n' ;;
        error) printf 'error\n' ;;
        feature|feature_request) printf 'feature_request\n' ;;
        asset) printf 'asset\n' ;;
        *)
            echo "Invalid type: $1" >&2
            echo "Allowed values: learning error feature_request asset" >&2
            exit 1
            ;;
    esac
}

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_global_memory_dir() {
    self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override"
}

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
}

infer_namespace_from_query() {
    local text
    text="$(lowercase "$1")"

    if [[ "$text" == *"preferred name"* || "$text" == *"profile"* || "$text" == *"publication"* || "$text" == *"funding"* || "$text" == *"fellowship"* || "$text" == *"grant"* || "$text" == *"award"* || "$text" == *"advisor"* || "$text" == *"degree"* || "$text" == *"affiliation"* || "$text" == *"bio"* || "$text" == *"cv"* || "$text" == *"who am i"* || "$text" == *"whoami"* || "$text" == *"do you know me"* || "$text" == *"my name"* || "$text" == *"my identity"* || "$text" == *"我是谁"* || "$text" == *"你知道我是谁"* || "$text" == *"你认识我"* || "$text" == *"你了解我"* || "$text" == *"我的名字"* || "$text" == *"我的身份"* || "$text" == *"我的档案"* || "$text" == *"我的个人资料"* ]]; then
        printf 'user-profile\n'
    elif [[ "$text" == *"proposal"* || "$text" == *"submission"* || "$text" == *"milestone"* || "$text" == *"under review"* || "$text" == *"status"* ]]; then
        printf 'research-history\n'
    elif [[ "$text" == *"proxy"* || "$text" == *"latexmk"* || "$text" == *"bibtex"* || "$text" == *"tooling"* || "$text" == *"workflow"* || "$text" == *"campus"* ]]; then
        printf 'research-ops\n'
    else
        printf '\n'
    fi
}

query_has_project_signals() {
    local text
    text="$(lowercase "$1")"

    case "$text" in
        *repo-local*|*repository*|*repo*|*project*|*codebase*|*implementation*|*file*|*files*|*module*|*modules*|*test*|*tests*|*fixture*|*fixtures*|*path*|*paths*|*build*|*docs*|*diagram*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

query_is_project_registry_meta() {
    local text
    text="$(lowercase "$1")"

    if [[ "$text" == *"project-memory"* || "$text" == *"project memory"* || "$text" == *"project memor"* ]]; then
        if [[ "$text" == *"register"* || "$text" == *"registr"* || "$text" == *"which"* || "$text" == *"这台机器"* || "$text" == *"哪些"* || "$text" == *"注册"* || "$text" == *"已注册"* ]]; then
            return 0
        fi
    fi

    return 1
}

query_is_memory_system_meta() {
    local text
    text="$(lowercase "$1")"
    local has_subject="false"
    local has_inspection_cue="false"

    case "$text" in
        *"memory system"*|*"memory-system"*|*"project memory"*|*"global memory"*|*"project-memory"*|*"global-memory"*|*"memory registry"*|*"memory root"*|*"global namespace"*|*"global namespaces"*|*"记忆系统"*|*"全局记忆"*|*"项目记忆"*|*"project memor"*|*"global memor"*)
            has_subject="true"
            ;;
    esac

    case "$text" in
        *"which"*|*"where"*|*"list"*|*"show"*|*"registered"*|*"register"*|*"registry"*|*"path"*|*"paths"*|*"root"*|*"roots"*|*"namespace"*|*"namespaces"*|*"exist"*|*"exists"*|*"existing"*|*"current"*|*"setup"*|*"有哪些"*|*"哪里"*|*"路径"*|*"根"*|*"注册"*|*"现有"*|*"当前"*)
            has_inspection_cue="true"
            ;;
    esac

    if [[ "$has_subject" == "true" && "$has_inspection_cue" == "true" ]]; then
        return 0
    fi

    return 1
}

query_requests_existing_only() {
    local text
    text="$(lowercase "$1")"

    if [[ "$text" == *"existing"* || "$text" == *"currently exist"* || "$text" == *"still exist"* || "$text" == *"live"* || "$text" == *"valid"* || "$text" == *"当前"* && "$text" == *"存在"* || "$text" == *"现在"* && "$text" == *"存在"* || "$text" == *"仍然存在"* ]]; then
        return 0
    fi

    return 1
}

resolve_scope_and_namespace() {
    local resolved_scope="$scope"
    local resolved_namespace="$namespace"

    if [[ "$scope" == "auto" ]]; then
        if [[ "$namespace_explicit" == true ]]; then
            resolved_scope="global"
        elif [[ -n "$query" ]]; then
            local inferred_namespace
            local project_signals="false"
            inferred_namespace="$(infer_namespace_from_query "$query")"
            if query_has_project_signals "$query"; then
                project_signals="true"
            fi
            if [[ -n "$inferred_namespace" ]]; then
                resolved_namespace="$inferred_namespace"
                if [[ "$project_signals" == "true" ]]; then
                    resolved_scope="both"
                else
                    resolved_scope="global"
                fi
            else
                resolved_scope="project"
            fi
        else
            resolved_scope="project"
        fi
    fi

    printf '%s\t%s\n' "$resolved_scope" "$resolved_namespace"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --mode)
            mode="${2:-}"
            mode_explicit=true
            shift 2
            ;;
        --memory-system-view)
            memory_system_view="${2:-}"
            shift 2
            ;;
        --namespace)
            namespace="${2:-}"
            namespace_explicit=true
            shift 2
            ;;
        --query)
            query="${2:-}"
            shift 2
            ;;
        --type)
            search_type="$(normalize_type "${2:-}")"
            shift 2
            ;;
        --status)
            status_filter="${2:-}"
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
        --max-items)
            max_items="${2:-}"
            max_items_explicit=true
            shift 2
            ;;
        --max-hits)
            max_hits="${2:-}"
            shift 2
            ;;
        --deeper)
            deeper="${2:-}"
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

validate_one_of "scope" "$scope" auto project global both
validate_one_of "mode" "$mode" default memory-system project-registry
validate_one_of "memory-system-view" "$memory_system_view" auto overview project-registry
validate_one_of "deeper" "$deeper" true false

if [[ -n "$status_filter" ]]; then
    validate_one_of "status" "$status_filter" pending in_progress resolved wont_fix promoted_to_summary promoted_to_skill active archived moved
fi

if [[ ! "$max_items" =~ ^[0-9]+$ ]] || [[ "$max_items" -lt 1 ]]; then
    echo "--max-items must be a positive integer" >&2
    exit 1
fi

if [[ ! "$max_hits" =~ ^[0-9]+$ ]] || [[ "$max_hits" -lt 1 ]]; then
    echo "--max-hits must be a positive integer" >&2
    exit 1
fi

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
else
    project_memory_dir="$(resolve_project_memory_dir)"
fi

if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi

if [[ "$mode" == "project-registry" ]]; then
    mode="memory-system"
    if [[ "$memory_system_view" == "auto" ]]; then
        memory_system_view="project-registry"
    fi
fi

if [[ "$mode" == "memory-system" ]]; then
    include_project_registry="true"
    registry_only_recall="true"
    review_mode="memory-system"
    if [[ -n "$query" ]] && query_requests_existing_only "$query"; then
        registry_existing_only="true"
    fi
    if [[ -n "$query" ]] && query_is_project_registry_meta "$query" && [[ "$memory_system_view" == "auto" ]]; then
        memory_system_view="project-registry"
    elif [[ "$memory_system_view" == "auto" ]]; then
        memory_system_view="overview"
    fi
    if [[ "$max_items_explicit" == "true" ]]; then
        project_registry_max_items="$max_items"
    elif [[ "$memory_system_view" == "project-registry" ]]; then
        project_registry_max_items="all"
    else
        project_registry_max_items="$max_items"
    fi
elif [[ "$mode_explicit" != "true" && -n "$query" ]] && query_is_memory_system_meta "$query"; then
    include_project_registry="true"
    review_mode="memory-system"
    if query_requests_existing_only "$query"; then
        registry_existing_only="true"
    fi
    if query_is_project_registry_meta "$query"; then
        memory_system_view="project-registry"
    else
        memory_system_view="overview"
    fi
    if [[ "$max_items_explicit" == "true" ]]; then
        project_registry_max_items="$max_items"
    elif [[ "$memory_system_view" == "project-registry" ]]; then
        project_registry_max_items="all"
    else
        project_registry_max_items="$max_items"
    fi
    if [[ "$deeper" == "false" && -z "$search_type" && -z "$status_filter" ]]; then
        registry_only_recall="true"
    fi
fi

resolved_fields="$(resolve_scope_and_namespace)"
resolved_scope="${resolved_fields%%$'\t'*}"
resolved_namespace="${resolved_fields#*$'\t'}"
namespace="$resolved_namespace"

global_memory_dir=""
if [[ "$resolved_scope" == "global" || "$resolved_scope" == "both" ]]; then
    global_memory_dir="$(resolve_global_memory_dir)"
    self_improving_validate_memory_isolation_or_die "$project_memory_dir" "$global_memory_dir"
fi

review_args=(--scope "$resolved_scope" --project-root "$project_root" --max-items "$max_items")
review_args+=(--mode "$review_mode")
search_args=(--scope "$resolved_scope" --project-root "$project_root" --max-hits "$max_hits")

if [[ -n "$project_memory_dir" ]]; then
    review_args+=(--project-memory-dir "$project_memory_dir")
    search_args+=(--project-memory-dir "$project_memory_dir")
fi

if [[ "$resolved_scope" == "global" || "$resolved_scope" == "both" ]]; then
    review_args+=(--namespace "$namespace")
    search_args+=(--namespace "$namespace")
    if [[ -n "$global_memory_dir_override" ]]; then
        review_args+=(--global-memory-dir "$global_memory_dir_override")
        search_args+=(--global-memory-dir "$global_memory_dir_override")
    fi
fi

if [[ "$include_project_registry" == "true" ]]; then
    review_args+=(--memory-system-view "$memory_system_view" --registry-existing-only "$registry_existing_only" --project-registry-max-items "$project_registry_max_items")
fi

review_output="$(bash "$SCRIPT_DIR/review-memory.sh" "${review_args[@]}")"

include_search=false
if [[ -n "$query" || "$deeper" == "true" || -n "$search_type" || -n "$status_filter" ]]; then
    include_search=true
fi
if [[ "$include_project_registry" == "true" && "$deeper" == "false" && -z "$search_type" && -z "$status_filter" ]]; then
    include_search=false
fi

search_output=""
if [[ "$include_search" == true ]]; then
    [[ -n "$query" ]] && search_args+=(--query "$query")
    [[ -n "$search_type" ]] && search_args+=(--type "$search_type")
    [[ -n "$status_filter" ]] && search_args+=(--status "$status_filter")
    if [[ "$deeper" == "true" ]]; then
        search_args+=(--exhaustive true)
    fi
    search_output="$(bash "$SCRIPT_DIR/search-memory.sh" "${search_args[@]}")"
fi

echo "<memory-recall>"
printf 'Requested-Scope: %s\n' "$scope"
printf 'Resolved-Scope: %s\n' "$resolved_scope"
if [[ "$resolved_scope" == "global" || "$resolved_scope" == "both" ]]; then
    printf 'Resolved-Namespace: %s\n' "$namespace"
fi
if [[ -n "$query" ]]; then
    printf 'Query: %s\n' "$query"
fi
printf 'Deeper: %s\n' "$deeper"
echo "Summary-First: true"
echo "Review:"
printf '%s\n' "$review_output"
if [[ "$include_search" == true ]]; then
    echo "Search:"
    printf '%s\n' "$search_output"
fi
echo "</memory-recall>"
