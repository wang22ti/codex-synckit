#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REVIEW_SCRIPT="$SKILL_DIR/scripts/recall/review-memory.sh"
INIT_SCRIPT="$SKILL_DIR/scripts/bootstrap/init-memory.sh"
LOG_ASSET_SCRIPT="$SKILL_DIR/scripts/capture/log-asset.sh"

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

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_ROOT="$TMP_DIR/project"
GLOBAL_ROOT="$TMP_DIR/global-memory"
STATE_ROOT="$TMP_DIR/state"
ACTIVE_ASSET="$TMP_DIR/active.pdf"
ARCHIVED_ASSET="$TMP_DIR/archived.pdf"

mkdir -p "$PROJECT_ROOT"
printf 'active\n' > "$ACTIVE_ASSET"
printf 'archived\n' > "$ARCHIVED_ASSET"

export SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT"
export SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT"
export SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces"
export SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile"
export XDG_STATE_HOME="$STATE_ROOT"

bash "$INIT_SCRIPT" --scope both --project-root "$PROJECT_ROOT" >/dev/null

cat <<'EOF' > "$PROJECT_ROOT/.learnings/SUMMARY.md"
# Project Summary

Current high-priority principles:
- Project summary should suppress raw entry previews in auto mode.
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/REVIEW.md"
# Project Memory Review

## Pending Items

- [LRN-REVIEW-001] high: Review preview remains visible.
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/LEARNINGS.md"
# Project Learnings

## [LRN-REVIEW-001] insight

**Logged**: 2026-04-03T00:00:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Project pending item should appear when include-entries is forced on

### Details
This entry exists to verify review fallback behavior.

### Suggested Action
Keep auto mode summary-first, but allow explicit entry previews.

### Metadata
- Source: conversation
- Related Files: review-memory.sh
- Tags: review
- Pattern-Key: memory_skill.review_project_pending
- Recurrence-Count: 1
- First-Seen: 2026-04-03
- Last-Seen: 2026-04-03

---
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/SUMMARY.md"
# User Profile Summary

Current high-priority facts:
- Global summary should suppress raw global entry previews in auto mode.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/.learnings/LEARNINGS.md"
# Global Learnings

## [LRN-REVIEW-GLOBAL-001] durable_fact

**Logged**: 2026-04-03T00:10:00Z
**Priority**: high
**Status**: pending
**Area**: profile

### Summary
Global pending item should appear when include-entries is forced on

### Details
This entry verifies global review fallback behavior.

### Suggested Action
Keep global review behavior symmetric with project review behavior.

### Metadata
- Source: conversation
- Related Files: PROFILE.md
- Tags: review
- Pattern-Key: memory_skill.review_global_pending
- Recurrence-Count: 1
- First-Seen: 2026-04-03
- Last-Seen: 2026-04-03

---
EOF

bash "$LOG_ASSET_SCRIPT" \
    --scope project \
    --project-root "$PROJECT_ROOT" \
    --title "Active Project Asset" \
    --type paper_pdf \
    --canonical-path "$ACTIVE_ASSET" \
    --summary "Active asset should appear in review output" >/dev/null

bash "$LOG_ASSET_SCRIPT" \
    --scope project \
    --project-root "$PROJECT_ROOT" \
    --title "Archived Project Asset" \
    --type paper_pdf \
    --canonical-path "$ARCHIVED_ASSET" \
    --summary "Archived asset should not appear in review output" \
    --status archived >/dev/null

auto_output="$(bash "$REVIEW_SCRIPT" --scope both --project-root "$PROJECT_ROOT" --namespace user-profile)"
assert_contains "$auto_output" "<memory-review>"
assert_contains "$auto_output" "Project summary highlights:"
assert_contains "$auto_output" "Project summary should suppress raw entry previews in auto mode."
assert_contains "$auto_output" "Project review highlights:"
assert_contains "$auto_output" "Review preview remains visible."
assert_contains "$auto_output" "Global summary highlights:"
assert_contains "$auto_output" "Global summary should suppress raw global entry previews in auto mode."
assert_not_contains "$auto_output" "Project pending high-priority items:"
assert_not_contains "$auto_output" "Global pending high-priority items:"
assert_contains "$auto_output" "Project indexed assets:"
assert_contains "$auto_output" "Active Project Asset"
assert_not_contains "$auto_output" "Archived Project Asset"

include_entries_output="$(bash "$REVIEW_SCRIPT" --scope both --project-root "$PROJECT_ROOT" --namespace user-profile --include-entries true)"
assert_contains "$include_entries_output" "Project pending high-priority items:"
assert_contains "$include_entries_output" "[LRN-REVIEW-001]"
assert_contains "$include_entries_output" "Global pending high-priority items:"
assert_contains "$include_entries_output" "[LRN-REVIEW-GLOBAL-001]"

PROJECT_ONLY_ROOT="$TMP_DIR/project-no-summary"
mkdir -p "$PROJECT_ONLY_ROOT/.learnings"
cat <<'EOF' > "$PROJECT_ONLY_ROOT/.learnings/LEARNINGS.md"
# Project Learnings

## [LRN-REVIEW-002] insight

**Logged**: 2026-04-03T00:20:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Auto mode should fall back to raw pending items when no summary or review exists

### Details
This entry makes the include-entries auto fallback observable.

### Suggested Action
Keep review output useful even for unorganized memories.

### Metadata
- Source: conversation
- Related Files: review-memory.sh
- Tags: review
- Pattern-Key: memory_skill.review_auto_fallback
- Recurrence-Count: 1
- First-Seen: 2026-04-03
- Last-Seen: 2026-04-03

---
EOF

fallback_output="$(bash "$REVIEW_SCRIPT" --scope project --project-root "$PROJECT_ONLY_ROOT")"
assert_contains "$fallback_output" "Project pending high-priority items:"
assert_contains "$fallback_output" "[LRN-REVIEW-002]"

printf 'review-memory assertions passed\n'
