#!/bin/bash
# Index durable artifacts for project or global memory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
. "$SCRIPT_ROOT/shared/file-lock.sh"

scope="project"
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
title=""
asset_type="other"
canonical_path=""
source="conversation"
summary="none"
tags="none"
related_memory_ids="none"
status="active"

usage() {
    cat <<EOF
Usage: $(basename "$0") --scope project|global --title TEXT --canonical-path PATH [options]
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

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
}

next_asset_id() {
    local file="$1"
    local today="$2"
    local last="0"

    if [[ -f "$file" ]]; then
        last="$(
            self_improving_extract_matches "AST-${today}-[0-9]{3}" "$file" \
            | sed -E "s/^AST-${today}-//" \
            | sort -n \
            | tail -1
        )"
    fi

    [[ -n "$last" ]] || last="0"
    printf 'AST-%s-%03d\n' "$today" "$((10#$last + 1))"
}

ensure_memory_initialized() {
    if [[ "$scope" == "project" ]]; then
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

find_existing_asset_id() {
    local index_file="$1"
    local wanted_path="$2"
    awk -v wanted="$wanted_path" '
        /^## \[/ {
            id=$0
            sub(/^## \[/, "", id)
            sub(/\].*$/, "", id)
        }
        /^\- Canonical-Path: / {
            path=substr($0, 19)
            if (path == wanted) {
                print id
                exit
            }
        }
    ' "$index_file"
}

update_existing_asset() {
    local index_file="$1"
    local wanted_path="$2"
    local logged="$3"
    local new_title="$4"
    local new_type="$5"
    local new_scope="$6"
    local new_namespace="$7"
    local new_source="$8"
    local new_summary="$9"
    local new_tags="${10}"
    local new_related="${11}"
    local new_status="${12}"

    WANTED_PATH="$wanted_path" \
    LOGGED="$logged" \
    NEW_TITLE="$new_title" \
    NEW_TYPE="$new_type" \
    NEW_SCOPE="$new_scope" \
    NEW_NAMESPACE="$new_namespace" \
    NEW_SOURCE="$new_source" \
    NEW_SUMMARY="$new_summary" \
    NEW_TAGS="$new_tags" \
    NEW_RELATED="$new_related" \
    NEW_STATUS="$new_status" \
    perl -0pi -e '
        my $wanted = quotemeta($ENV{WANTED_PATH});
        my @parts = split(/^---\n/m, $_, -1);
        for my $part (@parts) {
            next unless $part =~ /(?:^|\n)- Canonical-Path: $wanted(?:\n|$)/m;
            $part =~ s{((?:^|\n)- Logged: )[^\n]+}{$1 . $ENV{LOGGED}}em;
            $part =~ s{((?:^|\n)- Title: )[^\n]+}{$1 . $ENV{NEW_TITLE}}em;
            $part =~ s{((?:^|\n)- Type: )[^\n]+}{$1 . $ENV{NEW_TYPE}}em;
            $part =~ s{((?:^|\n)- Scope: )[^\n]+}{$1 . $ENV{NEW_SCOPE}}em;
            $part =~ s{((?:^|\n)- Namespace: )[^\n]+}{$1 . $ENV{NEW_NAMESPACE}}em;
            $part =~ s{((?:^|\n)- Source: )[^\n]+}{$1 . $ENV{NEW_SOURCE}}em;
            $part =~ s{((?:^|\n)- Summary: )[^\n]+}{$1 . $ENV{NEW_SUMMARY}}em;
            $part =~ s{((?:^|\n)- Tags: )[^\n]+}{$1 . $ENV{NEW_TAGS}}em;
            $part =~ s{((?:^|\n)- Related-Memory-IDs: )[^\n]+}{$1 . $ENV{NEW_RELATED}}em;
            $part =~ s{((?:^|\n)- Status: )[^\n]+}{$1 . $ENV{NEW_STATUS}}em;
        }
        $_ = join("---\n", @parts);
    ' "$index_file"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope) scope="${2:-}"; shift 2 ;;
        --namespace) namespace="${2:-}"; shift 2 ;;
        --project-root) project_root="${2:-}"; shift 2 ;;
        --project-memory-dir) project_memory_dir="${2:-}"; shift 2 ;;
        --global-memory-dir) global_memory_dir_override="${2:-}"; shift 2 ;;
        --title) title="${2:-}"; shift 2 ;;
        --type) asset_type="${2:-}"; shift 2 ;;
        --canonical-path) canonical_path="${2:-}"; shift 2 ;;
        --source) source="${2:-}"; shift 2 ;;
        --summary) summary="${2:-}"; shift 2 ;;
        --tags) tags="${2:-}"; shift 2 ;;
        --related-memory-ids) related_memory_ids="${2:-}"; shift 2 ;;
        --status) status="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$scope" in
    project|global) ;;
    *)
        echo "Invalid scope: $scope" >&2
        exit 1
        ;;
esac

validate_one_of "type" "$asset_type" paper_pdf supplementary_pdf slide_deck figure_source screenshot report_pdf dataset_snapshot structured_fact_file other
validate_one_of "source" "$source" conversation user_feedback automation import
validate_one_of "status" "$status" active archived moved

[[ -n "$title" ]] || { echo "--title is required" >&2; exit 1; }
[[ -n "$canonical_path" ]] || { echo "--canonical-path is required" >&2; exit 1; }

project_root="$(self_improving_normalize_path "$project_root")"
canonical_path="$(self_improving_normalize_path "$canonical_path")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi

if [[ "$scope" == "project" ]]; then
    memory_dir="$(resolve_project_memory_dir)"
    namespace_label="project"
else
    memory_dir="$(resolve_global_memory_dir)"
    namespace_label="$namespace"
fi

ensure_memory_initialized

index_file="$(self_improving_asset_index_for_scope_and_memory_dir "$scope" "$memory_dir")"
scope_lock_file="$memory_dir/.memory-write.lock"
self_improving_lock_acquire asset_scope "$scope_lock_file" 8

lock_file="$index_file.lock"
self_improving_lock_acquire asset_file "$lock_file" 9

logged="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

existing_id="$(find_existing_asset_id "$index_file" "$canonical_path")"
if [[ -n "$existing_id" ]]; then
    update_existing_asset "$index_file" "$canonical_path" "$logged" "$title" "$asset_type" "$scope" "$namespace_label" "$source" "$summary" "$tags" "$related_memory_ids" "$status"
    self_improving_lock_release asset_file
    self_improving_lock_release asset_scope
    printf 'Updated %s in %s\n' "$existing_id" "$index_file"
    exit 0
fi

today="$(date -u +%Y%m%d)"
asset_id="$(next_asset_id "$index_file" "$today")"
if grep -Fxq -- "- none indexed yet" "$index_file" 2>/dev/null; then
    perl -0pi -e 's/^- none indexed yet\n//m' "$index_file"
fi

cat >> "$index_file" <<EOF

## [$asset_id] $asset_type

- Logged: $logged
- Title: $title
- Type: $asset_type
- Scope: $scope
- Namespace: $namespace_label
- Canonical-Path: $canonical_path
- Source: $source
- Summary: $summary
- Tags: $tags
- Related-Memory-IDs: $related_memory_ids
- Status: $status

---
EOF

self_improving_lock_release asset_file
self_improving_lock_release asset_scope

printf 'Appended %s to %s\n' "$asset_id" "$index_file"
