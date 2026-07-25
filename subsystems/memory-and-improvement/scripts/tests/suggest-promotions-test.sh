#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUGGEST_SCRIPT="$SKILL_DIR/scripts/maintenance/suggest-promotions.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/suggest-promotions-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
GLOBAL_ROOT="$TMP_ROOT/global-memory"
STATE_ROOT="$TMP_ROOT/state"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
GLOBAL_NAMESPACE_DIR="$GLOBAL_ROOT/namespaces/user-profile"
GLOBAL_MEMORY="$GLOBAL_NAMESPACE_DIR/.learnings"

mkdir -p "$PROJECT_MEMORY" "$GLOBAL_MEMORY" "$GLOBAL_NAMESPACE_DIR" "$STATE_ROOT"

cat > "$PROJECT_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-TEST-001] best_practice

**Logged**: 2026-03-01T00:00:00Z
**Priority**: medium
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
- Recurrence-Count: 1
- First-Seen: 2026-03-01
- Last-Seen: 2026-03-21

---

## [LRN-TEST-002] best_practice

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
- Recurrence-Count: 2
- First-Seen: 2026-03-10
- Last-Seen: 2026-03-20

---

## [LRN-TEST-003] insight

**Logged**: 2026-03-12T00:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
The user's preferred name is Zitao

### Details
This is a stable user-profile fact that should be normalized for repeated loading in profile context.

### Suggested Action
Keep profile facts easy to reload.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: user.preferred.name
- Recurrence-Count: 2
- First-Seen: 2026-03-12
- Last-Seen: 2026-03-22

---

## [LRN-TEST-004] correction

**Logged**: 2026-03-30T00:00:00Z
**Priority**: low
**Status**: pending
**Area**: docs

### Summary
Investigate temporary flaky markdown renderer issue

### Details
This is tentative for now and might disappear after the next dependency bump.

### Suggested Action
Keep it in raw history until the pattern is stable.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: flaky.renderer.issue
- Recurrence-Count: 1
- First-Seen: 2026-03-30
- Last-Seen: 2026-03-30

---
EOF

cat > "$PROJECT_MEMORY/SUMMARY_CANDIDATES.md" <<'EOF'
# Summary Candidates

- Keep docs consistency checks visible in review
EOF

cat > "$PROJECT_MEMORY/REVIEW.md" <<'EOF'
# Review

- [LRN-TEST-001] medium, pending: Keep docs consistency checks visible in review
EOF

cat > "$GLOBAL_NAMESPACE_DIR/PROFILE.md" <<'EOF'
# User Profile
EOF

cat > "$GLOBAL_MEMORY/LEARNINGS.md" <<'EOF'
# Global Learnings

---

## [GLRN-TEST-001] insight

**Logged**: 2026-03-12T00:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
The user's preferred name is Zitao

### Details
This is a stable user-profile fact that should be normalized for repeated loading in profile context.

### Suggested Action
Keep profile facts easy to reload.

### Metadata
- Source: conversation
- Related Files: none
- Tags: none
- Pattern-Key: user.preferred.name
- Recurrence-Count: 2
- First-Seen: 2026-03-12
- Last-Seen: 2026-03-22

---
EOF

output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SUGGEST_SCRIPT" --scope project --limit 10
)"

assert_contains "$output" "<promotion-suggestions>"
assert_contains "$output" "[LRN-TEST-001] promote_to_summary -> SUMMARY.md"
assert_contains "$output" "[LRN-TEST-002] consider_skill -> skill candidate under ~/.codex/skills/"
assert_contains "$output" "[LRN-TEST-004] keep_raw -> .learnings/*.md"

global_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SUGGEST_SCRIPT" --scope global --limit 5
)"

assert_contains "$global_output" "[GLRN-TEST-001] promote_to_factual_file -> PROFILE.md"

tsv_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$SUGGEST_SCRIPT" --scope project --limit all --format tsv
)"

assert_contains "$tsv_output" "# promotion-suggestions-tsv-v1"
assert_contains "$tsv_output" $'rank\tscope\tclassification\tdestination\tid\tsummary\treason\ttype\trecurrence\tstatus'
assert_contains "$tsv_output" $'project\tpromote_to_summary'
assert_contains "$tsv_output" $'project\tconsider_skill'

data_row="$(printf '%s\n' "$tsv_output" | awk -F '\t' 'NR > 2 && NF { print NF; exit }')"
if [[ "$data_row" != "10" ]]; then
    printf 'Expected TSV data rows to have 10 fields, got: %s\n' "${data_row:-missing}" >&2
    exit 1
fi

printf 'suggest-promotions assertions passed\n'
