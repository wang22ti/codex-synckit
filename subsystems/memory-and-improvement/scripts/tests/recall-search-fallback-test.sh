#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEARCH_SCRIPT="$SKILL_DIR/scripts/recall/search-memory.sh"
RECALL_SCRIPT="$SKILL_DIR/scripts/recall/recall-memory.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/recall-search-fallback-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
HOME_ROOT="$TMP_ROOT/home"
PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"

mkdir -p "$FAKE_BIN" "$HOME_ROOT" "$PROJECT_MEMORY"

for cmd_name in bash basename dirname realpath grep awk find sort head tr sed cat mktemp; do
    cmd_path="$(command -v "$cmd_name")"
    ln -s "$cmd_path" "$FAKE_BIN/$cmd_name"
done

cat > "$PROJECT_MEMORY/SUMMARY.md" <<'EOF'
# Project Summary

Current high-priority principles:
- Fallback search should still find summary-layer hits without rg.
EOF

cat > "$PROJECT_MEMORY/REVIEW.md" <<'EOF'
# Project Memory Review

## Pending Items

- [LRN-FALLBACK-001] medium: Fallback review path stays visible without rg.
EOF

cat > "$PROJECT_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

## [LRN-FALLBACK-001] best_practice

**Logged**: 2026-04-02T00:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Fallback raw search still works without rg

### Details
This entry proves full-script search and recall still function when the PATH does not include rg.

### Suggested Action
Keep grep fallback behavior covered at the script level.

### Metadata
- Source: conversation
- Related Files: search-memory.sh
- Tags: fallback
- Pattern-Key: fallback.search.no_rg
- Recurrence-Count: 1
- First-Seen: 2026-04-02
- Last-Seen: 2026-04-02

---
EOF

search_output="$(
    env \
        PATH="$FAKE_BIN" \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        /bin/bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "summary-layer hits"
)"

assert_contains "$search_output" "<memory-search>"
assert_contains "$search_output" "[DOC-SUMMARY]"
assert_contains "$search_output" "Fallback search should still find summary-layer hits without rg."

recall_output="$(
    env \
        PATH="$FAKE_BIN" \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        /bin/bash "$RECALL_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "fallback raw search"
)"

assert_contains "$recall_output" "<memory-recall>"
assert_contains "$recall_output" "Resolved-Scope: project"
assert_contains "$recall_output" "Search:"
assert_contains "$recall_output" "[LRN-FALLBACK-001]"
assert_contains "$recall_output" "Fallback raw search still works without rg"

printf 'recall-search fallback assertions passed\n'
