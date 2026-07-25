#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REMOVE_SCRIPT="$SKILL_DIR/scripts/maintenance/remove-project-memory.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

assert_exists() {
    local path="$1"
    [[ -e "$path" ]] || {
        printf 'Expected path to exist: %s\n' "$path" >&2
        exit 1
    }
}

assert_not_exists() {
    local path="$1"
    [[ ! -e "$path" ]] || {
        printf 'Expected path not to exist: %s\n' "$path" >&2
        exit 1
    }
}

assert_contains_file() {
    local path="$1"
    local needle="$2"

    if ! grep -Fq -- "$needle" "$path"; then
        printf 'Expected %s to contain: %s\n' "$path" "$needle" >&2
        exit 1
    fi
}

assert_not_contains_file() {
    local path="$1"
    local needle="$2"

    if grep -Fq -- "$needle" "$path"; then
        printf 'Expected %s not to contain: %s\n' "$path" "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/remove-project-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
STATE_DIR="$TMP_ROOT/state"
PROJECT_DIR="$TMP_ROOT/project"
ARCHIVE_ROOT="$TMP_ROOT/archive"
REGISTRY_FILE="$STATE_DIR/memory-and-improvement/project-memory-registry.txt"

mkdir -p "$HOME_DIR/.codex/skills/memory-and-improvement" "$STATE_DIR" "$PROJECT_DIR/.learnings"
cat > "$PROJECT_DIR/PUBLICATIONS.md" <<'EOF'
# Publications
EOF
cat > "$PROJECT_DIR/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-RPM-001] learning

**Logged**: 2024-03-01T00:00:00Z
**Priority**: high
**Status**: pending
**Area**: publications

### Summary
Publication records should prefer the structured publications file over a homepage scrape.

### Details
This stable routing rule should be preserved before deleting the project memory.

### Suggested Action
Keep the structured factual file as the source of truth and only use external pages to fill missing links.

### Metadata
- Source: automation
- Related Files: PUBLICATIONS.md
- Tags: source-priority
- Pattern-Key: remove.project.memory
- Recurrence-Count: 2
- First-Seen: 2024-03-01
- Last-Seen: 2024-03-21

---
EOF

mkdir -p "$(dirname "$REGISTRY_FILE")"
cat > "$REGISTRY_FILE" <<EOF
$PROJECT_DIR/.learnings
EOF

set +e
blocked_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_DIR" \
        bash "$REMOVE_SCRIPT" --archive-root "$ARCHIVE_ROOT" 2>&1
)"
blocked_status=$?
set -e

if [[ "$blocked_status" -eq 0 ]]; then
    printf 'Expected removal with promotion candidates to stop\n' >&2
    exit 1
fi

assert_contains "$blocked_output" "Potential promotion candidates found before removing project memory"
assert_contains "$blocked_output" "[LRN-RPM-001]"
assert_exists "$PROJECT_DIR/.learnings"
assert_contains_file "$REGISTRY_FILE" "$PROJECT_DIR/.learnings"

allowed_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_DIR" \
        bash "$REMOVE_SCRIPT" --archive-root "$ARCHIVE_ROOT" --allow-unpromoted-candidates true
)"

assert_contains "$allowed_output" "Archived project memory to:"
assert_contains "$allowed_output" "Removed project memory registry entry:"
assert_contains "$allowed_output" "Potential promotion candidates found before removing project memory"
assert_contains "$allowed_output" "[LRN-RPM-001]"
assert_not_exists "$PROJECT_DIR/.learnings"
assert_not_contains_file "$REGISTRY_FILE" "$PROJECT_DIR/.learnings"

archived_dir="$(find "$ARCHIVE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
assert_exists "$archived_dir/LEARNINGS.md"

MISSING_PROJECT="$TMP_ROOT/missing-project"
mkdir -p "$MISSING_PROJECT"
cat > "$REGISTRY_FILE" <<EOF
$MISSING_PROJECT/.learnings
EOF

missing_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$MISSING_PROJECT" \
        bash "$REMOVE_SCRIPT"
)"

assert_contains "$missing_output" "Project memory directory does not exist; removed stale registry entry if present"
assert_not_contains_file "$REGISTRY_FILE" "$MISSING_PROJECT/.learnings"

DRY_RUN_PROJECT="$TMP_ROOT/dry-run-project"
mkdir -p "$DRY_RUN_PROJECT/.learnings"
cat > "$DRY_RUN_PROJECT/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
cat > "$REGISTRY_FILE" <<EOF
$DRY_RUN_PROJECT/.learnings
EOF

dry_run_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$DRY_RUN_PROJECT" \
        bash "$REMOVE_SCRIPT" --dry-run true
)"

assert_contains "$dry_run_output" "Dry run only. No files changed for project memory"
assert_exists "$DRY_RUN_PROJECT/.learnings"
assert_contains_file "$REGISTRY_FILE" "$DRY_RUN_PROJECT/.learnings"

PURGE_PROJECT="$TMP_ROOT/purge-project"
mkdir -p "$PURGE_PROJECT/.learnings"
cat > "$PURGE_PROJECT/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
cat > "$REGISTRY_FILE" <<EOF
$PURGE_PROJECT/.learnings
EOF

purge_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$PURGE_PROJECT" \
        bash "$REMOVE_SCRIPT" --archive-mode purge
)"

assert_contains "$purge_output" "Deleted project memory directory:"
assert_contains "$purge_output" "Removed project memory registry entry:"
assert_not_exists "$PURGE_PROJECT/.learnings"
assert_not_contains_file "$REGISTRY_FILE" "$PURGE_PROJECT/.learnings"

COLLISION_PROJECT="$TMP_ROOT/collision-project"
COLLISION_ARCHIVE_ROOT="$TMP_ROOT/collision-archive"
COLLISION_FAKE_BIN="$TMP_ROOT/collision-bin"
COLLISION_TIMESTAMP="20260403T120000Z"
mkdir -p "$COLLISION_PROJECT/.learnings" "$COLLISION_ARCHIVE_ROOT/collision-project-$COLLISION_TIMESTAMP" "$COLLISION_FAKE_BIN"
cat > "$COLLISION_PROJECT/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
cat > "$COLLISION_FAKE_BIN/date" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\$#" -eq 2 && "\$1" == "-u" && "\$2" == "+%Y%m%dT%H%M%SZ" ]]; then
    printf '%s\n' "$COLLISION_TIMESTAMP"
    exit 0
fi
exec /bin/date "\$@"
EOF
chmod +x "$COLLISION_FAKE_BIN/date"
cat > "$REGISTRY_FILE" <<EOF
$COLLISION_PROJECT/.learnings
EOF

collision_output="$(
    env \
        HOME="$HOME_DIR" \
        PATH="$COLLISION_FAKE_BIN:$PATH" \
        XDG_STATE_HOME="$STATE_DIR" \
        SELF_IMPROVING_PROJECT_ROOT="$COLLISION_PROJECT" \
        bash "$REMOVE_SCRIPT" --archive-root "$COLLISION_ARCHIVE_ROOT"
)"

assert_contains "$collision_output" "Archived project memory to: $COLLISION_ARCHIVE_ROOT/collision-project-$COLLISION_TIMESTAMP-2"
assert_exists "$COLLISION_ARCHIVE_ROOT/collision-project-$COLLISION_TIMESTAMP"
assert_exists "$COLLISION_ARCHIVE_ROOT/collision-project-$COLLISION_TIMESTAMP-2/LEARNINGS.md"
assert_not_exists "$COLLISION_PROJECT/.learnings"

INTERACT_PROJECT="$TMP_ROOT/interact-project"
INTERACT_MISSING="$TMP_ROOT/interact-missing"
INTERACT_STATE="$TMP_ROOT/interact-state"
mkdir -p "$INTERACT_PROJECT/.learnings" "$INTERACT_STATE"
cat > "$INTERACT_PROJECT/.learnings/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
INTERACT_REGISTRY="$INTERACT_STATE/memory-and-improvement/project-memory-registry.txt"
mkdir -p "$(dirname "$INTERACT_REGISTRY")"
cat > "$INTERACT_REGISTRY" <<EOF
$INTERACT_PROJECT/.learnings
$INTERACT_MISSING/.learnings
EOF

interact_remove_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$INTERACT_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$INTERACT_PROJECT" \
        bash "$REMOVE_SCRIPT" --archive-mode purge
)"

assert_contains "$interact_remove_output" "Deleted project memory directory:"
assert_not_contains_file "$INTERACT_REGISTRY" "$INTERACT_PROJECT/.learnings"
assert_contains_file "$INTERACT_REGISTRY" "$INTERACT_MISSING/.learnings"

NIGHTLY_SCRIPT="$SKILL_DIR/scripts/maintenance/nightly-maintenance.sh"
interact_nightly_output="$(
    env \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$INTERACT_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$INTERACT_PROJECT" \
        bash "$NIGHTLY_SCRIPT" --scope project --writeback false
)"

assert_contains "$interact_nightly_output" "Nightly maintenance pruned missing project memory registry entry: $INTERACT_MISSING/.learnings"
assert_contains "$interact_nightly_output" "Nightly maintenance skipped project scope: no existing project memory directories found"
assert_not_contains_file "$INTERACT_REGISTRY" "$INTERACT_MISSING/.learnings"

printf 'remove-project-memory assertions passed\n'
