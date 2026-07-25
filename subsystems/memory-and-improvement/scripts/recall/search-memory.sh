#!/bin/bash
# Search project and/or global memory with progressive-loading priority.

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
search_type=""
status_filter=""
pattern_key=""
query=""
max_hits=12
exhaustive="false"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--namespace NAME] [--type learning|error|feature_request|asset] [--status STATUS] [--pattern-key KEY] [--query TEXT] [--project-root PATH] [--project-memory-dir PATH] [--global-memory-dir PATH] [--max-hits N] [--exhaustive true|false]
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

matching_line_preview() {
    local file="$1"
    local query_text="$2"
    awk -v want="$(lowercase "$query_text")" '
        /^[[:space:]]*$/ { next }
        /^#/ { next }
        {
            raw=$0
            gsub(/^[[:space:]]*[-*][[:space:]]*/, "", raw)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
            if (raw == "") {
                next
            }
            low=tolower(raw)
            if (want == "" || index(low, want) > 0) {
                print raw
                exit
            }
        }
    ' "$file"
}

doc_hit() {
    local priority="$1"
    local scope_label="$2"
    local kind="$3"
    local file="$4"
    local entry_id="$5"

    [[ -f "$file" ]] || return 0
    [[ -z "$status_filter" ]] || return 0
    [[ -z "$pattern_key" ]] || return 0

    local preview=""
    preview="$(matching_line_preview "$file" "$query")"
    if [[ -z "$preview" ]]; then
        return 0
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$priority" "$scope_label" "$kind" "$file" "$entry_id" "$preview"
}

asset_hits() {
    local priority="$1"
    local scope_label="$2"
    local index_file="$3"

    [[ -f "$index_file" ]] || return 0
    [[ -z "$pattern_key" ]] || return 0

    awk \
        -v priority="$priority" \
        -v scope_label="$scope_label" \
        -v file_path="$index_file" \
        -v want_status="$status_filter" \
        -v want_query="$(lowercase "$query")" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function flush_asset(     text, preview, query_match) {
            if (id == "") {
                reset_asset()
                return
            }
            if (want_status != "" && status != want_status) {
                reset_asset()
                return
            }
            text = tolower(block)
            query_match = (want_query == "" || index(text, want_query) > 0 || index(tolower(title), want_query) > 0 || index(tolower(summary), want_query) > 0)
            if (!query_match) {
                reset_asset()
                return
            }
            preview = title
            if (summary != "" && summary != "none") {
                preview = summary
            } else if (canonical_path != "") {
                preview = canonical_path
            }
            print priority "\t" scope_label "\tasset\t" file_path "\t" id "\t" preview
            reset_asset()
        }
        function reset_asset() {
            id = ""
            title = ""
            summary = ""
            status = ""
            canonical_path = ""
            block = ""
        }
        BEGIN {
            reset_asset()
        }
        /^## \[/ {
            flush_asset()
            id = $0
            sub(/^## \[/, "", id)
            sub(/\].*$/, "", id)
            block = $0 "\n"
            next
        }
        {
            if (id != "") {
                block = block $0 "\n"
            }
        }
        /^\- Title: / { title = trim(substr($0, 10)); next }
        /^\- Summary: / { summary = trim(substr($0, 12)); next }
        /^\- Status: / { status = trim(substr($0, 11)); next }
        /^\- Canonical-Path: / { canonical_path = trim(substr($0, 19)); next }
        /^---[[:space:]]*$/ {
            flush_asset()
            next
        }
        END {
            flush_asset()
        }
    ' "$index_file"
}

entry_hits() {
    local priority="$1"
    local scope_label="$2"
    local type_label="$3"
    local file="$4"

    [[ -f "$file" ]] || return 0

    awk \
        -v priority="$priority" \
        -v scope_label="$scope_label" \
        -v type_label="$type_label" \
        -v file_path="$file" \
        -v want_status="$status_filter" \
        -v want_pattern="$pattern_key" \
        -v want_query="$(lowercase "$query")" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function flush_entry(     text, query_match) {
            if (id == "") {
                reset_entry()
                return
            }
            if (want_status != "" && status != want_status) {
                reset_entry()
                return
            }
            if (want_pattern != "" && pattern_key_value != want_pattern) {
                reset_entry()
                return
            }
            text = tolower(block)
            query_match = (want_query == "" || index(text, want_query) > 0 || index(tolower(summary), want_query) > 0)
            if (!query_match) {
                reset_entry()
                return
            }
            if (summary == "") {
                summary = "(no summary)"
            }
            print priority "\t" scope_label "\t" type_label "\t" file_path "\t" id "\t" summary
            reset_entry()
        }
        function reset_entry() {
            id = ""
            status = ""
            summary = ""
            pattern_key_value = ""
            block = ""
            in_summary = 0
        }
        BEGIN {
            reset_entry()
        }
        /^## \[/ {
            flush_entry()
            id = $0
            sub(/^## \[/, "", id)
            sub(/\].*$/, "", id)
            block = $0 "\n"
            next
        }
        {
            if (id != "") {
                block = block $0 "\n"
            }
        }
        /^\*\*Status\*\*: / {
            status = substr($0, 13)
            next
        }
        /^### (Summary|Requested Capability)$/ {
            in_summary = 1
            next
        }
        in_summary == 1 && summary == "" && $0 !~ /^[[:space:]]*$/ {
            summary = trim($0)
            in_summary = 0
            next
        }
        /^- Pattern-Key: / {
            pattern_key_value = trim(substr($0, 16))
            next
        }
        /^---[[:space:]]*$/ {
            flush_entry()
            next
        }
        END {
            flush_entry()
        }
    ' "$file"
}

collect_fact_hits() {
    local priority="$1"
    local scope_label="$2"
    local base_dir="$3"

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if [[ "$scope_label" == "project" ]]; then
            case "$(basename "$file")" in
                README.md|INIT.md|SUMMARY.md|SUMMARY_CANDIDATES.md|LEARNINGS.md|ERRORS.md|FEATURE_REQUESTS.md|REVIEW.md) continue ;;
            esac
        else
            case "$(basename "$file")" in
                README.md|INIT.md|SUMMARY.md|SUMMARY_CANDIDATES.md) continue ;;
            esac
        fi
        doc_hit "$priority" "$scope_label" fact "$file" "DOC-$(basename "$file" .md | tr '[:lower:]' '[:upper:]')"
    done < <(find "$base_dir" -maxdepth 1 -type f -name '*.md' | sort)
}

collect_layer_hits() {
    local layer="$1"
    local project_dir="$2"
    local global_dir="$3"
    local output=""

    case "$layer" in
        init)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        doc_hit 1 project init "$project_dir/INIT.md" "DOC-INIT"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        doc_hit 1 global init "${global_dir%/.learnings}/INIT.md" "DOC-INIT"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        summary)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        doc_hit 2 project summary "$project_dir/SUMMARY.md" "DOC-SUMMARY"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        doc_hit 2 global summary "${global_dir%/.learnings}/SUMMARY.md" "DOC-SUMMARY"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        fact)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        collect_fact_hits 3 project "$project_dir"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        collect_fact_hits 3 global "${global_dir%/.learnings}"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        review)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        doc_hit 4 project review "$project_dir/REVIEW.md" "DOC-REVIEW"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        doc_hit 4 global review "$global_dir/REVIEW.md" "DOC-REVIEW"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        raw)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        entry_hits 5 project learning "$project_dir/LEARNINGS.md"
                        entry_hits 5 project error "$project_dir/ERRORS.md"
                        entry_hits 5 project feature_request "$project_dir/FEATURE_REQUESTS.md"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        entry_hits 5 global learning "$global_dir/LEARNINGS.md"
                        entry_hits 5 global error "$global_dir/ERRORS.md"
                        entry_hits 5 global feature_request "$global_dir/FEATURE_REQUESTS.md"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        asset)
            output="$(
                {
                    if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                        asset_hits 6 project "$project_dir/assets/INDEX.md"
                    fi
                    if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                        asset_hits 6 global "${global_dir%/.learnings}/assets/INDEX.md"
                    fi
                } | awk 'NF > 0'
            )"
            ;;
        *)
            echo "Unknown layer: $layer" >&2
            exit 1
            ;;
    esac

    [[ -n "$output" ]] && printf '%s\n' "$output"
}

collect_type_hits() {
    local project_dir="$1"
    local global_dir="$2"

    case "$search_type" in
        learning)
            if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                entry_hits 5 project learning "$project_dir/LEARNINGS.md"
            fi
            if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                entry_hits 5 global learning "$global_dir/LEARNINGS.md"
            fi
            ;;
        error)
            if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                entry_hits 5 project error "$project_dir/ERRORS.md"
            fi
            if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                entry_hits 5 global error "$global_dir/ERRORS.md"
            fi
            ;;
        feature_request)
            if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                entry_hits 5 project feature_request "$project_dir/FEATURE_REQUESTS.md"
            fi
            if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                entry_hits 5 global feature_request "$global_dir/FEATURE_REQUESTS.md"
            fi
            ;;
        asset)
            if [[ "$scope" == "project" || "$scope" == "both" ]]; then
                asset_hits 6 project "$project_dir/assets/INDEX.md"
            fi
            if [[ "$scope" == "global" || "$scope" == "both" ]]; then
                asset_hits 6 global "${global_dir%/.learnings}/assets/INDEX.md"
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

collect_progressive_hits() {
    local project_dir="$1"
    local global_dir="$2"
    local layer_hits=""
    local aggregated=""

    if [[ -n "$search_type" ]]; then
        collect_type_hits "$project_dir" "$global_dir"
        return 0
    fi

    local layer
    for layer in init summary fact review raw asset; do
        layer_hits="$(collect_layer_hits "$layer" "$project_dir" "$global_dir")"
        if [[ -n "$layer_hits" ]]; then
            if [[ -n "$aggregated" ]]; then
                aggregated+=$'\n'
            fi
            aggregated+="$layer_hits"
            if [[ "$exhaustive" == "false" ]]; then
                break
            fi
        fi
    done

    if [[ -n "$aggregated" ]]; then
        printf '%s\n' "$aggregated"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --namespace)
            namespace="${2:-}"
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
        --pattern-key)
            pattern_key="${2:-}"
            shift 2
            ;;
        --query)
            query="${2:-}"
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
        --max-hits)
            max_hits="${2:-}"
            shift 2
            ;;
        --exhaustive)
            exhaustive="${2:-}"
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

validate_one_of "exhaustive" "$exhaustive" true false

if [[ -n "$status_filter" ]]; then
    validate_one_of "status" "$status_filter" pending in_progress resolved wont_fix promoted_to_summary promoted_to_skill active archived moved
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

global_memory_dir=""
if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    global_memory_dir="$(resolve_global_memory_dir)"
fi

if [[ -n "$global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$project_memory_dir" "$global_memory_dir"
fi

hits="$(
    collect_progressive_hits "$project_memory_dir" "$global_memory_dir" \
        | awk -F '\t' 'NF >= 6' \
        | head -n "$max_hits"
)"

echo "<memory-search>"
printf 'Scope: %s\n' "$scope"
if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    printf 'Namespace: %s\n' "$namespace"
fi
if [[ -n "$search_type" ]]; then
    printf 'Type: %s\n' "$search_type"
fi
if [[ -n "$status_filter" ]]; then
    printf 'Status: %s\n' "$status_filter"
fi
if [[ -n "$pattern_key" ]]; then
    printf 'Pattern-Key: %s\n' "$pattern_key"
fi
if [[ -n "$query" ]]; then
    printf 'Query: %s\n' "$query"
fi
printf 'Exhaustive: %s\n' "$exhaustive"

if [[ -z "$hits" ]]; then
    echo "Hits: none"
else
    echo "Hits:"
    while IFS=$'\t' read -r priority scope_label kind file entry_id preview; do
        printf -- '- [%s] %s %s %s :: %s\n' "$entry_id" "$scope_label" "$kind" "$file" "$preview"
    done <<< "$hits"
fi
echo "</memory-search>"
