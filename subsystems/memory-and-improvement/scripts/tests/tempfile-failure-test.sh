#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SCRIPT="$SKILL_DIR/scripts/maintenance/install-nightly-maintenance.sh"
UPDATE_SCRIPT="$SKILL_DIR/scripts/maintenance/update-skill-policy.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tempfile-failure-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
HOME_ROOT="$TMP_ROOT/home"
STATE_ROOT="$TMP_ROOT/state"
PROJECT_ROOT="$TMP_ROOT/project"
SKILL_FILE="$TMP_ROOT/SKILL.md"
CRONTAB_STATE="$TMP_ROOT/crontab.txt"

mkdir -p "$FAKE_BIN" "$HOME_ROOT" "$STATE_ROOT" "$PROJECT_ROOT/.learnings"

for cmd_name in bash basename dirname realpath grep awk find sort head tr sed cat mkdir date pwd perl python3 touch mv flock sleep rmdir; do
    if command -v "$cmd_name" >/dev/null 2>&1; then
        ln -s "$(command -v "$cmd_name")" "$FAKE_BIN/$cmd_name"
    fi
done

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

cat > "$PROJECT_ROOT/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-TMP-001] correction

**Logged**: 2026-04-03T10:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
Changing nightly defaults in defaults.toml must be paired with install-nightly-maintenance.sh --apply

### Details
This is a maintainer policy for the memory-and-improvement skill itself.

### Suggested Action
Keep live crontab refresh coupled to installed default changes.

### Metadata
- Source: user_feedback
- Related Files: none
- Tags: automation-policy,maintainer-policy,routing-policy

---
EOF

cat > "$SKILL_FILE" <<'EOF'
# Memory-and-Improvement Skill

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF

cat > "$FAKE_BIN/mktemp" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "mktemp failure" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/mktemp"

set +e
install_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        /bin/bash "$INSTALL_SCRIPT" --scope project --apply 2>&1
)"
install_status=$?
set -e

if [[ "$install_status" -eq 0 ]]; then
    printf 'Expected install-nightly-maintenance --apply to fail when mktemp fails\n' >&2
    exit 1
fi

assert_contains "$install_output" "Failed to allocate a temporary file while preparing the cron block."

set +e
update_output="$(
    env \
        HOME="$HOME_ROOT" \
        PATH="$FAKE_BIN" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_SKILL_FILE="$SKILL_FILE" \
        /bin/bash "$UPDATE_SCRIPT" 2>&1
)"
update_status=$?
set -e

if [[ "$update_status" -eq 0 ]]; then
    printf 'Expected update-skill-policy to fail when mktemp fails\n' >&2
    exit 1
fi

assert_contains "$update_output" "Failed to allocate a temporary file for rewriting the skill policy block."

printf 'tempfile failure assertions passed\n'
