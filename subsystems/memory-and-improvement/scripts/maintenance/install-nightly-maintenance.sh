#!/bin/bash
# Install or print a cron entry for nightly memory maintenance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
scope="$self_improving_maintenance_scope_default"
hour="$self_improving_maintenance_schedule_hour_default"
minute="$self_improving_maintenance_schedule_minute_default"
hour_set=false
minute_set=false
interval_set=false
apply=false
git_commit="$self_improving_git_autocommit_default"
writeback="$self_improving_nightly_writeback_default"
min_recurrence="$self_improving_organize_min_recurrence_default"
interval_minutes=""
interval_hours=""
project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
namespace="$self_improving_global_namespace"
global_memory_dir_override=""
if [[ "$self_improving_global_memory_dir_overridden" == true ]]; then
    global_memory_dir_override="$self_improving_global_memory_dir"
fi
log_dir="$self_improving_log_dir_default"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|global|both] [--hour HOUR] [--minute MINUTE] [--git-commit true|false] [--writeback true|false] [--min-recurrence N] [--apply]
       [--interval-minutes N | --interval-hours N]
       [--project-root PATH] [--project-memory-dir PATH] [--namespace NAME] [--global-memory-dir PATH]
       [--log-dir PATH]

Without --apply, prints the cron line you can install manually.
With --apply, updates the current crontab using a managed marker block.

Without scheduling flags, the installer uses the resolved config/default schedule.
Fixed mode uses --hour/--minute.
Interval mode uses a lightweight cron probe plus interval-maintenance.sh so runs can happen every N minutes or hours without relying on 24-hour cron divisibility.
EOF
}

gcd() {
    local a="$1"
    local b="$2"
    local tmp

    while (( b != 0 )); do
        tmp="$((a % b))"
        a="$b"
        b="$tmp"
    done

    printf '%s\n' "$a"
}

render_shell_part() {
    local part="$1"
    local key
    local value

    if [[ "$part" == *=* ]]; then
        key="${part%%=*}"
        value="${part#*=}"
        if [[ "$value" == "$HOME" ]]; then
            printf '%s=$HOME' "$key"
            return 0
        fi
        if [[ "$value" == "$HOME/"* ]]; then
            printf '%s=$HOME%s' "$key" "${value#$HOME}"
            return 0
        fi
    fi

    if [[ "$part" == "$HOME" ]]; then
        printf '$HOME'
        return 0
    fi

    if [[ "$part" == "$HOME/"* ]]; then
        printf '$HOME%s' "${part#$HOME}"
        return 0
    fi

    printf '%q' "$part"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --hour)
            hour="${2:-}"
            hour_set=true
            shift 2
            ;;
        --minute)
            minute="${2:-}"
            minute_set=true
            shift 2
            ;;
        --interval-minutes)
            interval_minutes="${2:-}"
            interval_set=true
            shift 2
            ;;
        --interval-hours)
            interval_hours="${2:-}"
            interval_set=true
            shift 2
            ;;
        --git-commit)
            git_commit="${2:-}"
            shift 2
            ;;
        --writeback)
            writeback="${2:-}"
            shift 2
            ;;
        --min-recurrence)
            min_recurrence="${2:-}"
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
        --namespace)
            namespace="${2:-}"
            shift 2
            ;;
        --global-memory-dir)
            global_memory_dir_override="${2:-}"
            shift 2
            ;;
        --log-dir)
            log_dir="${2:-}"
            shift 2
            ;;
        --apply)
            apply=true
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

if [[ -n "$interval_minutes" && -n "$interval_hours" ]]; then
    echo "Choose either --interval-minutes or --interval-hours, not both." >&2
    exit 1
fi

if [[ "$interval_set" == true && ( "$hour_set" == true || "$minute_set" == true ) ]]; then
    echo "Do not combine --interval-minutes/--interval-hours with --hour or --minute." >&2
    exit 1
fi

if [[ "$hour_set" == true || "$minute_set" == true ]]; then
    interval_minutes=""
fi

if [[ "$interval_set" != true && "$hour_set" != true && "$minute_set" != true && "$self_improving_maintenance_schedule_mode_default" == "interval" ]]; then
    interval_minutes="$self_improving_maintenance_schedule_interval_minutes_default"
fi

if [[ -n "$interval_hours" ]]; then
    [[ "$interval_hours" =~ ^[0-9]+$ ]] || {
        echo "--interval-hours must be a positive integer" >&2
        exit 1
    }
    if [[ "$interval_hours" -le 0 ]]; then
        echo "--interval-hours must be greater than 0" >&2
        exit 1
    fi
    interval_minutes="$((interval_hours * 60))"
fi

if [[ -n "$interval_minutes" ]]; then
    [[ "$interval_minutes" =~ ^[0-9]+$ ]] || {
        echo "--interval-minutes must be a positive integer" >&2
        exit 1
    }
    if [[ "$interval_minutes" -le 0 ]]; then
        echo "--interval-minutes must be greater than 0" >&2
        exit 1
    fi
    if [[ "$hour_set" == true || "$minute_set" == true ]]; then
        echo "Do not combine --interval-minutes/--interval-hours with --hour or --minute." >&2
        exit 1
    fi
fi

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
if [[ -n "$global_memory_dir_override" ]]; then
    global_memory_dir_override="$(self_improving_normalize_path "$global_memory_dir_override")"
fi
resolved_project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir")"
resolved_global_memory_dir=""
if [[ -n "$global_memory_dir_override" || "$scope" == "global" || "$scope" == "both" ]]; then
    resolved_global_memory_dir="$(self_improving_resolve_global_memory_dir "$namespace" "$global_memory_dir_override")"
fi
if [[ -n "$resolved_global_memory_dir" ]]; then
    self_improving_validate_memory_isolation_or_die "$resolved_project_memory_dir" "$resolved_global_memory_dir"
fi
log_dir="$(self_improving_normalize_path "$log_dir")"
mkdir -p "$log_dir"

mode_label="fixed-daily"

command_parts=(
    "SELF_IMPROVING_GLOBAL_ROOT=$self_improving_global_root"
    "SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT=$self_improving_global_namespaces_root"
    "SELF_IMPROVING_GIT_AUTOCOMMIT=$git_commit"
    "SELF_IMPROVING_NIGHTLY_WRITEBACK=$writeback"
    "SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE=$min_recurrence"
)

if [[ -n "$interval_minutes" ]]; then
    mode_label="interval"
    interval_state_file="$self_improving_state_root/interval-maintenance.last-run"
    command_parts+=(
        bash
        "$SCRIPT_DIR/interval-maintenance.sh"
        --interval-minutes
        "$interval_minutes"
        --scope
        "$scope"
        --project-root
        "$project_root"
        --namespace
        "$namespace"
        --writeback
        "$writeback"
        --min-recurrence
        "$min_recurrence"
        --state-file
        "$interval_state_file"
    )
else
    command_parts+=(
        bash
        "$SCRIPT_DIR/nightly-maintenance.sh"
        --scope
        "$scope"
        --project-root
        "$project_root"
        --namespace
        "$namespace"
        --writeback
        "$writeback"
        --min-recurrence
        "$min_recurrence"
    )
fi

if [[ -n "$project_memory_dir" ]]; then
    command_parts+=(--project-memory-dir "$project_memory_dir")
fi

if [[ -n "$global_memory_dir_override" ]]; then
    command_parts+=(--global-memory-dir "$global_memory_dir_override")
fi

command_string=""
for part in "${command_parts[@]}"; do
    quoted_part="$(render_shell_part "$part")"
    command_string+="${command_string:+ }$quoted_part"
done

log_file_quoted="$(render_shell_part "$log_dir/nightly-maintenance.log")"
inner_command="$command_string >> $log_file_quoted 2>&1"
printf -v inner_command_quoted '%q' "$inner_command"
if [[ -n "$interval_minutes" ]]; then
    probe_minutes="$(gcd "$interval_minutes" 60)"
    if [[ "$probe_minutes" -ge 60 ]]; then
        cron_schedule="0 * * * *"
    else
        cron_schedule="*/$probe_minutes * * * *"
    fi
else
    cron_schedule="$minute $hour * * *"
fi
cron_line="$cron_schedule /bin/bash -lc $inner_command_quoted"
begin_marker="# BEGIN memory-and-improvement nightly maintenance"
end_marker="# END memory-and-improvement nightly maintenance"

if [[ "$apply" != true ]]; then
    printf '# mode: %s\n' "$mode_label"
    printf '%s\n%s\n%s\n' "$begin_marker" "$cron_line" "$end_marker"
    exit 0
fi

if ! command -v crontab >/dev/null 2>&1; then
    echo "Cannot apply cron block because the crontab command is unavailable in PATH." >&2
    exit 1
fi

tmpfile="$(mktemp)" || {
    echo "Failed to allocate a temporary file while preparing the cron block." >&2
    exit 1
}
existing="$(mktemp)" || {
    rm -f "$tmpfile"
    echo "Failed to allocate a temporary file for the existing crontab snapshot." >&2
    exit 1
}

crontab -l > "$existing" 2>/dev/null || true
awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
' "$existing" > "$tmpfile"

{
    cat "$tmpfile"
    echo "$begin_marker"
    echo "$cron_line"
    echo "$end_marker"
} | crontab -

rm -f "$tmpfile" "$existing"
echo "Installed nightly maintenance cron entry."
