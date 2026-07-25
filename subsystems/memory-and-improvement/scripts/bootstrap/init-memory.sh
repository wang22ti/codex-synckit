#!/bin/bash
# Initialize project and/or global memory directories for memory-and-improvement.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

scope="both"
project_root="$self_improving_project_root"
project_memory_dir="$self_improving_project_memory_dir"
project_memory_dir_overridden="$self_improving_project_memory_dir_overridden"
global_root="$self_improving_global_root"
global_namespaces_root="$self_improving_global_namespaces_root"
global_namespace="$self_improving_global_namespace"
global_memory_dir="$self_improving_global_memory_dir"
global_memory_dir_overridden="$self_improving_global_memory_dir_overridden"
default_global_namespaces="$self_improving_default_global_namespaces"
global_defaults=false
global_root_overridden=false

usage() {
    cat <<EOF
Usage: init-memory.sh [--scope project|global|both] [--project-root PATH] [--project-memory-dir PATH] [--global-root PATH] [--global-namespace NAME] [--global-memory-dir PATH] [--global-defaults]

Initializes memory files without overwriting existing content.

Defaults:
  --scope both
  --project-root $project_root
  --project-memory-dir <path-to-.learnings> overrides repo-root default
  --global-root $global_root
  --global-namespace $global_namespace
  --global-memory-dir <path-to-.learnings> overrides global root + namespace
  --global-defaults creates namespaces: $default_global_namespaces
EOF
}

normalize_path() {
    self_improving_absolutize_path "$1"
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
            project_memory_dir_overridden=true
            shift 2
            ;;
        --global-root)
            global_root="${2:-}"
            global_root_overridden=true
            shift 2
            ;;
        --global-namespace)
            global_namespace="${2:-}"
            shift 2
            ;;
        --global-memory-dir)
            global_memory_dir="${2:-}"
            global_memory_dir_overridden=true
            shift 2
            ;;
        --global-defaults)
            global_defaults=true
            shift
            ;;
        --help|-h)
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
        usage >&2
        exit 1
        ;;
esac

project_root="$(normalize_path "$project_root")"
if [[ "$project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$(normalize_path "$project_memory_dir")"
    if [[ "$project_memory_dir" != */.learnings ]]; then
        echo "--project-memory-dir must point to a .learnings directory" >&2
        exit 1
    fi
else
    project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root")"
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    global_root="$(normalize_path "$global_root")"
    global_namespace="${global_namespace#/}"
    global_namespace="${global_namespace%/}"
    if [[ "$global_defaults" != true && "$global_memory_dir_overridden" != true ]]; then
        self_improving_validate_namespace_or_die "$global_namespace"
    fi
    if [[ "$global_root_overridden" == true && -z "${SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT:-}" ]]; then
        global_namespaces_root="$(normalize_path "$global_root/namespaces")"
    else
        global_namespaces_root="$(normalize_path "$global_namespaces_root")"
    fi
    if [[ "$global_memory_dir_overridden" == true ]]; then
        global_memory_dir="$(normalize_path "$global_memory_dir")"
        if [[ "$global_memory_dir" != */.learnings ]]; then
            echo "--global-memory-dir must point to a .learnings directory" >&2
            exit 1
        fi
    else
        global_memory_dir="$global_namespaces_root/$global_namespace/.learnings"
    fi
fi

if [[ -n "$global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$project_memory_dir" "$global_memory_dir"
fi

create_file_if_missing() {
    local path="$1"
    local title="$2"
    local body="$3"
    if [[ ! -f "$path" ]]; then
        cat > "$path" <<EOF
# $title

$body

---
EOF
    fi
}

create_literal_file_if_missing() {
    local path="$1"
    local content="$2"
    if [[ ! -f "$path" ]]; then
        printf '%s\n' "$content" > "$path"
    fi
}

create_project_summary_if_missing() {
    local project_dir="$1"

    create_namespace_file_if_missing "$project_dir/SUMMARY.md" "# Project Summary

Load this file before opening detailed project memory when you want the shortest useful summary for this repository.

Use this file for repo facts, constraints, and distilled lessons.
Do not store repo-local agent instructions, prompt policy, or routing policy here; keep those in \`AGENTS.md\` or explicit repo config.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"
}

create_asset_index_if_missing() {
    local scope="$1"
    local memory_dir="$2"
    local assets_dir
    local files_dir
    local index_file

    assets_dir="$(self_improving_assets_dir_for_scope_and_memory_dir "$scope" "$memory_dir")"
    files_dir="$(self_improving_asset_files_dir_for_scope_and_memory_dir "$scope" "$memory_dir")"
    index_file="$(self_improving_asset_index_for_scope_and_memory_dir "$scope" "$memory_dir")"

    mkdir -p "$assets_dir" "$files_dir"
    create_namespace_file_if_missing "$index_file" "# Asset Index

Index durable artifacts here before opening the asset file itself.

- none indexed yet
"
}

init_memory_dir() {
    local dir="$1"
    local title_prefix="$2"
    local learnings_body="$3"
    local errors_body="$4"
    local features_body="$5"

    mkdir -p "$dir"
    create_file_if_missing "$dir/LEARNINGS.md" "$title_prefix Learnings" "$learnings_body"
    create_file_if_missing "$dir/ERRORS.md" "$title_prefix Errors" "$errors_body"
    create_file_if_missing "$dir/FEATURE_REQUESTS.md" "$title_prefix Feature Requests" "$features_body"
    create_literal_file_if_missing "$dir/.gitignore" "*.lock"
}

create_namespace_file_if_missing() {
    local path="$1"
    local content="$2"
    if [[ ! -f "$path" ]]; then
        cat > "$path" <<EOF
$content
EOF
    fi
}

init_global_root() {
    mkdir -p "$global_root"
    mkdir -p "$global_namespaces_root"
    create_namespace_file_if_missing "$global_root/README.md" "# Global Memory

This directory stores memory only.

Structure:

- \`namespaces/<namespace>/README.md\`: scope and routing for one namespace
- \`namespaces/<namespace>/INIT.md\`: cross-project guidance loaded once during session init
- \`namespaces/<namespace>/SUMMARY.md\`: short high-frequency facts or principles
- \`namespaces/<namespace>/assets/INDEX.md\`: asset discovery index for namespace-level artifacts
- \`namespaces/<namespace>/.learnings/*.md\`: detailed history
- namespace factual files such as \`PROFILE.md\` or \`RECORDS.md\`: durable structured facts
"
}

init_namespace() {
    local namespace="$1"
    local namespace_dir="$global_namespaces_root/$namespace"
    local readme_content
    local init_content
    local summary_content

    self_improving_validate_namespace_or_die "$namespace"

    mkdir -p "$namespace_dir"

    readme_content="# ${namespace} Memory

Namespace for cross-project memory relevant to ${namespace}.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"

    init_content="# ${namespace} Init

Load this file during session init when this namespace is relevant.

Use it for cross-project guidance, durable user preferences, and high-value operator context that should be seen early.
Repo-local instructions still belong in \`AGENTS.md\` inside the repository being worked on.

Initialization cues:
- none added yet
"

    summary_content="# ${namespace} Summary

Load this file before opening \`.learnings/\` when you want the shortest useful summary for this namespace.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"

    case "$namespace" in
        user-profile)
            readme_content="# User Profile Memory

Use this namespace for durable facts about the user as a person.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"
            create_namespace_file_if_missing "$namespace_dir/PROFILE.md" "# User Profile

Use this file for durable personal facts.
"
            ;;
        research-principle)
            readme_content="# Research Principle Memory

Use this namespace for cross-project research principles and writing heuristics.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"
            init_content="# research-principle Init

Load this file during session init when this namespace is relevant.

Use it for cross-project research principles and writing heuristics that should be seen early.
"
            summary_content="# Research Principle Summary

Load this file before opening \`.learnings/\` when you want the shortest useful summary for this namespace.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"
            ;;
        research-ops)
            readme_content="# Research Ops Memory

Use this namespace for cross-project research operations memory.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"
            init_content="# research-ops Init

Load this file during session init when this namespace is relevant.

Use it for cross-project research tooling, workflow lessons, and operational guidance that should be seen early.
"
            summary_content="# Research Ops Summary

Load this file before opening \`.learnings/\` when you want the shortest useful summary for this namespace.

Current high-priority operations memory:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"
            ;;
        research-history)
            readme_content="# Research History Memory

Use this namespace for factual records of research timelines, applications, submissions, grants, milestones, outcomes, and roles beyond one user's personal profile.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"
            init_content="# research-history Init

Load this file during session init when this namespace is relevant.

Use it for stable historical orientation only.
"
            summary_content="# Research History Summary

Load this file before opening \`.learnings/\` when you want the shortest useful summary for this namespace.

Current high-priority research-history facts:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"
            create_namespace_file_if_missing "$namespace_dir/RECORDS.md" "# Research History Records

Use this file for detailed factual records of research timelines, grants, applications, submissions, milestones, and outcomes.
"
            ;;
        project)
            readme_content="# Project Memory

Use this namespace for durable cross-project memory about long-running internal projects, tool systems, and framework evolution.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"
            create_namespace_file_if_missing "$namespace_dir/RECORDS.md" "# Project Records

Use this file for detailed factual records of long-lived internal project development, architecture changes, milestones, and outcomes.
"
            ;;
    esac

    create_namespace_file_if_missing "$namespace_dir/README.md" "$readme_content"
    create_namespace_file_if_missing "$namespace_dir/INIT.md" "$init_content"
    create_namespace_file_if_missing "$namespace_dir/SUMMARY.md" "$summary_content"

    init_memory_dir \
        "$namespace_dir/.learnings" \
        "$namespace" \
        "Cross-project corrections, insights, and stable best practices relevant to the $namespace namespace." \
        "Cross-project failures and tool gotchas relevant to the $namespace namespace." \
        "Requested capabilities that would improve workflows related to the $namespace namespace."
    create_asset_index_if_missing global "$namespace_dir/.learnings"

    printf 'Global memory: %s\n' "$namespace_dir/.learnings"
}

init_custom_global_memory() {
    local memory_dir="$1"
    local namespace_dir="${memory_dir%/.learnings}"
    local namespace_label

    namespace_label="$(basename "$namespace_dir")"
    mkdir -p "$namespace_dir"

    create_namespace_file_if_missing "$namespace_dir/README.md" "# ${namespace_label} Memory

Namespace for cross-project memory relevant to ${namespace_label}.

Use \`assets/INDEX.md\` for namespace-level artifact discovery.
"

    create_namespace_file_if_missing "$namespace_dir/INIT.md" "# ${namespace_label} Init

Load this file during session init when this namespace is relevant.

Use it for cross-project guidance, durable user preferences, and high-value operator context that should be seen early.
Repo-local instructions still belong in \`AGENTS.md\` inside the repository being worked on.

Initialization cues:
- none added yet
"

    create_namespace_file_if_missing "$namespace_dir/SUMMARY.md" "# ${namespace_label} Summary

Load this file before opening \`.learnings/\` when you want the shortest useful summary for this namespace.

Current high-priority principles:
- none recorded yet

## Auto Promoted Summary

<!-- memory-auto-summary:start -->
- none promoted yet
<!-- memory-auto-summary:end -->
"

    init_memory_dir \
        "$memory_dir" \
        "$namespace_label" \
        "Cross-project corrections, insights, and stable best practices relevant to the ${namespace_label} namespace." \
        "Cross-project failures and tool gotchas relevant to the ${namespace_label} namespace." \
        "Requested capabilities that would improve workflows related to the ${namespace_label} namespace."
    create_asset_index_if_missing global "$memory_dir"

    printf 'Global memory: %s\n' "$memory_dir"
}

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    init_memory_dir \
        "$project_memory_dir" \
        "Project" \
        "Project-specific corrections, insights, and stable best practices captured during work in this repository." \
        "Project-specific command failures, integration issues, and local debugging notes." \
        "Requested capabilities and workflow improvements relevant to this repository."
    create_project_summary_if_missing "$project_memory_dir"
    create_asset_index_if_missing project "$project_memory_dir"
    self_improving_register_project_memory_dir "$project_memory_dir"
    printf 'Project memory: %s\n' "$project_memory_dir"
fi

if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    init_global_root
    if [[ "$global_memory_dir_overridden" == true ]]; then
        init_custom_global_memory "$global_memory_dir"
    elif [[ "$global_defaults" == true ]]; then
        for namespace in $default_global_namespaces; do
            init_namespace "$namespace"
        done
    else
        init_namespace "${global_namespace:-research}"
    fi
fi
