#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECALL_SCRIPT="$SKILL_DIR/scripts/recall/recall-memory.sh"
INIT_SCRIPT="$SKILL_DIR/scripts/bootstrap/init-memory.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_ROOT="$TMP_DIR/project"
GLOBAL_ROOT="$TMP_DIR/global-memory"
STATE_ROOT="$TMP_DIR/state"
mkdir -p "$PROJECT_ROOT"

export SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT"
export SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT"
export SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces"
export SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle"
export XDG_STATE_HOME="$STATE_ROOT"

bash "$INIT_SCRIPT" --scope both --project-root "$PROJECT_ROOT" >/dev/null
bash "$INIT_SCRIPT" --scope global --global-namespace user-profile >/dev/null

cat <<'EOF' > "$PROJECT_ROOT/.learnings/SUMMARY.md"
# Project Summary

Load this file before opening detailed project memory when you want the shortest useful summary for this repository.

Use this file for repo facts, constraints, and distilled lessons.
Do not store repo-local agent instructions, prompt policy, or routing policy here; keep those in `AGENTS.md` or explicit repo config.

Current high-priority principles:
- Run audit-focused subagents after roadmap-driven memory skill changes.
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/LEARNINGS.md"
# Project Learnings

## [LRN-20260401-001] best_practice

**Logged**: 2026-04-01T12:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Use subagent audits after roadmap phases

### Details
Audit plan alignment before starting the next phase.

### Suggested Action
Spawn a dedicated audit subagent.

### Metadata
- Source: conversation
- Related Files: TODO.md
- Tags: audit
- Pattern-Key: memory_skill.subagent_audit_convention
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-002] malformed

**Logged**: 2026-04-01T12:03:00Z
**Priority**: low
**Status**: pending
**Area**: docs

### Details
This malformed project entry intentionally omits a summary so a later valid recall hit must still survive.

### Metadata
- Source: conversation
- Related Files: none
- Tags: malformed
- Pattern-Key: memory_skill.recall_malformed_entry
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-003] best_practice

**Logged**: 2026-04-01T12:04:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
EOF resilience holds after malformed recall entries

### Details
This later valid entry should still be reachable through recall-driven search.

### Suggested Action
Keep recall resilient to malformed history blocks.

### Metadata
- Source: conversation
- Related Files: recall-memory.sh
- Tags: malformed
- Pattern-Key: memory_skill.recall_eof_resilience
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/REVIEW.md"
# Project Memory Review

**Memory Dir**: project/.learnings

## Pending Items

- [LRN-20260401-099] medium: Review before opening raw history.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/SUMMARY.md"
# User Profile Summary

Load this file before opening `.learnings/` when you want the shortest useful summary for this namespace.

Current high-priority facts:
- Preferred name: Example.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/ACADEMIC_PROFILE.md"
# Academic Profile

This malformed factual file intentionally does not contain the target wording.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/PROFILE.md"
# Profile

- Factual fallback remains visible through recall after malformed higher-layer files.
EOF

mkdir -p "$GLOBAL_ROOT/namespaces/user-profile/.learnings"
cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/.learnings/LEARNINGS.md"
# Global Learnings

## [LRN-UG-20260401-001] durable_fact

**Logged**: 2026-04-01T12:31:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Factual fallback remains visible through recall after malformed higher-layer files.

### Details
This raw global learning duplicates the factual file wording so recall can verify that factual files outrank raw learnings by default.

### Suggested Action
Open the factual file before deeper raw history when both match.

### Metadata
- Source: conversation
- Related Files: PROFILE.md
- Tags: factual
- Pattern-Key: memory_skill.recall_global_factual_first
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---
EOF

mkdir -p "$GLOBAL_ROOT/namespaces/user-profile/assets"
cat <<'EOF' > "$GLOBAL_ROOT/namespaces/user-profile/assets/INDEX.md"
# Asset Index

## [AST-20260401-000] broken_block

- Logged: 2026-04-01T12:29:00Z
- Summary: Broken asset block without title should not suppress later valid assets

## [AST-20260401-001] report_pdf

- Logged: 2026-04-01T12:30:00Z
- Title: recall-fallback-report
- Type: report_pdf
- Scope: global
- Namespace: user-profile
- Canonical-Path: /tmp/recall-fallback-report.pdf
- Source: import
- Summary: Asset fallback remains visible through recall after malformed higher-layer files
- Tags: recall,fallback
- Related-Memory-IDs: none
- Status: active

---
EOF

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

project_output="$(bash "$RECALL_SCRIPT" --scope auto --project-root "$PROJECT_ROOT")"
assert_contains "$project_output" "<memory-recall>"
assert_contains "$project_output" "Requested-Scope: auto"
assert_contains "$project_output" "Resolved-Scope: project"
assert_contains "$project_output" "Summary-First: true"
assert_contains "$project_output" "Review:"
assert_contains "$project_output" "<memory-review>"
assert_contains "$project_output" "Run audit-focused subagents after roadmap-driven memory skill changes."
assert_contains "$project_output" "Project review highlights:"
assert_not_contains "$project_output" "Use subagent audits after roadmap phases"
assert_not_contains "$project_output" "Project recent visible items:"

global_output="$(bash "$RECALL_SCRIPT" --scope auto --project-root "$PROJECT_ROOT" --query "preferred name")"
assert_contains "$global_output" "Resolved-Scope: global"
assert_contains "$global_output" "Resolved-Namespace: user-profile"
assert_contains "$global_output" "Query: preferred name"
assert_contains "$global_output" "<memory-review>"
assert_contains "$global_output" "<memory-search>"
assert_contains "$global_output" "Preferred name: Example."

deeper_output="$(bash "$RECALL_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --deeper true)"
assert_contains "$deeper_output" "Resolved-Scope: project"
assert_contains "$deeper_output" "Deeper: true"
assert_contains "$deeper_output" "<memory-review>"
assert_contains "$deeper_output" "<memory-search>"
assert_contains "$deeper_output" "[LRN-20260401-001]"

both_output="$(bash "$RECALL_SCRIPT" --scope auto --project-root "$PROJECT_ROOT" --query "repo preferred name")"
assert_contains "$both_output" "Resolved-Scope: both"
assert_contains "$both_output" "Resolved-Namespace: user-profile"

case "$global_output" in
    *"<memory-review>"*"<memory-search>"*) ;;
    *)
        printf 'Expected recall output to show review before search\n' >&2
        exit 1
        ;;
esac

export SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile"
misroute_output="$(bash "$RECALL_SCRIPT" --scope auto --project-root "$PROJECT_ROOT" --query "repo-local implementation detail")"
assert_contains "$misroute_output" "Resolved-Scope: project"
assert_not_contains "$misroute_output" "Resolved-Namespace: user-profile"

malformed_project_output="$(bash "$RECALL_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "EOF resilience")"
assert_contains "$malformed_project_output" "Resolved-Scope: project"
assert_contains "$malformed_project_output" "Search:"
assert_contains "$malformed_project_output" "[LRN-20260401-003]"
assert_not_contains "$malformed_project_output" "[LRN-20260401-002]"

factual_fallback_output="$(bash "$RECALL_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --namespace user-profile --query "factual fallback remains visible")"
assert_contains "$factual_fallback_output" "Resolved-Scope: global"
assert_contains "$factual_fallback_output" "Resolved-Namespace: user-profile"
assert_contains "$factual_fallback_output" "Search:"
assert_contains "$factual_fallback_output" "[DOC-PROFILE]"
assert_contains "$factual_fallback_output" "Factual fallback remains visible through recall after malformed higher-layer files."
assert_not_contains "$factual_fallback_output" "[LRN-UG-20260401-001]"

asset_fallback_output="$(bash "$RECALL_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --namespace user-profile --query "asset fallback remains visible")"
assert_contains "$asset_fallback_output" "Resolved-Scope: global"
assert_contains "$asset_fallback_output" "Search:"
assert_contains "$asset_fallback_output" "[AST-20260401-001]"
assert_contains "$asset_fallback_output" "Asset fallback remains visible through recall after malformed higher-layer files"

printf 'recall-memory assertions passed\n'
