#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SCRIPT="$SKILL_DIR/scripts/maintenance/install-nightly-maintenance.sh"
CHECK_SCRIPT="$SKILL_DIR/scripts/maintenance/check-installed-crontab-sync.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installed-crontab-sync-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_ROOT="$TMP_ROOT/home"
STATE_ROOT="$TMP_ROOT/state"
PROJECT_ROOT="$HOME_ROOT/project"
FAKE_BIN="$TMP_ROOT/bin"
CRONTAB_STATE="$TMP_ROOT/crontab.txt"

mkdir -p "$PROJECT_ROOT" "$STATE_ROOT" "$FAKE_BIN" "$HOME_ROOT/.codex/skills/memory-and-improvement"

cat > "$FAKE_BIN/crontab" <<EOF
#!/bin/bash
set -euo pipefail
STATE_FILE="$CRONTAB_STATE"

if [[ "\${1:-}" == "-l" ]]; then
    [[ -f "\$STATE_FILE" ]] && cat "\$STATE_FILE"
    exit 0
fi

if [[ "\${1:-}" == "-" ]]; then
    cat > "\$STATE_FILE"
    exit 0
fi

echo "Unsupported crontab args: \$*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/crontab"

cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = true
nightly_writeback = true
organize_min_recurrence = 2

[maintenance]
scope = "both"

[maintenance.schedule]
mode = "interval"
interval_minutes = 180
EOF

env \
    HOME="$HOME_ROOT" \
    PATH="$FAKE_BIN:$PATH" \
    XDG_STATE_HOME="$STATE_ROOT" \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$INSTALL_SCRIPT" --apply >/dev/null

initial_sync="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$CHECK_SCRIPT"
)"

assert_contains "$initial_sync" "cron block is in sync"

grep -c '^# BEGIN memory-and-improvement nightly maintenance$' "$CRONTAB_STATE" | grep -qx '1' || {
    printf 'Expected exactly one managed cron block after initial apply\n' >&2
    exit 1
}

cat > "$HOME_ROOT/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = true
nightly_writeback = true
organize_min_recurrence = 2

[maintenance]
scope = "both"

[maintenance.schedule]
mode = "interval"
interval_minutes = 240
EOF

set +e
drift_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$CHECK_SCRIPT" 2>&1
)"
drift_status=$?
set -e

if [[ "$drift_status" -eq 0 ]]; then
    printf 'Expected cron sync check to fail after config drift\n' >&2
    exit 1
fi

assert_contains "$drift_output" "out of sync"
assert_contains "$drift_output" "install-nightly-maintenance.sh --apply"

env \
    HOME="$HOME_ROOT" \
    PATH="$FAKE_BIN:$PATH" \
    XDG_STATE_HOME="$STATE_ROOT" \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$INSTALL_SCRIPT" --apply >/dev/null

resynced_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN:$PATH" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash "$CHECK_SCRIPT"
)"

assert_contains "$resynced_output" "cron block is in sync"
grep -c '^# BEGIN memory-and-improvement nightly maintenance$' "$CRONTAB_STATE" | grep -qx '1' || {
    printf 'Expected exactly one managed cron block after re-apply\n' >&2
    exit 1
}

printf 'installed-crontab-sync assertions passed\n'
