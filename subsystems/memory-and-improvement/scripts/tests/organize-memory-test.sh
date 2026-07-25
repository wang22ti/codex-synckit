#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORGANIZE_SCRIPT="$SKILL_DIR/scripts/maintenance/organize-memory.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/organize-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
STATE_ROOT="$TMP_ROOT/state"

mkdir -p "$PROJECT_MEMORY" "$STATE_ROOT"

cat > "$PROJECT_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-ORG-001] insight

**Logged**: 2026-04-02T00:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Keep maintenance review focused on valid recurring entries

### Details
This valid entry should still be parsed even if another entry is malformed.

### Suggested Action
Keep malformed entries from crashing review generation.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: organize.valid.entry
- Recurrence-Count: 2
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-02

---

## [LRN-ORG-BAD-001] insight

**Logged**: 2026-04-02T00:05:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Details
This malformed entry intentionally omits the Summary heading and summary body.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: organize.malformed.entry
- Recurrence-Count: 9
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-02

---
EOF

output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$ORGANIZE_SCRIPT" --scope project --min-recurrence 2
)"

assert_contains "$output" "Organized project memory:"
assert_contains_file "$PROJECT_MEMORY/REVIEW.md" "[LRN-ORG-001]"
assert_contains_file "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" "[LRN-ORG-001]"
assert_not_contains_file "$PROJECT_MEMORY/REVIEW.md" "[LRN-ORG-BAD-001]"
assert_not_contains_file "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" "[LRN-ORG-BAD-001]"

printf 'organize-memory assertions passed\n'
