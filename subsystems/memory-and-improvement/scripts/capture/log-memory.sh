#!/bin/bash
# Append or update a structured memory entry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
. "$SCRIPT_ROOT/shared/file-lock.sh"

scope="project"
entry_type=""
category=""
summary=""
details=""
suggested_action=""
error_text=""
context_text=""
suggested_fix=""
capability=""
user_context=""
complexity="medium"
suggested_implementation=""
priority=""
status="pending"
area="docs"
source="conversation"
related_files="none"
tags="none"
pattern_key=""
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
reproducible="unknown"
dry_run=false
git_autocommit="$self_improving_git_autocommit_default"

usage() {
    cat <<EOF
Usage: $(basename "$0") --scope project|global --type learning|error|feature [options]

Core options:
  --scope project|global
  --type learning|error|feature
  --summary TEXT
  --namespace NAME              Used for global scope unless --global-memory-dir is set
  --project-root PATH
  --project-memory-dir PATH     Absolute or relative path to a .learnings directory
  --global-memory-dir PATH      Absolute or relative path to a .learnings directory
  --pattern-key KEY             Stable dedupe key for recurring entries
  --git-autocommit true|false   Commit memory updates through git-memory.sh
  --dry-run

Learning options:
  --category correction|insight|knowledge_gap|best_practice
  --details TEXT
  --suggested-action TEXT

Error options:
  --error-text TEXT
  --context TEXT
  --suggested-fix TEXT
  --reproducible yes|no|unknown

Feature options:
  --capability TEXT
  --user-context TEXT
  --complexity simple|medium|complex
  --suggested-implementation TEXT

Shared metadata:
  --priority low|medium|high|critical
  --status pending|in_progress|resolved|wont_fix|promoted_to_summary|promoted_to_skill
  --area frontend|backend|infra|tests|docs|config
  --source conversation|error|user_feedback|automation
  --related-files path1,path2
  --tags tag1,tag2
EOF
}

make_pattern_key() {
    local seed="$1"
    local normalized
    local checksum
    normalized="$(printf '%s' "$seed" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/./g; s/^\.//; s/\.$//; s/\.\.+/./g')"
    checksum="$(printf '%s' "$seed" | cksum | awk '{print $1}')"
    normalized="${normalized:0:48}"
    if [[ -z "$normalized" ]]; then
        normalized="entry"
    fi
    printf '%s.%s\n' "$normalized" "$checksum"
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

next_entry_id() {
    local prefix="$1"
    local file="$2"
    local today="$3"
    local last="0"

    if [[ -f "$file" ]]; then
        last="$(
            self_improving_extract_matches "${prefix}-${today}-[0-9]{3}" "$file" \
            | sed -E "s/^${prefix}-${today}-//" \
            | sort -n \
            | tail -1
        )"
    fi

    if [[ -z "$last" ]]; then
        last="0"
    fi

    printf '%s-%s-%03d\n' "$prefix" "$today" "$((10#$last + 1))"
}

resolve_global_memory_dir() {
    self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override"
}

resolve_project_memory_dir() {
    self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir"
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

extract_existing_id() {
    local file="$1"
    local key="$2"
    awk -v wanted="$key" '
        /^## \[/ {
            id=$0
            sub(/^## \[/, "", id)
            sub(/\].*$/, "", id)
        }
        $0 == "- Pattern-Key: " wanted {
            print id
            exit
        }
    ' "$file"
}

update_recurrence_if_present() {
    local file="$1"
    local key="$2"
    local today="$3"
    local recurrence_note="${4:-}"
    local reopen_status="${5:-}"
    local feature_frequency="${6:-}"

    PATTERN_KEY="$key" LAST_SEEN="$today" RECURRENCE_NOTE="$recurrence_note" REOPEN_STATUS="$reopen_status" FEATURE_FREQUENCY="$feature_frequency" perl -0pi -e '
        my $key = quotemeta $ENV{PATTERN_KEY};
        my $last_seen = $ENV{LAST_SEEN};
        my $note = $ENV{RECURRENCE_NOTE} // q{};
        my $reopen_status = $ENV{REOPEN_STATUS} // q{};
        my $feature_frequency = $ENV{FEATURE_FREQUENCY} // q{};
        my @parts = split(/^---\n/m, $_, -1);
        for my $part (@parts) {
            next unless $part =~ /(?:^|\n)- Pattern-Key: $key(?:\n|$)/m;
            $part =~ s{((?:^|\n)- Recurrence-Count: )(\d+)}{$1 . ($2 + 1)}em;
            $part =~ s{((?:^|\n)- Last-Seen: )[^\n]+}{$1 . $last_seen}em;
            if (length $reopen_status) {
                $part =~ s{(\n\*\*Status\*\*: )resolved\b}{$1 . $reopen_status}em;
            }
            if (length $feature_frequency) {
                $part =~ s{((?:^|\n)- Frequency: )[^\n]+}{$1 . $feature_frequency}em;
            }
            if (length $note) {
                my $bullet = "- $last_seen: $note";
                if (index($part, $bullet) < 0) {
                    if ($part =~ /\n### Recurrence Notes\n/) {
                        $part =~ s{\n### Recurrence Notes\n}{\n### Recurrence Notes\n$bullet\n};
                    } elsif ($part =~ /\n### Metadata\n/) {
                        $part =~ s{\n### Metadata\n}{\n### Recurrence Notes\n$bullet\n\n### Metadata\n};
                    } else {
                        $part .= "\n### Recurrence Notes\n$bullet\n";
                    }
                }
            }
        }
        $_ = join("---\n", @parts);
    ' "$file"
}

append_line_if_value() {
    local label="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        printf '%s%s\n' "$label" "$value"
    fi
}

normalize_single_line() {
    printf '%s' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

build_recurrence_note() {
    local parts=()

    case "$entry_type" in
        learning)
            [[ -n "$details" && "$details" != "none" ]] && parts+=("Details: $(normalize_single_line "$details")")
            [[ -n "$suggested_action" && "$suggested_action" != "none" ]] && parts+=("Suggested Action: $(normalize_single_line "$suggested_action")")
            ;;
        error)
            [[ -n "$error_text" && "$error_text" != "none" ]] && parts+=("Error: $(normalize_single_line "$error_text")")
            [[ -n "$context_text" && "$context_text" != "none" ]] && parts+=("Context: $(normalize_single_line "$context_text")")
            [[ -n "$suggested_fix" && "$suggested_fix" != "none" ]] && parts+=("Suggested Fix: $(normalize_single_line "$suggested_fix")")
            ;;
        feature)
            [[ -n "$capability" && "$capability" != "none" ]] && parts+=("Requested Capability: $(normalize_single_line "$capability")")
            [[ -n "$user_context" && "$user_context" != "none" ]] && parts+=("User Context: $(normalize_single_line "$user_context")")
            [[ -n "$suggested_implementation" && "$suggested_implementation" != "none" ]] && parts+=("Suggested Implementation: $(normalize_single_line "$suggested_implementation")")
            ;;
    esac

    if [[ ${#parts[@]} -gt 0 ]]; then
        local joined
        printf -v joined '%s | ' "${parts[@]}"
        printf '%s\n' "${joined% | }"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --type)
            entry_type="${2:-}"
            shift 2
            ;;
        --summary)
            summary="${2:-}"
            shift 2
            ;;
        --category)
            category="${2:-}"
            shift 2
            ;;
        --details)
            details="${2:-}"
            shift 2
            ;;
        --suggested-action)
            suggested_action="${2:-}"
            shift 2
            ;;
        --error-text)
            error_text="${2:-}"
            shift 2
            ;;
        --context)
            context_text="${2:-}"
            shift 2
            ;;
        --suggested-fix)
            suggested_fix="${2:-}"
            shift 2
            ;;
        --capability)
            capability="${2:-}"
            shift 2
            ;;
        --user-context)
            user_context="${2:-}"
            shift 2
            ;;
        --complexity)
            complexity="${2:-}"
            shift 2
            ;;
        --suggested-implementation)
            suggested_implementation="${2:-}"
            shift 2
            ;;
        --priority)
            priority="${2:-}"
            shift 2
            ;;
        --status)
            status="${2:-}"
            shift 2
            ;;
        --area)
            area="${2:-}"
            shift 2
            ;;
        --source)
            source="${2:-}"
            shift 2
            ;;
        --related-files)
            related_files="${2:-}"
            shift 2
            ;;
        --tags)
            tags="${2:-}"
            shift 2
            ;;
        --pattern-key)
            pattern_key="${2:-}"
            shift 2
            ;;
        --git-autocommit)
            git_autocommit="${2:-}"
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
        --reproducible)
            reproducible="${2:-}"
            shift 2
            ;;
        --dry-run)
            dry_run=true
            shift
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
    project|global) ;;
    *)
        echo "Invalid scope: $scope" >&2
        exit 1
        ;;
esac

case "$entry_type" in
    learning|error|feature) ;;
    *)
        echo "--type is required and must be learning, error, or feature" >&2
        exit 1
        ;;
esac

if [[ -z "$category" ]]; then
    case "$entry_type" in
        learning) category="insight" ;;
        error) category="operation" ;;
        feature) category="capability_request" ;;
    esac
fi

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
resolved_project_memory_dir="$(resolve_project_memory_dir)"
resolved_global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" ]]; then
    resolved_global_memory_dir="$(resolve_global_memory_dir)"
elif [[ -n "$self_improving_global_memory_dir" ]]; then
    resolved_global_memory_dir="$self_improving_global_memory_dir"
fi
if [[ -n "$resolved_global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$resolved_project_memory_dir" "$resolved_global_memory_dir"
fi

if [[ "$scope" == "global" && -z "$global_memory_dir_override" ]]; then
    self_improving_validate_namespace_or_die "$namespace" >/dev/null
fi

if [[ "$entry_type" == "feature" && -z "$summary" && -n "$capability" ]]; then
    summary="$capability"
fi

if [[ -z "$summary" ]]; then
    echo "--summary is required" >&2
    exit 1
fi

if [[ -z "$priority" ]]; then
    case "$entry_type" in
        learning) priority="medium" ;;
        error) priority="high" ;;
        feature) priority="medium" ;;
    esac
fi

validate_one_of "status" "$status" pending in_progress resolved wont_fix promoted_to_summary promoted_to_skill
validate_one_of "priority" "$priority" low medium high critical
validate_one_of "area" "$area" frontend backend infra tests docs config
validate_one_of "source" "$source" conversation error user_feedback automation
validate_one_of "git-autocommit" "$git_autocommit" true false

case "$entry_type" in
    learning)
        validate_one_of "category" "$category" correction insight knowledge_gap best_practice
        ;;
    error)
        validate_one_of "category" "$category" operation integration environment tooling
        validate_one_of "reproducible" "$reproducible" yes no unknown
        ;;
    feature)
        validate_one_of "complexity" "$complexity" simple medium complex
        ;;
esac

if [[ -z "$pattern_key" ]]; then
    pattern_key="$(make_pattern_key "$entry_type.$category.$summary")"
fi

ensure_memory_initialized

if [[ "$scope" == "project" ]]; then
    destination_dir="$(resolve_project_memory_dir)"
else
    destination_dir="$(resolve_global_memory_dir)"
fi

if [[ "$scope" == "project" ]]; then
    self_improving_register_project_memory_dir "$destination_dir"
fi

case "$entry_type" in
    learning)
        destination_file="$destination_dir/LEARNINGS.md"
        id_prefix="LRN"
        ;;
    error)
        destination_file="$destination_dir/ERRORS.md"
        id_prefix="ERR"
        ;;
    feature)
        destination_file="$destination_dir/FEATURE_REQUESTS.md"
        id_prefix="FEAT"
        ;;
esac

timestamp="$(date -Iseconds)"
today_id="$(date +%Y%m%d)"
today_short="$(date +%F)"
entry_id="PENDING"

render_metadata_common() {
    printf -- "- Source: %s\n" "$source"
    printf -- "- Related Files: %s\n" "$related_files"
    printf -- "- Tags: %s\n" "$tags"
    if [[ -n "$pattern_key" ]]; then
        printf -- "- Pattern-Key: %s\n" "$pattern_key"
        printf -- "- Recurrence-Count: 1\n"
        printf -- "- First-Seen: %s\n" "$today_short"
        printf -- "- Last-Seen: %s\n" "$today_short"
    fi
}

render_entry() {
    case "$entry_type" in
        learning)
            cat <<EOF
## [$entry_id] $category

**Logged**: $timestamp
**Priority**: $priority
**Status**: $status
**Area**: $area

### Summary
$summary

### Details
${details:-none}

### Suggested Action
${suggested_action:-none}

### Metadata
$(render_metadata_common)

---
EOF
            ;;
        error)
            cat <<EOF
## [$entry_id] ${category:-operation}

**Logged**: $timestamp
**Priority**: $priority
**Status**: $status
**Area**: $area

### Summary
$summary

### Error
\`\`\`
${error_text:-none}
\`\`\`

### Context
${context_text:-none}

### Suggested Fix
${suggested_fix:-none}

### Metadata
- Reproducible: $reproducible
$(render_metadata_common)

---
EOF
            ;;
        feature)
            cat <<EOF
## [$entry_id] ${capability:-capability_request}

**Logged**: $timestamp
**Priority**: $priority
**Status**: $status
**Area**: $area

### Requested Capability
${capability:-$summary}

### User Context
${user_context:-none}

### Complexity Estimate
$complexity

### Suggested Implementation
${suggested_implementation:-none}

### Metadata
- Frequency: first_time
$(render_metadata_common)

---
EOF
            ;;
    esac
}

if [[ "$dry_run" == true ]]; then
    if [[ -n "$pattern_key" ]] && self_improving_contains_fixed "- Pattern-Key: $pattern_key" "$destination_file"; then
        existing_id="$(extract_existing_id "$destination_file" "$pattern_key")"
        printf 'Would update recurrence for %s in %s\n' "${existing_id:-existing entry}" "$destination_file"
        exit 0
    fi
    entry_id="$(next_entry_id "$id_prefix" "$destination_file" "$today_id")"
    printf 'Would append to %s\n\n' "$destination_file"
    render_entry
    exit 0
fi

run_git_commit() {
    local commit_scope_args=(--scope "$scope" --project-root "$project_root" --namespace "$namespace" --message "memory: update $(basename "$destination_file")")

    if [[ -n "$project_memory_dir" ]]; then
        commit_scope_args+=(--project-memory-dir "$project_memory_dir")
    fi

    if [[ -n "$global_memory_dir_override" ]]; then
        commit_scope_args+=(--global-memory-dir "$global_memory_dir_override")
    fi

    bash "$SCRIPT_ROOT/maintenance/git-memory.sh" commit "${commit_scope_args[@]}" >/dev/null
}

scope_lock_file="$destination_dir/.memory-write.lock"
self_improving_lock_acquire memory_scope "$scope_lock_file" 8

lock_file="$destination_file.lock"
self_improving_lock_acquire memory_file "$lock_file" 9

if [[ -n "$pattern_key" ]] && self_improving_contains_fixed "- Pattern-Key: $pattern_key" "$destination_file"; then
    existing_id="$(extract_existing_id "$destination_file" "$pattern_key")"
    recurrence_note="$(build_recurrence_note)"
    reopen_status="pending"
    feature_frequency=""
    if [[ "$entry_type" == "feature" ]]; then
        feature_frequency="recurring"
    fi
    update_recurrence_if_present "$destination_file" "$pattern_key" "$today_short" "$recurrence_note" "$reopen_status" "$feature_frequency"
    self_improving_lock_release memory_file
    self_improving_lock_release memory_scope
    if [[ "$git_autocommit" == "true" ]]; then
        run_git_commit
    fi
    printf 'Updated recurrence for %s in %s\n' "${existing_id:-existing entry}" "$destination_file"
    exit 0
fi

entry_id="$(next_entry_id "$id_prefix" "$destination_file" "$today_id")"
printf '\n%s\n' "$(render_entry)" >> "$destination_file"

self_improving_lock_release memory_file
self_improving_lock_release memory_scope

if [[ "$git_autocommit" == "true" ]]; then
    run_git_commit
fi

printf 'Appended %s to %s\n' "$entry_id" "$destination_file"
