#!/bin/bash
# Shared global config loading for memory-and-improvement.
# Precedence: built-in defaults < global config file < environment variables.
# CLI overrides still happen in each business script after sourcing memory-paths.sh.

if [[ -n "${SELF_IMPROVING_MEMORY_CONFIG_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

self_improving_config_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
self_improving_config_defaults_file="$self_improving_config_repo_root/config/defaults.toml"
self_improving_config_file="$HOME/.codex/skills/memory-and-improvement/config.toml"
self_improving_config_current_source=""
self_improving_config_log_dir_explicit=false
self_improving_config_global_namespaces_root_explicit=false
self_improving_config_defaults_file_exists=false
self_improving_config_file_exists=false

declare -A self_improving_config_key_types=(
    [paths.global_root]="string"
    [paths.global_namespaces_root]="string"
    [paths.state_root]="string"
    [paths.log_dir]="string"
    [paths.codex_home]="string"
    [paths.codex_skills_dir]="string"
    [defaults.global_namespace]="string"
    [defaults.git_autocommit]="bool"
    [defaults.nightly_writeback]="bool"
    [defaults.skill_policy_writeback]="bool"
    [defaults.organize_min_recurrence]="int"
    [maintenance.scope]="string"
    [maintenance.schedule.mode]="string"
    [maintenance.schedule.hour]="int"
    [maintenance.schedule.minute]="int"
    [maintenance.schedule.interval_minutes]="int"
)

declare -A self_improving_config_key_vars=(
    [paths.global_root]="self_improving_config_global_root"
    [paths.global_namespaces_root]="self_improving_config_global_namespaces_root"
    [paths.state_root]="self_improving_config_state_root"
    [paths.log_dir]="self_improving_config_log_dir"
    [paths.codex_home]="self_improving_config_codex_home"
    [paths.codex_skills_dir]="self_improving_config_codex_skills_dir"
    [defaults.global_namespace]="self_improving_config_global_namespace"
    [defaults.git_autocommit]="self_improving_config_git_autocommit"
    [defaults.nightly_writeback]="self_improving_config_nightly_writeback"
    [defaults.skill_policy_writeback]="self_improving_config_skill_policy_writeback"
    [defaults.organize_min_recurrence]="self_improving_config_organize_min_recurrence"
    [maintenance.scope]="self_improving_config_maintenance_scope"
    [maintenance.schedule.mode]="self_improving_config_maintenance_schedule_mode"
    [maintenance.schedule.hour]="self_improving_config_maintenance_schedule_hour"
    [maintenance.schedule.minute]="self_improving_config_maintenance_schedule_minute"
    [maintenance.schedule.interval_minutes]="self_improving_config_maintenance_schedule_interval_minutes"
)

declare -A self_improving_config_allowed_sections=(
    [paths]=1
    [defaults]=1
    [maintenance]=1
    [maintenance.schedule]=1
)

self_improving_config_fail() {
    printf 'memory-config.sh: %s\n' "$1" >&2
    return 1
}

self_improving_config_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

self_improving_config_expand_home() {
    local value="$1"

    case "$value" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s/%s\n' "$HOME" "${value#~/}"
            ;;
        '$HOME')
            printf '%s\n' "$HOME"
            ;;
        '$HOME/'*)
            printf '%s/%s\n' "$HOME" "${value#\$HOME/}"
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}

self_improving_config_parse_string() {
    local raw_value
    raw_value="$(self_improving_config_trim "$1")"

    if [[ "$raw_value" =~ ^\"([^\"]*)\"([[:space:]]*#.*)?$ ]]; then
        printf '%s\n' "$(self_improving_config_expand_home "${BASH_REMATCH[1]}")"
        return 0
    fi

    if [[ "$raw_value" =~ ^\'([^\']*)\'([[:space:]]*#.*)?$ ]]; then
        printf '%s\n' "$(self_improving_config_expand_home "${BASH_REMATCH[1]}")"
        return 0
    fi

    return 1
}

self_improving_config_parse_bool() {
    local raw_value
    raw_value="$(self_improving_config_trim "$1")"

    if [[ "$raw_value" =~ ^(true|false)([[:space:]]*#.*)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

self_improving_config_parse_int() {
    local raw_value
    raw_value="$(self_improving_config_trim "$1")"

    if [[ "$raw_value" =~ ^([0-9]+)([[:space:]]*#.*)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

self_improving_config_validate_namespace() {
    local namespace="$1"
    [[ "$namespace" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

self_improving_config_apply_entry() {
    local key="$1"
    local raw_value="$2"
    local parsed_value=""
    local value_type="${self_improving_config_key_types[$key]:-}"
    local value_var="${self_improving_config_key_vars[$key]:-}"

    if [[ -z "$value_type" || -z "$value_var" ]]; then
        self_improving_config_fail "unsupported config key: $key"
        return 1
    fi

    case "$value_type" in
        string)
            parsed_value="$(self_improving_config_parse_string "$raw_value")" || {
                self_improving_config_fail "invalid string for $key"
                return 1
            }
            ;;
        bool)
            parsed_value="$(self_improving_config_parse_bool "$raw_value")" || {
                self_improving_config_fail "invalid boolean for $key"
                return 1
            }
            ;;
        int)
            parsed_value="$(self_improving_config_parse_int "$raw_value")" || {
                self_improving_config_fail "invalid integer for $key"
                return 1
            }
            ;;
        *)
            self_improving_config_fail "unsupported config type for $key: $value_type"
            return 1
            ;;
    esac

    printf -v "$value_var" '%s' "$parsed_value"

    case "$key" in
        paths.log_dir)
            if [[ "$self_improving_config_current_source" == "user" ]]; then
                self_improving_config_log_dir_explicit=true
            fi
            ;;
        paths.global_namespaces_root)
            if [[ "$self_improving_config_current_source" == "user" ]]; then
                self_improving_config_global_namespaces_root_explicit=true
            fi
            ;;
    esac
}

self_improving_config_validate_final_values() {
    case "$self_improving_config_global_namespace" in
        "")
            self_improving_config_fail "defaults.global_namespace cannot be empty"
            return 1
            ;;
        *)
            self_improving_config_validate_namespace "$self_improving_config_global_namespace" || {
                self_improving_config_fail "invalid defaults.global_namespace: $self_improving_config_global_namespace"
                return 1
            }
            ;;
    esac

    case "$self_improving_config_git_autocommit" in
        true|false) ;;
        *)
            self_improving_config_fail "invalid defaults.git_autocommit: $self_improving_config_git_autocommit"
            return 1
            ;;
    esac

    case "$self_improving_config_nightly_writeback" in
        true|false) ;;
        *)
            self_improving_config_fail "invalid defaults.nightly_writeback: $self_improving_config_nightly_writeback"
            return 1
            ;;
    esac

    case "$self_improving_config_skill_policy_writeback" in
        true|false) ;;
        *)
            self_improving_config_fail "invalid defaults.skill_policy_writeback: $self_improving_config_skill_policy_writeback"
            return 1
            ;;
    esac

    [[ "$self_improving_config_organize_min_recurrence" =~ ^[0-9]+$ ]] || {
        self_improving_config_fail "invalid defaults.organize_min_recurrence: $self_improving_config_organize_min_recurrence"
        return 1
    }
    [[ "$self_improving_config_maintenance_schedule_hour" =~ ^[0-9]+$ ]] || {
        self_improving_config_fail "invalid maintenance.schedule.hour: $self_improving_config_maintenance_schedule_hour"
        return 1
    }
    [[ "$self_improving_config_maintenance_schedule_minute" =~ ^[0-9]+$ ]] || {
        self_improving_config_fail "invalid maintenance.schedule.minute: $self_improving_config_maintenance_schedule_minute"
        return 1
    }
    [[ "$self_improving_config_maintenance_schedule_interval_minutes" =~ ^[0-9]+$ ]] || {
        self_improving_config_fail "invalid maintenance.schedule.interval_minutes: $self_improving_config_maintenance_schedule_interval_minutes"
        return 1
    }

    if (( self_improving_config_maintenance_schedule_hour < 0 || self_improving_config_maintenance_schedule_hour > 23 )); then
        self_improving_config_fail "maintenance.schedule.hour must be between 0 and 23"
        return 1
    fi

    if (( self_improving_config_maintenance_schedule_minute < 0 || self_improving_config_maintenance_schedule_minute > 59 )); then
        self_improving_config_fail "maintenance.schedule.minute must be between 0 and 59"
        return 1
    fi

    if (( self_improving_config_maintenance_schedule_interval_minutes <= 0 )); then
        self_improving_config_fail "maintenance.schedule.interval_minutes must be greater than 0"
        return 1
    fi

    case "$self_improving_config_maintenance_scope" in
        project|global|both) ;;
        *)
            self_improving_config_fail "invalid maintenance.scope: $self_improving_config_maintenance_scope"
            return 1
            ;;
    esac

    case "$self_improving_config_maintenance_schedule_mode" in
        fixed|interval) ;;
        *)
            self_improving_config_fail "invalid maintenance.schedule.mode: $self_improving_config_maintenance_schedule_mode"
            return 1
            ;;
    esac
}

self_improving_config_load_file() {
    local file="$1"
    local line=""
    local trimmed=""
    local section=""
    local key=""
    local value=""
    local lineno=0

    [[ -f "$file" ]] || return 0
    if [[ "$file" == "$self_improving_config_defaults_file" ]]; then
        self_improving_config_current_source="defaults"
        self_improving_config_defaults_file_exists=true
    fi
    if [[ "$file" == "$self_improving_config_file" ]]; then
        self_improving_config_current_source="user"
        self_improving_config_file_exists=true
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"
        trimmed="$(self_improving_config_trim "$line")"

        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == \#* ]] && continue

        if [[ "$trimmed" =~ ^\[([a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            if [[ -z "${self_improving_config_allowed_sections[$section]:-}" ]]; then
                self_improving_config_fail "unsupported section '$section' in $file:$lineno"
                return 1
            fi
            continue
        fi

        if [[ -z "$section" ]]; then
            self_improving_config_fail "config key outside of a section in $file:$lineno"
            return 1
        fi

        if [[ ! "$trimmed" =~ ^([a-z][a-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            self_improving_config_fail "invalid config line in $file:$lineno"
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        self_improving_config_apply_entry "$section.$key" "$value" || return 1
    done < "$file"

    self_improving_config_current_source=""
}

self_improving_config_load_file "$self_improving_config_defaults_file" || return 1
if [[ "$self_improving_config_defaults_file_exists" != true ]]; then
    self_improving_config_fail "missing built-in defaults file: $self_improving_config_defaults_file"
    return 1
fi

self_improving_config_load_file "$self_improving_config_file" || return 1

if [[ -n "${SELF_IMPROVING_GLOBAL_ROOT:-}" ]]; then
    self_improving_config_global_root="$SELF_IMPROVING_GLOBAL_ROOT"
fi

if [[ -n "${SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT:-}" ]]; then
    self_improving_config_global_namespaces_root="$SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT"
    self_improving_config_global_namespaces_root_explicit=true
fi

if [[ "$self_improving_config_global_namespaces_root_explicit" != true ]]; then
    self_improving_config_global_namespaces_root="$self_improving_config_global_root/namespaces"
fi

if [[ -n "${SELF_IMPROVING_GLOBAL_NAMESPACE:-}" ]]; then
    self_improving_config_global_namespace="$SELF_IMPROVING_GLOBAL_NAMESPACE"
fi

if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    self_improving_config_state_root="$XDG_STATE_HOME/memory-and-improvement"
fi

if [[ -n "${CODEX_HOME:-}" ]]; then
    self_improving_config_codex_home="$CODEX_HOME"
fi

if [[ -n "${SELF_IMPROVING_CODEX_SKILLS_DIR:-}" ]]; then
    self_improving_config_codex_skills_dir="$SELF_IMPROVING_CODEX_SKILLS_DIR"
fi

if [[ -n "${SELF_IMPROVING_GIT_AUTOCOMMIT:-}" ]]; then
    self_improving_config_git_autocommit="$SELF_IMPROVING_GIT_AUTOCOMMIT"
fi

if [[ -n "${SELF_IMPROVING_NIGHTLY_WRITEBACK:-}" ]]; then
    self_improving_config_nightly_writeback="$SELF_IMPROVING_NIGHTLY_WRITEBACK"
fi

if [[ -n "${SELF_IMPROVING_SKILL_POLICY_WRITEBACK:-}" ]]; then
    self_improving_config_skill_policy_writeback="$SELF_IMPROVING_SKILL_POLICY_WRITEBACK"
fi

if [[ -n "${SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE:-}" ]]; then
    self_improving_config_organize_min_recurrence="$SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE"
fi

if [[ "$self_improving_config_log_dir_explicit" != true ]]; then
    self_improving_config_log_dir="$self_improving_config_state_root/logs"
fi

self_improving_config_validate_final_values || return 1
SELF_IMPROVING_MEMORY_CONFIG_SH_LOADED=1
