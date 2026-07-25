#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_SCRIPT="$SKILL_DIR/scripts/maintenance/update-skill-policy.sh"

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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/update-skill-policy-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
SKILL_FILE="$TMP_ROOT/SKILL.md"

mkdir -p "$PROJECT_MEMORY"

cat > "$PROJECT_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-SP-001] correction

**Logged**: 2026-04-03T10:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
Changing nightly defaults in defaults.toml must be paired with install-nightly-maintenance.sh --apply

### Details
This is a maintainer policy for the memory-and-improvement skill itself, not a namespace-specific fact.

### Suggested Action
Treat live crontab refresh as part of the routing strategy for installed automation changes.

### Metadata
- Source: user_feedback
- Related Files: none
- Tags: automation-policy,maintainer-policy,routing-policy

---

## [LRN-SP-002] correction

**Logged**: 2026-04-03T11:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
User paper PDFs should be stored in global-memory assets, and non-user papers must be excluded from user-profile paper assets

### Details
This is a routing and asset policy correction about global memory rather than a local repo note.

### Suggested Action
Route paper PDFs into the correct global namespace assets and verify ownership before indexing them.

### Metadata
- Source: user_feedback
- Related Files: none
- Tags: memory-assets,user-profile,papers

---

## [LRN-SP-003] insight

**Logged**: 2026-04-03T12:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
Use clearer progress updates during long-running downloads

### Details
This is a UX note about commentary pacing, not a memory-governance rule.

### Suggested Action
Keep commentary more explicit during long tasks.

### Metadata
- Source: conversation
- Related Files: none
- Tags: ux,commentary

---

## [LRN-SP-004] correction

**Logged**: 2026-04-03T13:00:00Z
**Priority**: critical
**Status**: resolved
**Area**: docs

### Summary
Treat global_namespace as fallback-only and avoid using it as implicit routing policy

### Details
This is a skill policy about fallback-only behavior, not a namespace-specific fact.

### Suggested Action
Keep fallback-only routing guidance in maintainer policy and expose it clearly to automation.

### Metadata
- Source: conversation
- Related Files: none
- Tags: skill-policy,routing-policy

---

## [LRN-SP-005] correction

**Logged**: 2026-04-03T14:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
Promotion strategy changes should update the drift check or maintainer policy in the same pass

### Details
This is a promotion strategy rule for the skill itself.

### Suggested Action
Treat drift-check coverage as part of the meta-policy update workflow.

### Metadata
- Source: conversation
- Related Files: none
- Tags: promotion-policy,maintainer-policy

---

## [LRN-SP-006] correction

**Logged**: 2026-04-03T15:00:00Z
**Priority**: critical
**Status**: resolved
**Area**: docs

### Summary
Routing policy for user-profile publications should keep PUBLICATIONS.md ahead of homepage scrape

### Details
This uses routing language but is still a publications-specific rule about user-profile assets.

### Suggested Action
Keep publication records and paper PDFs in the correct namespace assets.

### Metadata
- Source: conversation
- Related Files: none
- Tags: routing-policy,user-profile,publications,papers

---
EOF

cat > "$SKILL_FILE" <<'EOF'
# Memory-and-Improvement Skill

## Adaptive Routing Strategy

This section is auto-managed by `scripts/maintenance/update-skill-policy.sh`.
It may rewrite only the strategy hints below; it must not rewrite the rest of this skill.

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    SELF_IMPROVING_SKILL_FILE="$SKILL_FILE" \
    bash "$UPDATE_SCRIPT" >/dev/null

assert_contains_file "$SKILL_FILE" "[LRN-SP-001]"
assert_contains_file "$SKILL_FILE" "[LRN-SP-004]"
assert_contains_file "$SKILL_FILE" "[LRN-SP-005]"
assert_not_contains_file "$SKILL_FILE" "[LRN-SP-002]"
assert_not_contains_file "$SKILL_FILE" "[LRN-SP-003]"
assert_not_contains_file "$SKILL_FILE" "[LRN-SP-006]"
assert_not_contains_file "$SKILL_FILE" "- none promoted yet"

UNRELATED_ROOT="$TMP_ROOT/unrelated"
UNRELATED_MEMORY="$UNRELATED_ROOT/.learnings"
mkdir -p "$UNRELATED_MEMORY"
cat > "$UNRELATED_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings

---

## [LRN-SP-007] correction

**Logged**: 2026-04-03T13:00:00Z
**Priority**: critical
**Status**: resolved
**Area**: docs

### Summary
Use global memory for customer billing namespace migrations

### Details
This should never affect the memory-and-improvement skill policy block.

### Suggested Action
Keep it local to the unrelated repository.

### Metadata
- Source: conversation
- Related Files: none
- Tags: routing-policy

---
EOF

REGISTRY_FILE="$TMP_ROOT/state/memory-and-improvement/project-memory-registry.txt"
mkdir -p "$(dirname "$REGISTRY_FILE")"
cat > "$REGISTRY_FILE" <<EOF
$UNRELATED_MEMORY
EOF

env \
    SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
    XDG_STATE_HOME="$TMP_ROOT/state" \
    SELF_IMPROVING_SKILL_FILE="$SKILL_FILE" \
    bash "$UPDATE_SCRIPT" >/dev/null

assert_not_contains_file "$SKILL_FILE" "[LRN-SP-007]"

EMPTY_ROOT="$TMP_ROOT/empty"
EMPTY_SKILL="$TMP_ROOT/EMPTY-SKILL.md"
mkdir -p "$EMPTY_ROOT"
cat > "$EMPTY_SKILL" <<'EOF'
# Empty Skill
EOF

empty_output="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$EMPTY_ROOT" \
        SELF_IMPROVING_SKILL_FILE="$EMPTY_SKILL" \
        bash "$UPDATE_SCRIPT"
)"

printf '%s' "$empty_output" | grep -Fq "Updated skill policy block" || {
    printf 'Expected empty project policy update to succeed as a no-op\n' >&2
    exit 1
}

printf 'update-skill-policy assertions passed\n'
