#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRITEBACK_SCRIPT="$SKILL_DIR/scripts/maintenance/writeback-memory.sh"

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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/writeback-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_MEMORY" "$STATE_ROOT"

cat > "$PROJECT_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-WB-001] insight

**Logged**: 2026-03-01T00:00:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Keep docs consistency checks visible in review

### Details
This is a durable repo convention that recurs across maintenance work.

### Suggested Action
Keep summary-level reminders easy to load.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: docs.consistency.visible
- Recurrence-Count: 2
- First-Seen: 2026-03-01
- Last-Seen: 2026-03-21

---

## [LRN-WB-002] best_practice

**Logged**: 2026-03-10T00:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Regenerate the scaffolding workflow after schema changes

### Details
After schema changes, regenerate the scaffolding, then validate the output, then update the golden files, then rerun tests. This workflow should be followed as a reusable checklist.

### Suggested Action
Turn this into a repeatable skill when it stabilizes.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: schema.regeneration.workflow
- Recurrence-Count: 4
- First-Seen: 2026-03-10
- Last-Seen: 2026-03-20

---

## [LRN-WB-003] best_practice

**Logged**: 2026-03-05T00:00:00Z
**Priority**: medium
**Status**: promoted_to_summary
**Area**: docs

### Summary
Keep the old reusable release checklist visible

### Details
This reusable workflow still reads like a procedural checklist.

### Suggested Action
Keep it visible while the summary status is still active.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: release.checklist.visible
- Recurrence-Count: 1
- First-Seen: 2026-03-05
- Last-Seen: 2026-03-18

---
EOF

cat > "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" <<'EOF'
# Project Summary Candidates

**Threshold**: recurrence >= 2
**Policy**: advisory review hints only; not every recurring item should be promoted

- [LRN-WB-001] x2 (insight, pending): Keep docs consistency checks visible in review
EOF

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$WRITEBACK_SCRIPT" --scope project --min-recurrence 3 >/dev/null

SUMMARY_FILE="$PROJECT_MEMORY/SUMMARY.md"
assert_not_contains_file "$SUMMARY_FILE" "[LRN-WB-001]"
assert_not_contains_file "$SUMMARY_FILE" "[LRN-WB-002]"
assert_contains_file "$SUMMARY_FILE" "[LRN-WB-003]"

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$STATE_ROOT" \
    bash "$WRITEBACK_SCRIPT" --scope project --min-recurrence 2 >/dev/null

assert_contains_file "$SUMMARY_FILE" "[LRN-WB-001]"
assert_not_contains_file "$SUMMARY_FILE" "[LRN-WB-002]"
assert_contains_file "$SUMMARY_FILE" "[LRN-WB-003]"
assert_contains_file "$PROJECT_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"

printf 'writeback-memory assertions passed\n'
