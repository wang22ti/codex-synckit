#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEARCH_SCRIPT="$SKILL_DIR/scripts/recall/search-memory.sh"
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

cat <<'EOF' > "$PROJECT_ROOT/.learnings/SUMMARY.md"
# Project Summary

Current high-priority principles:
- Prefer claim-evidence summaries before raw audit history.
- Layered search ordering keyword lives in summary first.
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/REVIEW.md"
# Project Memory Review

## Pending Items

- [LRN-20260401-099] medium: Layered search ordering keyword also appears in review.
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

## [LRN-20260401-002] docs_pattern

**Logged**: 2026-04-01T12:05:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Prefer claim-evidence summaries before raw audit history

### Details
This duplicate phrase is here so the search test can verify that higher-layer summary hits stop the default search before raw entries.

### Suggested Action
Search should not surface this raw entry when summary is enough.

### Metadata
- Source: conversation
- Related Files: SKILL.md
- Tags: summary
- Pattern-Key: memory_skill.progressive_loading
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-003] docs_pattern

**Logged**: 2026-04-01T12:06:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Layered search ordering keyword also appears in raw memory

### Details
This entry exists so exhaustive search can verify summary, review, and raw ordering together.

### Suggested Action
Keep layer ordering stable.

### Metadata
- Source: conversation
- Related Files: review-memory.sh
- Tags: search
- Pattern-Key: memory_skill.layer_ordering
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-004] malformed

**Logged**: 2026-04-01T12:07:00Z
**Priority**: low
**Status**: pending
**Area**: docs

### Details
This malformed block intentionally omits a summary so later valid hits must still survive.

### Metadata
- Source: conversation
- Related Files: none
- Tags: malformed
- Pattern-Key: memory_skill.malformed.middle
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-005] docs_pattern

**Logged**: 2026-04-01T12:08:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
EOF resilience survives malformed trailing entries

### Details
This valid entry should still be searchable even when a later entry is truncated.

### Suggested Action
Keep parser behavior resilient.

### Metadata
- Source: conversation
- Related Files: search-memory.sh
- Tags: malformed
- Pattern-Key: memory_skill.eof_resilience
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---

## [LRN-20260401-006] truncated

**Logged**: 2026-04-01T12:09:00Z
**Priority**: low
**Status**: pending
**Area**: docs

### Details
This trailing block is intentionally truncated without a summary or closing separator.
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/ERRORS.md"
# Project Errors

## [ERR-20260401-001] shell

**Logged**: 2026-04-01T12:10:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Sandbox blocked registry writes

### Error
touch failed

### Context
registry path was read-only

### Suggested Fix
run with escalated permissions

### Metadata
- Reproducible: yes
- Related Files: memory-paths.sh

---
EOF

cat <<'EOF' > "$PROJECT_ROOT/.learnings/FEATURE_REQUESTS.md"
# Project Feature Requests

## [FEAT-20260401-001] search_memory

**Logged**: 2026-04-01T12:20:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Requested Capability
Search memory by pattern key from the command line

### User Context
Useful when revisiting memory conventions.

### Complexity Estimate
medium

### Suggested Implementation
Add a dedicated search script with filters.

### Metadata
- Frequency: first_time
- Related Features: review-memory

---
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/SUMMARY.md"
# Research Principle Summary

Load this file before opening `.learnings/` when you want the shortest useful summary for this namespace.

Current high-priority principles:
- Prefer concise rebuttal drafts with explicit claim-evidence structure.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/RECORDS.md"
# Research Principle Records

Representative durable workflow facts:
- Claim-evidence structure is reused across papers.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/ACADEMIC_PROFILE.md"
# Academic Profile

This malformed factual file intentionally does not match the target query.
EOF

cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/PROFILE.md"
# Profile

- Factual fallback remains searchable after malformed higher-layer files.
EOF

mkdir -p "$GLOBAL_ROOT/namespaces/research-principle/.learnings"
cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/.learnings/LEARNINGS.md"
# Global Learnings

## [LRN-GLOBAL-20260401-001] durable_fact

**Logged**: 2026-04-01T12:31:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Factual fallback remains searchable after malformed higher-layer files.

### Details
This raw learning duplicates the factual file wording so search ordering can verify that structured factual files win before raw learnings.

### Suggested Action
Prefer the structured factual file before opening raw learnings.

### Metadata
- Source: conversation
- Related Files: PROFILE.md
- Tags: factual
- Pattern-Key: memory_skill.global_factual_first
- Recurrence-Count: 1
- First-Seen: 2026-04-01
- Last-Seen: 2026-04-01

---
EOF

mkdir -p "$GLOBAL_ROOT/namespaces/research-principle/assets"
cat <<'EOF' > "$GLOBAL_ROOT/namespaces/research-principle/assets/INDEX.md"
# Asset Index

## [AST-20260401-000] broken_block

- Logged: 2026-04-01T12:29:00Z
- Summary: Broken asset block without title should not suppress later valid assets

## [AST-20260401-001] paper_pdf

- Logged: 2026-04-01T12:30:00Z
- Title: rebuttal-example
- Type: paper_pdf
- Scope: global
- Namespace: research-principle
- Canonical-Path: /tmp/rebuttal.pdf
- Source: import
- Summary: Example rebuttal PDF
- Tags: rebuttal,paper
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

project_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query subagent)"
assert_contains "$project_output" "<memory-search>"
assert_contains "$project_output" "[LRN-20260401-001]"
assert_contains "$project_output" "Use subagent audits after roadmap phases"

global_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --query claim-evidence)"
assert_contains "$global_output" "[DOC-SUMMARY]"
assert_contains "$global_output" "explicit claim-evidence structure"

summary_stop_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query claim-evidence)"
assert_contains "$summary_stop_output" "[DOC-SUMMARY]"
assert_contains "$summary_stop_output" "Prefer claim-evidence summaries before raw audit history."
assert_not_contains "$summary_stop_output" "[LRN-20260401-002]"

ordering_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "ordering keyword")"
assert_contains "$ordering_output" "[DOC-SUMMARY]"
assert_not_contains "$ordering_output" "[DOC-REVIEW]"
assert_not_contains "$ordering_output" "[LRN-20260401-003]"

exhaustive_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query claim-evidence --exhaustive true)"
assert_contains "$exhaustive_output" "Exhaustive: true"
assert_contains "$exhaustive_output" "[DOC-SUMMARY]"
assert_contains "$exhaustive_output" "[LRN-20260401-002]"

ordering_exhaustive_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "ordering keyword" --exhaustive true)"
assert_contains "$ordering_exhaustive_output" "Exhaustive: true"
assert_contains "$ordering_exhaustive_output" "[DOC-SUMMARY]"
assert_contains "$ordering_exhaustive_output" "[DOC-REVIEW]"
assert_contains "$ordering_exhaustive_output" "[LRN-20260401-003]"
case "$ordering_exhaustive_output" in
    *"[DOC-SUMMARY]"*"[DOC-REVIEW]"*"[LRN-20260401-003]"*) ;;
    *)
        printf 'Expected exhaustive search ordering to stay summary -> review -> raw\n' >&2
        exit 1
        ;;
esac

malformed_survival_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --query "EOF resilience")"
assert_contains "$malformed_survival_output" "[LRN-20260401-005]"
assert_not_contains "$malformed_survival_output" "[LRN-20260401-006]"

filtered_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type learning --pattern-key memory_skill.subagent_audit_convention)"
assert_contains "$filtered_output" "Type: learning"
assert_contains "$filtered_output" "Pattern-Key: memory_skill.subagent_audit_convention"
assert_contains "$filtered_output" "[LRN-20260401-001]"

error_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type error --status pending --query registry)"
assert_contains "$error_output" "Type: error"
assert_contains "$error_output" "Status: pending"
assert_contains "$error_output" "[ERR-20260401-001]"

feature_output="$(bash "$SEARCH_SCRIPT" --scope project --project-root "$PROJECT_ROOT" --type feature_request --query "pattern key")"
assert_contains "$feature_output" "Type: feature_request"
assert_contains "$feature_output" "[FEAT-20260401-001]"
assert_contains "$feature_output" "Search memory by pattern key from the command line"

status_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --status pending --query claim-evidence)"
assert_contains "$status_output" "Status: pending"
assert_contains "$status_output" "Hits: none"

asset_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --type asset --query rebuttal)"
assert_contains "$asset_output" "Type: asset"
assert_contains "$asset_output" "[AST-20260401-001]"
assert_contains "$asset_output" "Example rebuttal PDF"

asset_status_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --type asset --status active --query rebuttal)"
assert_contains "$asset_status_output" "Status: active"
assert_contains "$asset_status_output" "[AST-20260401-001]"

asset_malformed_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --type asset --query rebuttal)"
assert_contains "$asset_malformed_output" "[AST-20260401-001]"

factual_fallback_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --query "factual fallback remains searchable")"
assert_contains "$factual_fallback_output" "[DOC-PROFILE]"
assert_contains "$factual_fallback_output" "Factual fallback remains searchable after malformed higher-layer files."
assert_not_contains "$factual_fallback_output" "[LRN-GLOBAL-20260401-001]"

factual_fallback_exhaustive_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --query "factual fallback remains searchable" --exhaustive true)"
assert_contains "$factual_fallback_exhaustive_output" "[DOC-PROFILE]"
assert_contains "$factual_fallback_exhaustive_output" "[LRN-GLOBAL-20260401-001]"

no_hit_output="$(bash "$SEARCH_SCRIPT" --scope both --project-root "$PROJECT_ROOT" --query "nothing-will-match-this-query")"
assert_contains "$no_hit_output" "Hits: none"

printf 'search-memory assertions passed\n'
