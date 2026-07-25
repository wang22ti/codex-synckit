#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SCRIPT="$SKILL_DIR/scripts/maintenance/install-nightly-maintenance.sh"
CHECK_SYNC_SCRIPT="$SKILL_DIR/scripts/maintenance/check-crontab-sync.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/install-nightly-maintenance-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_ROOT="$TMP_ROOT/home"
STATE_ROOT="$TMP_ROOT/state"
PROJECT_ROOT="$HOME_ROOT/project"
FAKE_BIN="$TMP_ROOT/bin"
FAKE_CRONTAB_FILE="$TMP_ROOT/fake-crontab.txt"

mkdir -p "$PROJECT_ROOT" "$STATE_ROOT" "$FAKE_BIN"

cat > "$FAKE_BIN/crontab" <<'EOF'
#!/bin/bash
set -euo pipefail

target_file="${FAKE_CRONTAB_FILE:?}"

case "${1:-}" in
    -l)
        if [[ -f "$target_file" ]]; then
            cat "$target_file"
            exit 0
        fi
        exit 1
        ;;
    -)
        cat > "$target_file"
        exit 0
        ;;
    *)
        printf 'fake crontab does not support args: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$FAKE_BIN/crontab"

fixed_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --hour 4 --minute 0 --writeback true
)"

assert_contains "$fixed_output" "# mode: fixed-daily"
assert_contains "$fixed_output" "0 4 * * *"
assert_contains "$fixed_output" "scripts/maintenance/nightly-maintenance.sh"
assert_contains "$fixed_output" "SELF_IMPROVING_GLOBAL_ROOT=\\\$HOME/global-memory"
assert_contains "$fixed_output" "SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT=\\\$HOME/global-memory/namespaces"
assert_contains "$fixed_output" '--project-root\ \$HOME/project'
assert_contains "$fixed_output" '--namespace\ research-principle'

interval_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --interval-minutes 90 --writeback true
)"

assert_contains "$interval_output" "# mode: interval"
assert_contains "$interval_output" "*/30 * * * *"
assert_contains "$interval_output" "scripts/maintenance/interval-maintenance.sh"
assert_contains "$interval_output" "SELF_IMPROVING_GLOBAL_ROOT=\\\$HOME/global-memory"
assert_contains "$interval_output" "SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT=\\\$HOME/global-memory/namespaces"
assert_contains "$interval_output" '--interval-minutes\ 90'
assert_contains "$interval_output" "interval-maintenance.last-run"

interval_gcd_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --interval-minutes 75 --writeback true
)"

assert_contains "$interval_gcd_output" "# mode: interval"
assert_contains "$interval_gcd_output" "*/15 * * * *"
assert_contains "$interval_gcd_output" '--interval-minutes\ 75'

interval_hours_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --interval-hours 2 --writeback true
)"

assert_contains "$interval_hours_output" "# mode: interval"
assert_contains "$interval_hours_output" "0 * * * *"
assert_contains "$interval_hours_output" '--interval-minutes\ 120'

set +e
conflict_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --interval-minutes 90 --hour 4 2>&1
)"
conflict_status=$?
set -e

if [[ "$conflict_status" -eq 0 ]]; then
    printf 'Expected scheduling flag conflict to fail\n' >&2
    exit 1
fi

assert_contains "$conflict_output" "Do not combine --interval-minutes/--interval-hours with --hour or --minute."

set +e
zero_interval_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --interval-minutes 0 2>&1
)"
zero_interval_status=$?
set -e

if [[ "$zero_interval_status" -eq 0 ]]; then
    printf 'Expected zero interval minutes to fail\n' >&2
    exit 1
fi

assert_contains "$zero_interval_output" "--interval-minutes must be greater than 0"

mkdir -p "$HOME_ROOT/.codex/skills/memory-and-improvement"
cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = true
nightly_writeback = true
organize_min_recurrence = 5

[maintenance]
scope = "global"

[maintenance.schedule]
mode = "interval"
hour = 4
minute = 0
interval_minutes = 180
EOF

config_output="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT"
)"

assert_contains "$config_output" "# mode: interval"
assert_contains "$config_output" "0 * * * *"
assert_contains "$config_output" '--scope\ global'
assert_contains "$config_output" '--namespace\ research-principle'
assert_contains "$config_output" "SELF_IMPROVING_GIT_AUTOCOMMIT=true"
assert_contains "$config_output" "SELF_IMPROVING_NIGHTLY_WRITEBACK=true"
assert_contains "$config_output" "SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE=5"
assert_contains "$config_output" "SELF_IMPROVING_GLOBAL_ROOT=\\\$HOME/global-memory"
assert_contains "$config_output" "SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT=\\\$HOME/global-memory/namespaces"
assert_contains "$config_output" '--interval-minutes\ 180'

apply_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        FAKE_CRONTAB_FILE="$FAKE_CRONTAB_FILE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --interval-minutes 90 --writeback true --apply
)"

assert_contains "$apply_output" "Installed nightly maintenance cron entry."
installed_crontab="$(cat "$FAKE_CRONTAB_FILE")"
assert_contains "$installed_crontab" "# BEGIN memory-and-improvement nightly maintenance"
assert_contains "$installed_crontab" "# END memory-and-improvement nightly maintenance"
assert_contains "$installed_crontab" "*/30 * * * *"
assert_contains "$installed_crontab" "scripts/maintenance/interval-maintenance.sh"
assert_contains "$installed_crontab" '--interval-minutes\ 90'

sync_ok_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        FAKE_CRONTAB_FILE="$FAKE_CRONTAB_FILE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$CHECK_SYNC_SCRIPT" --scope both --interval-minutes 90 --writeback true
)"

assert_contains "$sync_ok_output" "Crontab sync check passed."

reapply_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        FAKE_CRONTAB_FILE="$FAKE_CRONTAB_FILE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT" --scope both --hour 5 --minute 10 --writeback false --apply
)"

assert_contains "$reapply_output" "Installed nightly maintenance cron entry."
reinstalled_crontab="$(cat "$FAKE_CRONTAB_FILE")"
assert_contains "$reinstalled_crontab" "10 5 * * *"
assert_contains "$reinstalled_crontab" "scripts/maintenance/nightly-maintenance.sh"
assert_contains "$reinstalled_crontab" '--writeback\ false'
assert_contains "$reinstalled_crontab" "SELF_IMPROVING_NIGHTLY_WRITEBACK=false"
if printf '%s' "$reinstalled_crontab" | grep -Fq -- '--interval-minutes\ 90'; then
    printf 'Expected re-applied crontab to replace the previous interval command\n' >&2
    exit 1
fi

cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = false
nightly_writeback = true
organize_min_recurrence = 9

[maintenance]
scope = "project"

[maintenance.schedule]
mode = "interval"
hour = 4
minute = 0
interval_minutes = 240
EOF

printed_only_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        FAKE_CRONTAB_FILE="$FAKE_CRONTAB_FILE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$INSTALL_SCRIPT"
)"

assert_contains "$printed_only_output" "# mode: interval"
assert_contains "$printed_only_output" '--interval-minutes\ 240'

unchanged_installed_crontab="$(cat "$FAKE_CRONTAB_FILE")"
assert_contains "$unchanged_installed_crontab" "10 5 * * *"
if printf '%s' "$unchanged_installed_crontab" | grep -Fq -- '--interval-minutes\ 240'; then
    printf 'Expected printed-only installer output not to mutate the installed crontab\n' >&2
    exit 1
fi

set +e
sync_stale_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        FAKE_CRONTAB_FILE="$FAKE_CRONTAB_FILE" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$CHECK_SYNC_SCRIPT" 2>&1
)"
sync_stale_status=$?
set -e

if [[ "$sync_stale_status" -eq 0 ]]; then
    printf 'Expected crontab sync check to fail for stale installed cron block\n' >&2
    exit 1
fi

assert_contains "$sync_stale_output" "Crontab sync check failed: installed cron block does not match current resolved installer output."

NO_CRONTAB_BIN="$TMP_ROOT/no-crontab-bin"
mkdir -p "$NO_CRONTAB_BIN"
for cmd_name in bash basename dirname realpath grep awk find sort head tr sed cat mktemp mkdir date pwd; do
    ln -s "$(command -v "$cmd_name")" "$NO_CRONTAB_BIN/$cmd_name"
done

set +e
missing_crontab_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$NO_CRONTAB_BIN" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        /bin/bash "$INSTALL_SCRIPT" --scope project --apply 2>&1
)"
missing_crontab_status=$?
set -e

if [[ "$missing_crontab_status" -eq 0 ]]; then
    printf 'Expected --apply to fail clearly when crontab is unavailable\n' >&2
    exit 1
fi

assert_contains "$missing_crontab_output" "Cannot apply cron block because the crontab command is unavailable in PATH."

printf 'install-nightly-maintenance assertions passed\n'
