#!/bin/bash
# Print resolved maintenance defaults for platform-specific schedulers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

printf 'mode=%s\n' "$self_improving_maintenance_schedule_mode_default"
printf 'interval_minutes=%s\n' "$self_improving_maintenance_schedule_interval_minutes_default"
printf 'hour=%s\n' "$self_improving_maintenance_schedule_hour_default"
printf 'minute=%s\n' "$self_improving_maintenance_schedule_minute_default"
printf 'scope=%s\n' "$self_improving_maintenance_scope_default"
printf 'git_commit=%s\n' "$self_improving_git_autocommit_default"
printf 'writeback=%s\n' "$self_improving_nightly_writeback_default"
printf 'skill_policy_writeback=%s\n' "$self_improving_skill_policy_writeback_default"
printf 'min_recurrence=%s\n' "$self_improving_organize_min_recurrence_default"
printf 'namespace=%s\n' "$self_improving_global_namespace"
printf 'global_root=%s\n' "$self_improving_global_root"
printf 'global_namespaces_root=%s\n' "$self_improving_global_namespaces_root"
printf 'state_root=%s\n' "$self_improving_state_root"
