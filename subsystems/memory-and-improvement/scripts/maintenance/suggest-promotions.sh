#!/bin/bash
# Suggest likely promotion targets without editing memory files.

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
limit=8
output_format="text"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--namespace NAME] [--project-root PATH] [--project-memory-dir PATH] [--global-memory-dir PATH] [--limit N|all] [--format text|tsv]
EOF
}

resolve_global_memory_dir() {
    self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override"
}

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
}

validate_scope() {
    case "$1" in
        project|global|both) ;;
        *)
            printf 'Invalid scope: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

validate_format() {
    case "$1" in
        text|tsv) ;;
        *)
            printf 'Invalid format: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

trim() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

age_days_from_logged() {
    local logged="$1"
    local logged_epoch
    local now_epoch

    if ! logged_epoch="$(date -u -d "$logged" +%s 2>/dev/null)"; then
        printf '999\n'
        return 0
    fi
    now_epoch="$(date -u +%s)"
    printf '%s\n' "$(((now_epoch - logged_epoch) / 86400))"
}

infer_factual_destination() {
    local text
    text="$(lowercase "$1")"

    if [[ "$text" == *"funding"* || "$text" == *"grant"* || "$text" == *"fellowship"* || "$text" == *"award"* || "$text" == *"support program"* ]]; then
        printf 'FUNDING_HISTORY.md\n'
    elif [[ "$text" == *"publication"* || "$text" == *"paper"* || "$text" == *"preprint"* || "$text" == *"author"* || "$text" == *"citation"* ]]; then
        printf 'PUBLICATIONS.md\n'
    elif [[ "$text" == *"profile"* || "$text" == *"preferred name"* || "$text" == *"bio"* || "$text" == *"contact"* || "$text" == *"preference"* ]]; then
        printf 'PROFILE.md\n'
    elif [[ "$text" == *"affiliation"* || "$text" == *"advisor"* || "$text" == *"research interest"* || "$text" == *"position"* || "$text" == *"degree"* || "$text" == *"academic"* ]]; then
        printf 'ACADEMIC_PROFILE.md\n'
    else
        printf 'RECORDS.md\n'
    fi
}

factual_file_exists() {
    local memory_dir="$1"
    local target="$2"
    local namespace_dir

    namespace_dir="${memory_dir%/.learnings}"
    [[ -f "$namespace_dir/$target" ]]
}

classify_candidate() {
    local scope_label="$1"
    local type_label="$2"
    local memory_dir="$3"
    local id="$4"
    local logged="$5"
    local priority="$6"
    local status="$7"
    local heading="$8"
    local summary="$9"
    local recurrence="${10}"
    local body="${11}"

    local text age_days procedural_score factual_score destination classification reason rank effective_recurrence
    local low_summary low_body
    local review_hint="${12}"
    local summary_candidate_hint="${13}"

    low_summary="$(lowercase "$summary")"
    low_body="$(lowercase "$body")"
    text="$low_summary $low_body"
    age_days="$(age_days_from_logged "$logged")"
    effective_recurrence="$recurrence"
    if [[ "$review_hint" == "true" ]]; then
        effective_recurrence=$((effective_recurrence + 1))
    fi
    procedural_score=0
    factual_score=0

    [[ "$text" == *"workflow"* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"checklist"* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"step"* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"then "* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"before "* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"after "* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"always "* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"validate"* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"regenerate"* ]] && procedural_score=$((procedural_score + 1))
    [[ "$text" == *"run "* ]] && procedural_score=$((procedural_score + 1))

    [[ "$text" == *"profile"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"preferred name"* ]] && factual_score=$((factual_score + 2))
    [[ "$text" == *"preference"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"publication"* ]] && factual_score=$((factual_score + 2))
    [[ "$text" == *"funding"* ]] && factual_score=$((factual_score + 2))
    [[ "$text" == *"grant"* ]] && factual_score=$((factual_score + 2))
    [[ "$text" == *"fellowship"* ]] && factual_score=$((factual_score + 2))
    [[ "$text" == *"award"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"affiliation"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"degree"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"record"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"history"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"submitted"* ]] && factual_score=$((factual_score + 1))
    [[ "$text" == *"under review"* ]] && factual_score=$((factual_score + 1))

    classification="keep_raw"
    destination="$(basename "$memory_dir") history"
    rank=4
    reason="recent, tentative, or better kept as chronology/evidence"

    if [[ "$text" == *"tentative"* || "$text" == *"investigate"* || "$text" == *"maybe "* || "$text" == *"might "* || "$text" == *"temporary"* || "$text" == *"for now"* ]]; then
        classification="keep_raw"
        destination=".learnings/*.md"
        rank=4
        reason="contains tentative or time-local language"
    elif [[ "$age_days" -lt 7 && "$recurrence" -lt 2 ]]; then
        classification="keep_raw"
        destination=".learnings/*.md"
        rank=4
        reason="too recent to justify promotion without recurrence"
    elif [[ "$procedural_score" -ge 3 && "$type_label" == "learning" ]]; then
        classification="consider_skill"
        destination="skill candidate under ~/.codex/skills/"
        rank=3
        reason="looks like a reusable workflow or checklist"
    elif [[ "$summary_candidate_hint" == "true" && "$type_label" == "learning" ]]; then
        classification="promote_to_summary"
        destination="SUMMARY.md"
        rank=1
        reason="listed in SUMMARY_CANDIDATES.md as a likely summary-layer item"
    elif [[ "$factual_score" -ge 2 && "$type_label" == "learning" ]]; then
        local factual_destination
        factual_destination="$(infer_factual_destination "$text")"
        if factual_file_exists "$memory_dir" "$factual_destination"; then
            classification="promote_to_factual_file"
            destination="$factual_destination"
            rank=2
            reason="stable factual content matches an existing structured factual file"
        elif [[ "$scope_label" == "global" ]]; then
            classification="promote_to_factual_file"
            destination="$factual_destination"
            rank=2
            reason="stable factual content is likely easier to load from a structured factual file"
        fi
    elif [[ "$effective_recurrence" -ge 2 || "$priority" == "high" || "$priority" == "critical" ]]; then
        classification="promote_to_summary"
        destination="SUMMARY.md"
        rank=1
        reason="recurrent, review-visible, or high-priority item would help as a short loading hint"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$scope_label" "$classification" "$destination" "$id" "$summary" "$reason" "$type_label" "$recurrence" "$status"
}

file_mentions_id() {
    local file="$1"
    local id="$2"

    [[ -f "$file" ]] || return 1
    grep -Fq -- "[$id]" "$file"
}

file_mentions_summary() {
    local file="$1"
    local summary="$2"

    [[ -f "$file" ]] || return 1
    grep -Fq -- "$summary" "$file"
}

scan_entry_file() {
    local scope_label="$1"
    local memory_dir="$2"
    local type_label="$3"
    local file="$4"

    [[ -f "$file" ]] || return 0

    awk -v file_path="$file" -v type_label="$type_label" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function emit() {
            if (id != "" && summary != "") {
                gsub(/\t/, " ", block)
                print id "\t" logged "\t" priority "\t" status "\t" heading "\t" summary "\t" recurrence "\t" trim(block)
            }
        }
        function reset() {
            id = ""
            logged = ""
            priority = ""
            status = ""
            heading = ""
            summary = ""
            recurrence = "0"
            block = ""
            in_summary = 0
        }
        BEGIN {
            reset()
        }
        /^## \[/ {
            emit()
            reset()
            id = $0
            sub(/^## \[/, "", id)
            heading = $0
            sub(/^## \[[^]]+\][[:space:]]*/, "", heading)
            sub(/\].*$/, "", id)
            block = $0
            next
        }
        {
            if (id != "") {
                if (block != "") {
                    block = block " "
                }
                block = block $0
            }
        }
        /^\*\*Logged\*\*: / { logged = substr($0, 13); next }
        /^\*\*Priority\*\*: / { priority = substr($0, 15); next }
        /^\*\*Status\*\*: / { status = substr($0, 13); next }
        /^### (Summary|Requested Capability)$/ { in_summary = 1; next }
        in_summary == 1 && summary == "" && $0 !~ /^[[:space:]]*$/ {
            summary = trim($0)
            in_summary = 0
            next
        }
        /^- Recurrence-Count: / { recurrence = substr($0, 21); next }
        /^---[[:space:]]*$/ {
            emit()
            reset()
            next
        }
        END {
            emit()
        }
    ' "$file" \
        | while IFS=$'\t' read -r id logged priority status heading summary recurrence body; do
            local review_hint="false"
            local summary_candidate_hint="false"
            if file_mentions_id "$memory_dir/REVIEW.md" "$id"; then
                review_hint="true"
            fi
            if file_mentions_id "$memory_dir/SUMMARY_CANDIDATES.md" "$id" || file_mentions_summary "$memory_dir/SUMMARY_CANDIDATES.md" "$summary"; then
                summary_candidate_hint="true"
            fi
            classify_candidate "$scope_label" "$type_label" "$memory_dir" "$id" "$logged" "$priority" "$status" "$heading" "$summary" "$recurrence" "$body" "$review_hint" "$summary_candidate_hint"
        done
}

collect_scope_candidates() {
    local scope_label="$1"
    local memory_dir="$2"

    [[ -d "$memory_dir" ]] || return 0

    scan_entry_file "$scope_label" "$memory_dir" learning "$memory_dir/LEARNINGS.md"
    scan_entry_file "$scope_label" "$memory_dir" error "$memory_dir/ERRORS.md"
    scan_entry_file "$scope_label" "$memory_dir" feature_request "$memory_dir/FEATURE_REQUESTS.md"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope) scope="${2:-}"; shift 2 ;;
        --namespace) namespace="${2:-}"; shift 2 ;;
        --project-root) project_root="${2:-}"; shift 2 ;;
        --project-memory-dir) project_memory_dir="${2:-}"; shift 2 ;;
        --global-memory-dir) global_memory_dir_override="${2:-}"; shift 2 ;;
        --limit) limit="${2:-}"; shift 2 ;;
        --format) output_format="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

validate_scope "$scope"
validate_format "$output_format"
if [[ "$limit" != "all" ]]; then
    [[ "$limit" =~ ^[0-9]+$ ]] || { printf 'Invalid limit: %s\n' "$limit" >&2; exit 1; }
    ((limit > 0)) || { printf 'Limit must be positive\n' >&2; exit 1; }
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

tmp_file="$(mktemp "${TMPDIR:-/tmp}/suggest-promotions.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

if [[ "$scope" == "project" || "$scope" == "both" ]]; then
    collect_scope_candidates "project" "$project_memory_dir" >> "$tmp_file"
fi
if [[ "$scope" == "global" || "$scope" == "both" ]]; then
    collect_scope_candidates "global" "$global_memory_dir" >> "$tmp_file"
fi

sorted_output="$(sort -t $'\t' -k1,1n -k2,2 -k9,9nr "$tmp_file")"
if [[ "$limit" != "all" ]]; then
    sorted_output="$(printf '%s\n' "$sorted_output" | head -n "$limit")"
fi

if [[ "$output_format" == "tsv" ]]; then
    echo "# promotion-suggestions-tsv-v1"
    echo $'rank\tscope\tclassification\tdestination\tid\tsummary\treason\ttype\trecurrence\tstatus'
    if [[ -n "$sorted_output" && "$sorted_output" != $'\n' ]]; then
        printf '%s\n' "$sorted_output"
    fi
    exit 0
fi

echo "<promotion-suggestions>"

if [[ -z "$sorted_output" || "$sorted_output" == $'\n' ]]; then
    echo "No suggestion candidates found."
    echo "</promotion-suggestions>"
    exit 0
fi

while IFS=$'\t' read -r rank scope_label classification destination id summary reason type_label recurrence status; do
    [[ -n "$id" ]] || continue
    printf -- "- [%s] %s -> %s\n" "$id" "$classification" "$destination"
    printf '  Scope: %s\n' "$scope_label"
    printf '  Type: %s\n' "$type_label"
    printf '  Status: %s\n' "$status"
    printf '  Recurrence: %s\n' "$recurrence"
    printf '  Summary: %s\n' "$summary"
    printf '  Reason: %s\n' "$reason"
done <<< "$sorted_output"

echo "</promotion-suggestions>"
