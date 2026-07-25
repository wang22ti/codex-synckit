#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATHS_SCRIPT="$SKILL_DIR/scripts/shared/memory-paths.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'Expected output not to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-config-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

DEFAULT_HOME="$TMP_ROOT/default-home"
HOME_ROOT="$TMP_ROOT/home"
PROJECT_ROOT="$TMP_ROOT/project"
XDG_ROOT="$TMP_ROOT/xdg"
BAD_HOME="$TMP_ROOT/bad-home"

mkdir -p \
    "$DEFAULT_HOME" \
    "$HOME_ROOT/.codex/skills/memory-and-improvement" \
    "$PROJECT_ROOT" \
    "$XDG_ROOT" \
    "$BAD_HOME/.codex/skills/memory-and-improvement"

default_output="$(
    env \
        HOME="$DEFAULT_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
            printf "global_namespace=%s\n" "$self_improving_global_namespace"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
            printf "codex_home=%s\n" "$self_improving_codex_home"
            printf "codex_skills_dir=%s\n" "$self_improving_codex_skills_dir"
            printf "git_autocommit=%s\n" "$self_improving_git_autocommit_default"
            printf "nightly_writeback=%s\n" "$self_improving_nightly_writeback_default"
            printf "skill_policy_writeback=%s\n" "$self_improving_skill_policy_writeback_default"
            printf "organize_min_recurrence=%s\n" "$self_improving_organize_min_recurrence_default"
            printf "maintenance_scope=%s\n" "$self_improving_maintenance_scope_default"
            printf "schedule_mode=%s\n" "$self_improving_maintenance_schedule_mode_default"
            printf "schedule_hour=%s\n" "$self_improving_maintenance_schedule_hour_default"
            printf "schedule_minute=%s\n" "$self_improving_maintenance_schedule_minute_default"
            printf "schedule_interval=%s\n" "$self_improving_maintenance_schedule_interval_minutes_default"
        '
)"

assert_contains "$default_output" "global_root=$DEFAULT_HOME/global-memory"
assert_contains "$default_output" "global_namespaces_root=$DEFAULT_HOME/global-memory/namespaces"
assert_contains "$default_output" "global_namespace=research-principle"
assert_contains "$default_output" "state_root=$DEFAULT_HOME/.local/state/memory-and-improvement"
assert_contains "$default_output" "log_dir=$DEFAULT_HOME/.local/state/memory-and-improvement/logs"
assert_contains "$default_output" "codex_home=$DEFAULT_HOME/.codex"
assert_contains "$default_output" "codex_skills_dir=$DEFAULT_HOME/.codex/skills"
assert_contains "$default_output" "git_autocommit=true"
assert_contains "$default_output" "nightly_writeback=true"
assert_contains "$default_output" "skill_policy_writeback=false"
assert_contains "$default_output" "organize_min_recurrence=2"
assert_contains "$default_output" "maintenance_scope=both"
assert_contains "$default_output" "schedule_mode=interval"
assert_contains "$default_output" "schedule_hour=4"
assert_contains "$default_output" "schedule_minute=0"
assert_contains "$default_output" "schedule_interval=240"

xdg_default_output="$(
    env \
        HOME="$DEFAULT_HOME" \
        XDG_STATE_HOME="$XDG_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
        '
)"

assert_contains "$xdg_default_output" "state_root=$XDG_ROOT/memory-and-improvement"
assert_contains "$xdg_default_output" "log_dir=$XDG_ROOT/memory-and-improvement/logs"

cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[paths]
global_root = "$HOME/config-global"
global_namespaces_root = "$HOME/config-global/custom-namespaces"
state_root = "$HOME/config-state/runtime"
log_dir = "$HOME/config-logs"
codex_home = "$HOME/config-codex"
codex_skills_dir = "$HOME/config-codex/custom-skills"

[defaults]
global_namespace = "project"
git_autocommit = true
nightly_writeback = true
skill_policy_writeback = false
organize_min_recurrence = 7

[maintenance]
scope = "global"

[maintenance.schedule]
mode = "interval"
hour = 5
minute = 45
interval_minutes = 180
EOF

config_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
            printf "global_namespace=%s\n" "$self_improving_global_namespace"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
            printf "codex_home=%s\n" "$self_improving_codex_home"
            printf "codex_skills_dir=%s\n" "$self_improving_codex_skills_dir"
            printf "git_autocommit=%s\n" "$self_improving_git_autocommit_default"
            printf "nightly_writeback=%s\n" "$self_improving_nightly_writeback_default"
            printf "skill_policy_writeback=%s\n" "$self_improving_skill_policy_writeback_default"
            printf "organize_min_recurrence=%s\n" "$self_improving_organize_min_recurrence_default"
            printf "maintenance_scope=%s\n" "$self_improving_maintenance_scope_default"
            printf "schedule_mode=%s\n" "$self_improving_maintenance_schedule_mode_default"
            printf "schedule_hour=%s\n" "$self_improving_maintenance_schedule_hour_default"
            printf "schedule_minute=%s\n" "$self_improving_maintenance_schedule_minute_default"
            printf "schedule_interval=%s\n" "$self_improving_maintenance_schedule_interval_minutes_default"
        '
)"

assert_contains "$config_output" "global_root=$HOME_ROOT/config-global"
assert_contains "$config_output" "global_namespaces_root=$HOME_ROOT/config-global/custom-namespaces"
assert_contains "$config_output" "global_namespace=project"
assert_contains "$config_output" "state_root=$HOME_ROOT/config-state/runtime"
assert_contains "$config_output" "log_dir=$HOME_ROOT/config-logs"
assert_contains "$config_output" "codex_home=$HOME_ROOT/config-codex"
assert_contains "$config_output" "codex_skills_dir=$HOME_ROOT/config-codex/custom-skills"
assert_contains "$config_output" "git_autocommit=true"
assert_contains "$config_output" "nightly_writeback=true"
assert_contains "$config_output" "skill_policy_writeback=false"
assert_contains "$config_output" "organize_min_recurrence=7"
assert_contains "$config_output" "maintenance_scope=global"
assert_contains "$config_output" "schedule_mode=interval"
assert_contains "$config_output" "schedule_hour=5"
assert_contains "$config_output" "schedule_minute=45"
assert_contains "$config_output" "schedule_interval=180"

root_derived_output="$(
    env \
        HOME="$DEFAULT_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$TMP_ROOT/env-global-derived" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
        '
)"

assert_contains "$root_derived_output" "global_root=$TMP_ROOT/env-global-derived"
assert_contains "$root_derived_output" "global_namespaces_root=$TMP_ROOT/env-global-derived/namespaces"

env_override_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$XDG_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$TMP_ROOT/env-global" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile" \
        SELF_IMPROVING_GIT_AUTOCOMMIT="false" \
        SELF_IMPROVING_NIGHTLY_WRITEBACK="false" \
        SELF_IMPROVING_SKILL_POLICY_WRITEBACK="true" \
        SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE="3" \
        CODEX_HOME="$TMP_ROOT/env-codex" \
        SELF_IMPROVING_CODEX_SKILLS_DIR="$TMP_ROOT/env-skills" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
            printf "global_namespace=%s\n" "$self_improving_global_namespace"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
            printf "codex_home=%s\n" "$self_improving_codex_home"
            printf "codex_skills_dir=%s\n" "$self_improving_codex_skills_dir"
            printf "git_autocommit=%s\n" "$self_improving_git_autocommit_default"
            printf "nightly_writeback=%s\n" "$self_improving_nightly_writeback_default"
            printf "skill_policy_writeback=%s\n" "$self_improving_skill_policy_writeback_default"
            printf "organize_min_recurrence=%s\n" "$self_improving_organize_min_recurrence_default"
        '
)"

assert_contains "$env_override_output" "global_root=$TMP_ROOT/env-global"
assert_contains "$env_override_output" "global_namespaces_root=$HOME_ROOT/config-global/custom-namespaces"
assert_contains "$env_override_output" "global_namespace=user-profile"
assert_contains "$env_override_output" "state_root=$XDG_ROOT/memory-and-improvement"
assert_contains "$env_override_output" "log_dir=$HOME_ROOT/config-logs"
assert_contains "$env_override_output" "codex_home=$TMP_ROOT/env-codex"
assert_contains "$env_override_output" "codex_skills_dir=$TMP_ROOT/env-skills"
assert_contains "$env_override_output" "git_autocommit=false"
assert_contains "$env_override_output" "nightly_writeback=false"
assert_contains "$env_override_output" "skill_policy_writeback=true"
assert_contains "$env_override_output" "organize_min_recurrence=3"

explicit_namespaces_override_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$TMP_ROOT/env-global-root/../env-global-root" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$TMP_ROOT/env-namespaces-root/./custom" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
        '
)"

assert_contains "$explicit_namespaces_override_output" "global_root=$TMP_ROOT/env-global-root"
assert_contains "$explicit_namespaces_override_output" "global_namespaces_root=$TMP_ROOT/env-namespaces-root/custom"

config_canonical_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
        '
)"

assert_contains "$config_canonical_output" "state_root=$HOME_ROOT/config-state/runtime"
assert_contains "$config_canonical_output" "log_dir=$HOME_ROOT/config-logs"
assert_contains "$config_canonical_output" "global_root=$HOME_ROOT/config-global"
assert_contains "$config_canonical_output" "global_namespaces_root=$HOME_ROOT/config-global/custom-namespaces"

cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[paths]
global_root = "$HOME/config-global/./"
global_namespaces_root = "$HOME/config-global/../config-global/custom-namespaces/"
state_root = "$HOME/config-state/./runtime/"
log_dir = "$HOME/config-state/./runtime/logs/"
codex_home = "$HOME/config-codex/./"
codex_skills_dir = "$HOME/config-codex/skills/../skills/"
EOF

canonicalized_paths_output="$(
    env \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc '
            source "'"$PATHS_SCRIPT"'"
            printf "global_root=%s\n" "$self_improving_global_root"
            printf "global_namespaces_root=%s\n" "$self_improving_global_namespaces_root"
            printf "state_root=%s\n" "$self_improving_state_root"
            printf "log_dir=%s\n" "$self_improving_log_dir_default"
            printf "codex_home=%s\n" "$self_improving_codex_home"
            printf "codex_skills_dir=%s\n" "$self_improving_codex_skills_dir"
        '
)"

assert_contains "$canonicalized_paths_output" "global_root=$HOME_ROOT/config-global"
assert_contains "$canonicalized_paths_output" "global_namespaces_root=$HOME_ROOT/config-global/custom-namespaces"
assert_contains "$canonicalized_paths_output" "state_root=$HOME_ROOT/config-state/runtime"
assert_contains "$canonicalized_paths_output" "log_dir=$HOME_ROOT/config-state/runtime/logs"
assert_contains "$canonicalized_paths_output" "codex_home=$HOME_ROOT/config-codex"
assert_contains "$canonicalized_paths_output" "codex_skills_dir=$HOME_ROOT/config-codex/skills"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[paths]
unknown_path = "$HOME/nope"
EOF

set +e
bad_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_status=$?
set -e

if [[ "$bad_status" -eq 0 ]]; then
    printf 'Expected invalid config to fail\n' >&2
    exit 1
fi

assert_contains "$bad_output" "unsupported config key: paths.unknown_path"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[unsupported]
value = "nope"
EOF

set +e
bad_section_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_section_status=$?
set -e

if [[ "$bad_section_status" -eq 0 ]]; then
    printf 'Expected invalid section to fail\n' >&2
    exit 1
fi

assert_contains "$bad_section_output" "unsupported section 'unsupported'"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
nightly_writeback = maybe
EOF

set +e
bad_bool_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_bool_status=$?
set -e

if [[ "$bad_bool_status" -eq 0 ]]; then
    printf 'Expected invalid boolean to fail\n' >&2
    exit 1
fi

assert_contains "$bad_bool_output" "invalid boolean for defaults.nightly_writeback"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[paths]
global_root = $HOME/nope
EOF

set +e
bad_string_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_string_status=$?
set -e

if [[ "$bad_string_status" -eq 0 ]]; then
    printf 'Expected invalid string value to fail\n' >&2
    exit 1
fi

assert_contains "$bad_string_output" "invalid string for paths.global_root"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[maintenance.schedule]
hour = 24
EOF

set +e
bad_hour_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_hour_status=$?
set -e

if [[ "$bad_hour_status" -eq 0 ]]; then
    printf 'Expected invalid maintenance.schedule.hour to fail\n' >&2
    exit 1
fi

assert_contains "$bad_hour_output" "maintenance.schedule.hour must be between 0 and 23"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[maintenance.schedule]
hour = -1
EOF

set +e
bad_negative_hour_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_negative_hour_status=$?
set -e

if [[ "$bad_negative_hour_status" -eq 0 ]]; then
    printf 'Expected negative maintenance.schedule.hour to fail\n' >&2
    exit 1
fi

assert_contains "$bad_negative_hour_output" "invalid integer for maintenance.schedule.hour"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[maintenance.schedule]
minute = 60
EOF

set +e
bad_minute_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_minute_status=$?
set -e

if [[ "$bad_minute_status" -eq 0 ]]; then
    printf 'Expected invalid maintenance.schedule.minute to fail\n' >&2
    exit 1
fi

assert_contains "$bad_minute_output" "maintenance.schedule.minute must be between 0 and 59"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[maintenance.schedule]
interval_minutes = 0
EOF

set +e
bad_interval_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_interval_status=$?
set -e

if [[ "$bad_interval_status" -eq 0 ]]; then
    printf 'Expected invalid maintenance.schedule.interval_minutes to fail\n' >&2
    exit 1
fi

assert_contains "$bad_interval_output" "maintenance.schedule.interval_minutes must be greater than 0"

cat > "$BAD_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[maintenance.schedule]
mode = "weekly"
EOF

set +e
bad_mode_output="$(
    env \
        HOME="$BAD_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"' 2>&1
)"
bad_mode_status=$?
set -e

if [[ "$bad_mode_status" -eq 0 ]]; then
    printf 'Expected invalid maintenance.schedule.mode to fail\n' >&2
    exit 1
fi

assert_contains "$bad_mode_output" "invalid maintenance.schedule.mode: weekly"

printf 'memory-config assertions passed\n'
