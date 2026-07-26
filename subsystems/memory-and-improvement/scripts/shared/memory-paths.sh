#!/bin/bash
# Shared path resolution for memory-and-improvement.
# Source this file from other scripts.

if [[ -n "${SELF_IMPROVING_MEMORY_PATHS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
SELF_IMPROVING_MEMORY_PATHS_SH_LOADED=1

self_improving_pwd="${PWD:-$(pwd)}"
self_improving_pwd="${self_improving_pwd%/}"
if [[ -z "$self_improving_pwd" ]]; then
    self_improving_pwd="."
fi

self_improving_trim_trailing_slash() {
    local value="$1"
    if [[ "$value" == "/" ]]; then
        printf '/\n'
        return 0
    fi
    value="${value%/}"
    if [[ -z "$value" ]]; then
        value="."
    fi
    printf '%s\n' "$value"
}

self_improving_has_ripgrep() {
    local candidate
    candidate="$(command -v rg 2>/dev/null || true)"
    [[ -n "$candidate" ]] && "$candidate" --version >/dev/null 2>&1
}

self_improving_extract_matches() {
    local pattern="$1"
    local path="$2"

    if self_improving_has_ripgrep; then
        rg -o -- "$pattern" "$path" 2>/dev/null
    else
        grep -Eo -- "$pattern" "$path" 2>/dev/null
    fi
}

self_improving_contains_fixed() {
    local needle="$1"
    local path="$2"

    if self_improving_has_ripgrep; then
        rg -q --fixed-strings -- "$needle" "$path"
    else
        grep -Fq -- "$needle" "$path"
    fi
}

self_improving_contains_regex() {
    local pattern="$1"
    local path="$2"

    if self_improving_has_ripgrep; then
        rg -q -- "$pattern" "$path"
    else
        grep -Eq -- "$pattern" "$path"
    fi
}

self_improving_canonicalize_path() {
    local value="$1"
    local parent
    local base

    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$value"
        return 0
    fi

    if [[ -d "$value" ]]; then
        (cd "$value" && pwd -P)
        return 0
    fi

    if [[ -e "$value" ]]; then
        parent="$(dirname "$value")"
        base="$(basename "$value")"
        printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
        return 0
    fi

    parent="$(dirname "$value")"
    base="$(basename "$value")"
    if [[ -d "$parent" ]]; then
        printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
    else
        self_improving_trim_trailing_slash "$value"
    fi
}

self_improving_normalize_path() {
    local value="$1"
    local candidate

    if [[ "$value" =~ ^[A-Za-z]:[\\/] ]]; then
        if command -v cygpath >/dev/null 2>&1; then
            value="$(cygpath -u "$value")"
        else
            local drive="${value:0:1}"
            local rest="${value:2}"
            drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
            rest="${rest//\\//}"
            value="/$drive/$rest"
        fi
    fi

    if [[ "$value" == /* ]]; then
        candidate="$value"
    else
        candidate="$self_improving_pwd/${value#./}"
    fi
    self_improving_trim_trailing_slash "$(self_improving_canonicalize_path "$candidate")"
}

self_improving_absolutize_path() {
    self_improving_normalize_path "$1"
}

self_improving_detect_project_root() {
    if git -C "$self_improving_pwd" rev-parse --show-toplevel >/dev/null 2>&1; then
        git -C "$self_improving_pwd" rev-parse --show-toplevel
    else
        printf '%s\n' "$self_improving_pwd"
    fi
}

self_improving_validate_namespace() {
    local namespace="$1"
    [[ "$namespace" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

self_improving_validate_namespace_or_die() {
    local namespace="$1"
    if ! self_improving_validate_namespace "$namespace"; then
        echo "Invalid global namespace: $namespace" >&2
        echo "Use lowercase letters, numbers, and hyphens only." >&2
        return 1
    fi
}

self_improving_default_project_memory_dir_for_root() {
    local root="$1"
    printf '%s/.learnings\n' "$(self_improving_normalize_path "$root")"
}

self_improving_resolve_project_memory_dir() {
    local root="$1"
    local override="${2:-}"

    if [[ -n "$override" ]]; then
        self_improving_normalize_path "$override"
    else
        self_improving_default_project_memory_dir_for_root "$root"
    fi
}

self_improving_default_global_memory_dir_for_namespace() {
    local namespace="$1"
    self_improving_validate_namespace_or_die "$namespace" >/dev/null
    printf '%s/%s/.learnings\n' "$self_improving_global_namespaces_root" "$namespace"
}

self_improving_resolve_global_memory_dir() {
    local namespace="$1"
    local override="${2:-}"

    if [[ -n "$override" ]]; then
        self_improving_normalize_path "$override"
    else
        self_improving_default_global_memory_dir_for_namespace "$namespace"
    fi
}

self_improving_resolve_global_namespace_dir() {
    local namespace="$1"
    local override="${2:-}"
    local memory_dir

    memory_dir="$(self_improving_resolve_global_memory_dir "$namespace" "$override")"
    printf '%s\n' "${memory_dir%/.learnings}"
}

self_improving_paths_overlap() {
    local first="$1"
    local second="$2"

    [[ -n "$first" && -n "$second" ]] || return 1
    [[ "$first" == "$second" || "$first" == "$second/"* || "$second" == "$first/"* ]]
}

self_improving_validate_memory_isolation_or_die() {
    local project_dir="$1"
    local global_dir="$2"

    [[ -n "$project_dir" && -n "$global_dir" ]] || return 0

    project_dir="$(self_improving_normalize_path "$project_dir")"
    global_dir="$(self_improving_normalize_path "$global_dir")"

    if self_improving_paths_overlap "$project_dir" "$global_dir"; then
        echo "Project and global memory must be isolated." >&2
        echo "Project memory: $project_dir" >&2
        echo "Global memory:  $global_dir" >&2
        echo "Choose distinct, non-overlapping .learnings directories." >&2
        return 1
    fi
}

self_improving_shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$self_improving_shared_dir/memory-config.sh" || return 1

if [[ -n "${SELF_IMPROVING_PROJECT_ROOT:-}" ]]; then
    self_improving_project_root="$(self_improving_normalize_path "$SELF_IMPROVING_PROJECT_ROOT")"
else
    self_improving_project_root="$(self_improving_detect_project_root)"
fi

self_improving_project_memory_dir_overridden=false
if [[ -n "${SELF_IMPROVING_PROJECT_MEMORY_DIR:-}" ]]; then
    self_improving_project_memory_dir="$(self_improving_normalize_path "$SELF_IMPROVING_PROJECT_MEMORY_DIR")"
    self_improving_project_memory_dir_overridden=true
else
    self_improving_project_memory_dir="$(self_improving_default_project_memory_dir_for_root "$self_improving_project_root")"
fi
self_improving_project_memory_dir="$(self_improving_trim_trailing_slash "$self_improving_project_memory_dir")"

self_improving_global_root="$(self_improving_normalize_path "$self_improving_config_global_root")"
self_improving_global_namespaces_root="$(self_improving_normalize_path "$self_improving_config_global_namespaces_root")"
self_improving_global_namespace="$self_improving_config_global_namespace"
self_improving_global_namespace="${self_improving_global_namespace#/}"
self_improving_global_namespace="${self_improving_global_namespace%/}"
self_improving_default_global_namespaces="${SELF_IMPROVING_DEFAULT_GLOBAL_NAMESPACES:-research-principle research-ops research-history user-profile project}"

self_improving_global_memory_dir_overridden=false
if [[ -n "${SELF_IMPROVING_GLOBAL_MEMORY_DIR:-}" ]]; then
    self_improving_global_memory_dir="$(self_improving_normalize_path "$SELF_IMPROVING_GLOBAL_MEMORY_DIR")"
    self_improving_global_memory_dir_overridden=true
elif self_improving_validate_namespace "$self_improving_global_namespace"; then
    self_improving_global_memory_dir="$(self_improving_default_global_memory_dir_for_namespace "$self_improving_global_namespace")"
else
    self_improving_global_memory_dir=""
fi
self_improving_global_memory_dir="${self_improving_global_memory_dir:+$(self_improving_trim_trailing_slash "$self_improving_global_memory_dir")}"

self_improving_global_namespace_dir="${self_improving_global_memory_dir%/.learnings}"
self_improving_global_namespace_is_standard=false
if [[ -n "$self_improving_global_memory_dir" && "$self_improving_global_memory_dir" == "$self_improving_global_namespaces_root/"*"/.learnings" ]]; then
    self_improving_global_namespace_is_standard=true
fi

self_improving_codex_home="$(self_improving_normalize_path "$self_improving_config_codex_home")"
self_improving_codex_skills_dir="$(self_improving_normalize_path "$self_improving_config_codex_skills_dir")"
self_improving_state_root="$(self_improving_normalize_path "$self_improving_config_state_root")"
self_improving_log_dir_default="$(self_improving_normalize_path "$self_improving_config_log_dir")"
self_improving_git_autocommit_default="$self_improving_config_git_autocommit"
self_improving_nightly_writeback_default="$self_improving_config_nightly_writeback"
self_improving_skill_policy_writeback_default="$self_improving_config_skill_policy_writeback"
self_improving_organize_min_recurrence_default="$self_improving_config_organize_min_recurrence"
self_improving_maintenance_scope_default="$self_improving_config_maintenance_scope"
self_improving_maintenance_schedule_mode_default="$self_improving_config_maintenance_schedule_mode"
self_improving_maintenance_schedule_hour_default="$self_improving_config_maintenance_schedule_hour"
self_improving_maintenance_schedule_minute_default="$self_improving_config_maintenance_schedule_minute"
self_improving_maintenance_schedule_interval_minutes_default="$self_improving_config_maintenance_schedule_interval_minutes"
self_improving_skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
self_improving_legacy_project_registry_file="$self_improving_state_root/project-memory-registry.txt"
self_improving_codexkit_root=""
self_improving_skill_parent="${self_improving_skill_dir%/*}"
self_improving_skill_grandparent="${self_improving_skill_parent%/*}"
if [[ -n "${SELF_IMPROVING_CODEXKIT_ROOT:-}" ]]; then
    self_improving_codexkit_root="$(self_improving_normalize_path "$SELF_IMPROVING_CODEXKIT_ROOT")"
elif [[ "${self_improving_skill_parent##*/}" == "codex-skills" &&
        "${self_improving_skill_grandparent##*/}" == "skills" ]]; then
    self_improving_codexkit_root="${self_improving_skill_grandparent%/*}"
fi
if [[ -n "${SELF_IMPROVING_PROJECT_REGISTRY_FILE:-}" ]]; then
    self_improving_project_registry_file="$(self_improving_normalize_path "$SELF_IMPROVING_PROJECT_REGISTRY_FILE")"
elif [[ -n "$self_improving_codexkit_root" ]]; then
    self_improving_project_registry_file="$self_improving_codexkit_root/memory-system/project-memory-registry.tsv"
else
    self_improving_project_registry_file="$self_improving_legacy_project_registry_file"
fi
self_improving_promotable_status_regex='^(pending|in_progress|promoted_to_summary)$'
self_improving_review_visible_status_regex='^(pending|in_progress|promoted_to_summary)$'

self_improving_skill_markdown_template="$(awk '
    /^## SKILL\.md Template$/ { in_section=1; next }
    in_section && /^```markdown$/ { in_block=1; next }
    in_block && /^```$/ { exit }
    in_block { print }
' "$self_improving_skill_dir/references/SKILL-TEMPLATE.md" 2>/dev/null)"

self_improving_current_device_id() {
    local value=""
    if [[ -n "${SELF_IMPROVING_DEVICE_ID:-}" ]]; then
        value="$SELF_IMPROVING_DEVICE_ID"
    elif [[ -n "${COMPUTERNAME:-}" ]]; then
        value="$COMPUTERNAME"
    elif command -v hostname >/dev/null 2>&1; then
        value="$(hostname 2>/dev/null || true)"
    fi
    if [[ -z "$value" ]]; then
        value="${HOSTNAME:-}"
    fi
    value="${value//$'\t'/ }"
    value="${value//$'\r'/}"
    value="${value//$'\n'/ }"
    printf '%s\n' "${value:-unknown-device}"
}

self_improving_list_onedrive_roots() {
    local candidate=""
    local seen="|"
    local codexkit_parent=""

    if [[ -n "$self_improving_codexkit_root" ]]; then
        codexkit_parent="$(dirname "$self_improving_codexkit_root")"
        printf '%s\n' "$codexkit_parent"
        seen+="$codexkit_parent|"
    fi

    for candidate in "${OneDrive:-}" "${OneDriveConsumer:-}" "${OneDriveCommercial:-}" "${ONEDRIVE:-}"; do
        [[ -n "$candidate" ]] || continue
        candidate="$(self_improving_normalize_path "$candidate")"
        if [[ "$seen" != *"|$candidate|"* ]]; then
            printf '%s\n' "$candidate"
            seen+="$candidate|"
        fi
    done
}

self_improving_registry_record_for_path() {
    local memory_dir="$1"
    local root=""
    local relative=""
    local device=""

    memory_dir="$(self_improving_normalize_path "$memory_dir")"
    while IFS= read -r root; do
        [[ -n "$root" ]] || continue
        if [[ "$memory_dir" == "$root" || "$memory_dir" == "$root/"* ]]; then
            relative="${memory_dir#"$root"}"
            relative="${relative#/}"
            printf 'onedrive\t-\t%s\n' "${relative:-.}"
            return 0
        fi
    done < <(self_improving_list_onedrive_roots)

    device="$(self_improving_current_device_id)"
    if command -v cygpath >/dev/null 2>&1 && [[ "$memory_dir" == /[A-Za-z]/* ]]; then
        memory_dir="$(cygpath -w "$memory_dir" 2>/dev/null || printf '%s' "$memory_dir")"
    fi
    printf 'local\t%s\t%s\n' "$device" "$memory_dir"
}

self_improving_registry_resolve_record() {
    local storage="$1"
    local device="$2"
    local stored_path="$3"
    local root=""

    case "$storage" in
        local)
            [[ "$device" == "$(self_improving_current_device_id)" ]] || return 0
            if command -v cygpath >/dev/null 2>&1; then
                stored_path="$(cygpath -u "$stored_path" 2>/dev/null || printf '%s' "$stored_path")"
            fi
            printf '%s\n' "$(self_improving_normalize_path "$stored_path")"
            ;;
        onedrive)
            while IFS= read -r root; do
                [[ -n "$root" ]] || continue
                if [[ "$stored_path" == "." ]]; then
                    printf '%s\n' "$root"
                else
                    printf '%s\n' "$(self_improving_normalize_path "$root/$stored_path")"
                fi
                return 0
            done < <(self_improving_list_onedrive_roots)
            ;;
    esac
}

self_improving_registry_collect_records() {
    local file="$1"
    local line=""
    local storage=""
    local device=""
    local stored_path=""

    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        [[ "$line" == $'storage\tdevice\tpath' ]] && continue
        if [[ "$line" == *$'\t'* ]]; then
            IFS=$'\t' read -r storage device stored_path <<< "$line"
            case "$storage" in
                local)
                    if [[ -n "$stored_path" ]] &&
                       command -v cygpath >/dev/null 2>&1 &&
                       [[ "$stored_path" == /[A-Za-z]/* ]]; then
                        stored_path="$(cygpath -w "$stored_path" 2>/dev/null || printf '%s' "$stored_path")"
                    fi
                    [[ -n "$stored_path" ]] && printf '%s\t%s\t%s\n' "$storage" "$device" "$stored_path"
                    ;;
                onedrive)
                    [[ -n "$stored_path" ]] && printf '%s\t%s\t%s\n' "$storage" "$device" "$stored_path"
                    ;;
            esac
        else
            self_improving_registry_record_for_path "$line"
        fi
    done < "$file"
}

self_improving_registry_source_files() {
    local file="$self_improving_project_registry_file"
    local directory=""
    local candidate=""

    [[ -f "$file" ]] && printf '%s\n' "$file"
    directory="$(dirname "$file")"
    [[ -d "$directory" ]] || return 0

    while IFS= read -r candidate; do
        [[ "$candidate" == "$file" ]] || printf '%s\n' "$candidate"
    done < <(find "$directory" -maxdepth 1 -type f -name 'project-memory-registry*.tsv' -print 2>/dev/null | sort)
}

self_improving_write_registry_records() {
    local output_file="$1"
    shift
    {
        printf 'storage\tdevice\tpath\n'
        printf '%s\n' "$@" | awk 'NF && !seen[$0]++ { print }'
    } > "$output_file"
}

self_improving_register_project_memory_dir() {
    local memory_dir="$1"
    local file="$self_improving_project_registry_file"
    local legacy_file="$self_improving_legacy_project_registry_file"
    local lock_dir="$self_improving_state_root/project-memory-registry.lock"
    local temp_file=""
    local new_record=""
    local records=()
    local source_file=""
    local record=""
    local already_registered=false
    local source_files=()

    [[ -n "$memory_dir" ]] || return 0

    memory_dir="$(self_improving_normalize_path "$memory_dir")"
    mkdir -p "$(dirname "$file")"
    mkdir -p "$(dirname "$lock_dir")"
    new_record="$(self_improving_registry_record_for_path "$memory_dir")"

    (
        while ! mkdir "$lock_dir" 2>/dev/null; do
            sleep 0.1
        done
        trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

        mapfile -t source_files < <(self_improving_registry_source_files)
        mapfile -t records < <(
            for source_file in "${source_files[@]}"; do
                self_improving_registry_collect_records "$source_file"
            done
            if [[ "$legacy_file" != "$file" ]]; then
                self_improving_registry_collect_records "$legacy_file"
            fi
        )
        for record in "${records[@]}"; do
            if [[ "$record" == "$new_record" ]]; then
                already_registered=true
                break
            fi
        done
        if [[ "$already_registered" == true &&
              ! -f "$legacy_file" &&
              ${#source_files[@]} -le 1 ]] &&
           grep -Fqx -- "$new_record" "$file" 2>/dev/null; then
            local unique_record_count=""
            unique_record_count="$(
                printf '%s\n' "${records[@]}" |
                    awk 'NF && !seen[$0]++ { count++ } END { print count + 0 }'
            )"
            if [[ "$unique_record_count" -eq "${#records[@]}" ]]; then
                exit 0
            fi
        fi

        temp_file="$(mktemp "${TMPDIR:-/tmp}/project-memory-registry.XXXXXX")"
        records+=("$new_record")
        self_improving_write_registry_records "$temp_file" "${records[@]}"
        mv "$temp_file" "$file"
        if [[ "$legacy_file" != "$file" && -f "$legacy_file" ]]; then
            rm -f "$legacy_file"
        fi
    )
}

self_improving_list_registered_project_memory_dirs() {
    local file="$self_improving_project_registry_file"
    local legacy_file="$self_improving_legacy_project_registry_file"
    local source_file=""

    [[ -f "$file" || -f "$legacy_file" ]] || return 0

    local storage=""
    local device=""
    local stored_path=""
    local resolved=""

    while IFS=$'\t' read -r storage device stored_path; do
        [[ "$storage" == "storage" ]] && continue
        resolved="$(self_improving_registry_resolve_record "$storage" "$device" "$stored_path")"
        [[ -n "$resolved" ]] && printf '%s\n' "$resolved"
    done < <(
        while IFS= read -r source_file; do
            self_improving_registry_collect_records "$source_file"
        done < <(self_improving_registry_source_files)
        if [[ "$legacy_file" != "$file" ]]; then
            self_improving_registry_collect_records "$legacy_file"
        fi
    )
}

self_improving_unregister_project_memory_dir() {
    local memory_dir="$1"
    local file="$self_improving_project_registry_file"
    local legacy_file="$self_improving_legacy_project_registry_file"
    local lock_dir="$self_improving_state_root/project-memory-registry.lock"
    local temp_file=""
    local target_record=""
    local records=()
    local record=""
    local source_file=""
    local target_found=false

    [[ -n "$memory_dir" ]] || return 0

    memory_dir="$(self_improving_normalize_path "$memory_dir")"
    target_record="$(self_improving_registry_record_for_path "$memory_dir")"
    mkdir -p "$(dirname "$file")"
    mkdir -p "$(dirname "$lock_dir")"

    (
        while ! mkdir "$lock_dir" 2>/dev/null; do
            sleep 0.1
        done
        trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

        [[ -f "$file" || -f "$legacy_file" ]] || exit 0

        temp_file="$(mktemp "${TMPDIR:-/tmp}/project-memory-registry.XXXXXX")"
        mapfile -t records < <(
            while IFS= read -r source_file; do
                self_improving_registry_collect_records "$source_file"
            done < <(self_improving_registry_source_files)
            if [[ "$legacy_file" != "$file" ]]; then
                self_improving_registry_collect_records "$legacy_file"
            fi
        )
        local remaining=()
        for record in "${records[@]}"; do
            if [[ "$record" == "$target_record" ]]; then
                target_found=true
            else
                remaining+=("$record")
            fi
        done
        if [[ "$target_found" != true && ! -f "$legacy_file" ]]; then
            rm -f "$temp_file"
            exit 0
        fi
        self_improving_write_registry_records "$temp_file" "${remaining[@]}"

        mv "$temp_file" "$file"
        if [[ "$legacy_file" != "$file" && -f "$legacy_file" ]]; then
            rm -f "$legacy_file"
        fi
    )
}

self_improving_assets_dir_for_scope_and_memory_dir() {
    local scope="$1"
    local memory_dir="$2"
    local base_dir="${memory_dir%/.learnings}"

    case "$scope" in
        project) printf '%s/assets\n' "$memory_dir" ;;
        global) printf '%s/assets\n' "$base_dir" ;;
        *)
            printf 'Invalid asset scope: %s\n' "$scope" >&2
            return 1
            ;;
    esac
}

self_improving_asset_index_for_scope_and_memory_dir() {
    local scope="$1"
    local memory_dir="$2"
    printf '%s/INDEX.md\n' "$(self_improving_assets_dir_for_scope_and_memory_dir "$scope" "$memory_dir")"
}

self_improving_asset_files_dir_for_scope_and_memory_dir() {
    local scope="$1"
    local memory_dir="$2"
    printf '%s/files\n' "$(self_improving_assets_dir_for_scope_and_memory_dir "$scope" "$memory_dir")"
}
