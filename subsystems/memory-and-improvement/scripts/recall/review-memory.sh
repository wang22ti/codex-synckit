#!/bin/bash
# Print a concise memory snapshot for the current project and/or global namespace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="both"
mode="default"
memory_system_view="auto"
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
max_items=3
include_entries="auto"
registry_existing_only="false"
project_registry_max_items="3"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--mode default|memory-system|project-registry] [--memory-system-view auto|overview|project-registry] [--namespace NAME] [--project-root PATH] [--project-memory-dir PATH] [--global-memory-dir PATH] [--max-items N] [--include-entries auto|true|false] [--registry-existing-only true|false] [--project-registry-max-items N|all]
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

print_asset_items() {
    local scope="$1"
    local memory_dir="$2"
    local limit="$3"
    local index_file

    index_file="$(self_improving_asset_index_for_scope_and_memory_dir "$scope" "$memory_dir")"
    [[ -f "$index_file" ]] || return 0

    awk -v limit="$limit" '
        /^## \[/ {
            id=$0
            sub(/^## \[/, "", id)
            sub(/\].*$/, "", id)
            title=""
            type=""
            status=""
            next
        }
        /^\- Title: / { title=substr($0, 10); next }
        /^\- Type: / { type=substr($0, 9); next }
        /^\- Status: / { status=substr($0, 11); next }
        /^---[[:space:]]*$/ {
            if (id != "" && status != "archived") {
                printf "- [%s] %s: %s\n", id, type, title
                count++
                if (count >= limit) {
                    exit
                }
            }
            id=""
        }
        END {
            if (id != "" && status != "archived" && count < limit) {
                printf "- [%s] %s: %s\n", id, type, title
            }
        }
    ' "$index_file"
}

print_summary_preview() {
    local file="$1"
    local lines="$2"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    awk -v max_lines="$lines" '
        NR <= 2 { next }
        /^[[:space:]]*$/ { next }
        /^Load this file before opening/ { next }
        /^Load this file when/ { next }
        /^Use this file for repo facts, constraints, and distilled lessons\.$/ { next }
        /^Do not store repo-local agent instructions, prompt policy, or routing policy here; keep those in `AGENTS.md` or explicit repo config\.$/ { next }
        /^Current high-priority .*:$/ { next }
        /^Keep only stable, high-frequency memory here\./ { next }
        /^- none promoted yet$/ { next }
        /^- none recorded yet$/ { next }
        /^<!-- memory-auto-summary:/ { next }
        /^## Auto Promoted Summary$/ { next }
        {
            line=$0
            sub(/^- /, "", line)
            print "- " line
            count++
            if (count >= max_lines) {
                exit
            }
        }
    ' "$file"
}

print_review_preview() {
    local file="$1"
    local lines="$2"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    awk -v max_lines="$lines" '
        /^[[:space:]]*$/ { next }
        /^# / { next }
        /^\*\*Memory Dir\*\*: / { next }
        /^## / {
            line=substr($0, 4)
            print "- " line
            count++
            if (count >= max_lines) {
                exit
            }
            next
        }
        {
            line=$0
            sub(/^- /, "", line)
            print "- " line
            count++
            if (count >= max_lines) {
                exit
            }
        }
    ' "$file"
}

print_pending_items() {
    local dir="$1"
    local limit="$2"

    parse_entries "$dir" \
        | awk -F '\t' '($3 == "high" || $3 == "critical") && $4 == "pending" { print $1 "\t" $3 "\t" $5 }' \
        | head -n "$limit" \
        | while IFS=$'\t' read -r id priority summary; do
        printf -- "- [%s] %s: %s\n" "$id" "$priority" "$summary"
    done
}

print_recent_items() {
    local dir="$1"
    local limit="$2"

    parse_entries "$dir" \
        | awk -F '\t' -v status_re="$self_improving_review_visible_status_regex" '($4 ~ status_re) { print $2 "\t" $1 "\t" $3 "\t" $4 "\t" $5 }' \
        | sort -r \
        | head -n "$limit" \
        | while IFS=$'\t' read -r logged id priority status summary; do
            printf -- "- [%s] %s, %s: %s\n" "$id" "$priority" "$status" "$summary"
        done
}

print_registered_project_memories() {
    local limit="$1"
    local existing_only="$2"
    local count=0
    local memory_dir

    while IFS= read -r memory_dir; do
        [[ -n "$memory_dir" ]] || continue
        if [[ "$existing_only" == "true" && ! -d "$memory_dir" ]]; then
            continue
        fi
        printf -- "- %s\n" "$memory_dir"
        count=$((count + 1))
        if [[ "$limit" != "all" && "$count" -ge "$limit" ]]; then
            break
        fi
    done < <(self_improving_list_registered_project_memory_dirs)
}

print_existing_global_namespaces() {
    local limit="$1"
    local count=0
    local namespace_dir

    [[ -d "$self_improving_global_namespaces_root" ]] || return 0

    while IFS= read -r namespace_dir; do
        [[ -n "$namespace_dir" ]] || continue
        printf -- "- %s\n" "$(basename "$namespace_dir")"
        count=$((count + 1))
        if [[ "$limit" != "all" && "$count" -ge "$limit" ]]; then
            break
        fi
    done < <(find "$self_improving_global_namespaces_root" -mindepth 1 -maxdepth 1 -type d | sort)
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --mode)
            mode="${2:-}"
            shift 2
            ;;
        --memory-system-view)
            memory_system_view="${2:-}"
            shift 2
            ;;
        --namespace)
            namespace="${2:-}"
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
            shift 2
            ;;
        --include-entries)
            include_entries="${2:-}"
            shift 2
            ;;
        --registry-existing-only)
            registry_existing_only="${2:-}"
            shift 2
            ;;
        --project-registry-max-items)
            project_registry_max_items="${2:-}"
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

validate_one_of "include_entries" "$include_entries" auto true false
validate_one_of "mode" "$mode" default memory-system project-registry
validate_one_of "memory-system-view" "$memory_system_view" auto overview project-registry
validate_one_of "registry-existing-only" "$registry_existing_only" true false
if [[ "$project_registry_max_items" != "all" ]]; then
    if [[ ! "$project_registry_max_items" =~ ^[0-9]+$ ]] || [[ "$project_registry_max_items" -lt 1 ]]; then
        echo "--project-registry-max-items must be a positive integer or 'all'" >&2
        exit 1
    fi
fi

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
else
    project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" || "$scope" == "both" || "$mode" == "memory-system" || "$mode" == "project-registry" ]]; then
    global_memory_dir="$(resolve_global_memory_dir)"
fi
if [[ -n "$global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$project_memory_dir" "$global_memory_dir"
fi
global_namespace_dir="${global_memory_dir%/.learnings}"

if [[ "$mode" == "project-registry" ]]; then
    mode="memory-system"
    if [[ "$memory_system_view" == "auto" ]]; then
        memory_system_view="project-registry"
    fi
fi
if [[ "$mode" == "memory-system" && "$memory_system_view" == "auto" ]]; then
    memory_system_view="overview"
fi

echo "<memory-review>"

if [[ "$mode" == "memory-system" ]]; then
    echo "Memory system:"
    printf -- "- Project root: %s\n" "$project_root"
    printf -- "- Project memory: %s\n" "$project_memory_dir"
    printf -- "- Project memory registry: %s\n" "$self_improving_project_registry_file"
    printf -- "- Global root: %s\n" "$self_improving_global_root"
    printf -- "- Global namespaces root: %s\n" "$self_improving_global_namespaces_root"
    printf -- "- Active global namespace: %s\n" "$namespace"
    if [[ -n "$global_memory_dir" ]]; then
        printf -- "- Active global memory dir: %s\n" "$global_memory_dir"
    fi
fi

if [[ "$mode" == "memory-system" && "$memory_system_view" == "overview" ]]; then
    existing_global_namespaces="$(print_existing_global_namespaces "$max_items")"
    echo "Existing global namespaces:"
    if [[ -n "$existing_global_namespaces" ]]; then
        printf '%s\n' "$existing_global_namespaces"
    else
        echo "- none found"
    fi
fi

if [[ "$mode" == "memory-system" && ( "$memory_system_view" == "project-registry" || "$memory_system_view" == "overview" ) ]]; then
    registered_project_memories="$(print_registered_project_memories "$project_registry_max_items" "$registry_existing_only")"
    if [[ "$registry_existing_only" == "true" ]]; then
        echo "Registered existing project memories:"
    else
        echo "Registered project memories:"
    fi
    if [[ -n "$registered_project_memories" ]]; then
        printf '%s\n' "$registered_project_memories"
    else
        echo "- none found"
    fi
fi

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    if [[ "$mode" == "memory-system" ]]; then
        :
    else
    echo "Project memory: $project_memory_dir"
    project_summary_preview=""
    if [[ -f "$project_memory_dir/SUMMARY.md" ]]; then
        echo "Project summary highlights:"
        project_summary_preview="$(print_summary_preview "$project_memory_dir/SUMMARY.md" "$max_items")"
        if [[ -n "$project_summary_preview" ]]; then
            printf '%s\n' "$project_summary_preview"
        else
            echo "- none promoted yet"
        fi
    fi
    project_review_preview="$(print_review_preview "$project_memory_dir/REVIEW.md" "$max_items")"
    if [[ -n "$project_review_preview" ]]; then
        echo "Project review highlights:"
        printf '%s\n' "$project_review_preview"
    fi
    project_include_entries="$include_entries"
    if [[ "$project_include_entries" == "auto" ]]; then
        if [[ -n "$project_summary_preview" || -n "$project_review_preview" ]]; then
            project_include_entries="false"
        else
            project_include_entries="true"
        fi
    fi
    if [[ "$project_include_entries" == "true" ]]; then
        project_items="$(print_pending_items "$project_memory_dir" "$max_items")"
        if [[ -n "$project_items" ]]; then
            echo "Project pending high-priority items:"
            printf '%s\n' "$project_items"
        else
            recent_project_items="$(print_recent_items "$project_memory_dir" "$max_items")"
            if [[ -n "$recent_project_items" ]]; then
                echo "Project recent visible items:"
                printf '%s\n' "$recent_project_items"
            fi
        fi
    fi
    project_assets="$(print_asset_items project "$project_memory_dir" "$max_items")"
    if [[ -n "$project_assets" ]]; then
        echo "Project indexed assets:"
        printf '%s\n' "$project_assets"
    fi
    fi
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    if [[ "$mode" == "memory-system" ]]; then
        :
    else
    echo "Global memory: $global_memory_dir"
    global_summary_preview=""
    if [[ -f "$global_namespace_dir/SUMMARY.md" ]]; then
        echo "Global summary highlights:"
        global_summary_preview="$(print_summary_preview "$global_namespace_dir/SUMMARY.md" "$max_items")"
        if [[ -n "$global_summary_preview" ]]; then
            printf '%s\n' "$global_summary_preview"
        else
            echo "- none promoted yet"
        fi
    fi
    global_review_preview="$(print_review_preview "$global_memory_dir/REVIEW.md" "$max_items")"
    if [[ -n "$global_review_preview" ]]; then
        echo "Global review highlights:"
        printf '%s\n' "$global_review_preview"
    fi
    global_include_entries="$include_entries"
    if [[ "$global_include_entries" == "auto" ]]; then
        if [[ -n "$global_summary_preview" || -n "$global_review_preview" ]]; then
            global_include_entries="false"
        else
            global_include_entries="true"
        fi
    fi
    if [[ "$global_include_entries" == "true" ]]; then
        global_items="$(print_pending_items "$global_memory_dir" "$max_items")"
        if [[ -n "$global_items" ]]; then
            echo "Global pending high-priority items:"
            printf '%s\n' "$global_items"
        else
            recent_global_items="$(print_recent_items "$global_memory_dir" "$max_items")"
            if [[ -n "$recent_global_items" ]]; then
                echo "Global recent visible items:"
                printf '%s\n' "$recent_global_items"
            fi
        fi
    fi
    global_assets="$(print_asset_items global "$global_memory_dir" "$max_items")"
    if [[ -n "$global_assets" ]]; then
        echo "Global indexed assets:"
        printf '%s\n' "$global_assets"
    fi
    fi
fi

echo "</memory-review>"
