#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NIGHTLY_SCRIPT="$SKILL_DIR/scripts/maintenance/nightly-maintenance.sh"

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

assert_not_exists() {
    local path="$1"

    if [[ -e "$path" ]]; then
        printf 'Expected path not to exist: %s\n' "$path" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nightly-maintenance-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_project_fixture() {
    local root="$1"
    local summary_text="${2:-Nightly maintenance should honor project memory routing during config-driven writeback}"
    local pattern_key="${3:-nightly.maintenance.writeback}"
    local memory_dir="$root/.learnings"

    mkdir -p "$memory_dir"
    cat > "$memory_dir/LEARNINGS.md" <<EOF
# Project Learnings

---

## [LRN-NM-001] insight

**Logged**: 2026-03-01T00:00:00Z
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
$summary_text

### Details
This recurring repo convention should surface in summary output.

### Suggested Action
Keep the writeback path wired to shared config defaults.

### Metadata
- Source: automation
- Related Files: none
- Tags: none
- Pattern-Key: $pattern_key
- Recurrence-Count: 2
- First-Seen: 2026-03-01
- Last-Seen: 2026-03-21

---
EOF
}

HOME_TRUE="$TMP_ROOT/home-true"
STATE_TRUE="$TMP_ROOT/state-true"
PROJECT_TRUE="$TMP_ROOT/project-true"
SKILL_TRUE="$TMP_ROOT/skill-true.md"

mkdir -p "$HOME_TRUE/.codex/skills/memory-and-improvement" "$STATE_TRUE" "$PROJECT_TRUE"
make_project_fixture "$PROJECT_TRUE"
cat > "$SKILL_TRUE" <<'EOF'
# Memory-and-Improvement Skill

## Adaptive Routing Strategy

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF

cat > "$HOME_TRUE/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
nightly_writeback = true
skill_policy_writeback = true
organize_min_recurrence = 2

[maintenance]
scope = "project"
EOF

true_output="$(
    env \
        HOME="$HOME_TRUE" \
        XDG_STATE_HOME="$STATE_TRUE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_TRUE" \
        SELF_IMPROVING_SKILL_FILE="$SKILL_TRUE" \
        bash "$NIGHTLY_SCRIPT"
)"

assert_contains "$true_output" "Nightly maintenance complete for scope=project"
assert_contains_file "$PROJECT_TRUE/.learnings/SUMMARY.md" "[LRN-NM-001]"
assert_contains_file "$PROJECT_TRUE/.learnings/REVIEW.md" "[LRN-NM-001]"
assert_contains_file "$SKILL_TRUE" "- none promoted yet"

HOME_FALSE="$TMP_ROOT/home-false"
STATE_FALSE="$TMP_ROOT/state-false"
PROJECT_FALSE="$TMP_ROOT/project-false"

mkdir -p "$HOME_FALSE/.codex/skills/memory-and-improvement" "$STATE_FALSE" "$PROJECT_FALSE"
make_project_fixture "$PROJECT_FALSE"

cat > "$HOME_FALSE/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
nightly_writeback = true
organize_min_recurrence = 2
EOF

false_output="$(
    env \
        HOME="$HOME_FALSE" \
        XDG_STATE_HOME="$STATE_FALSE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_FALSE" \
        bash "$NIGHTLY_SCRIPT" --scope project --writeback false
)"

assert_contains "$false_output" "Nightly maintenance complete for scope=project"
assert_not_contains_file "$PROJECT_FALSE/.learnings/SUMMARY.md" "[LRN-NM-001]"
assert_contains_file "$PROJECT_FALSE/.learnings/REVIEW.md" "[LRN-NM-001]"

BOTH_HOME="$TMP_ROOT/home-both"
BOTH_STATE="$TMP_ROOT/state-both"
PROJECT_BOTH_A="$TMP_ROOT/project-both-a"
PROJECT_BOTH_B="$TMP_ROOT/project-both-b"
GLOBAL_ROOT="$TMP_ROOT/global-memory"
GLOBAL_NS_ONE="$GLOBAL_ROOT/namespaces/research-principle"
GLOBAL_NS_TWO="$GLOBAL_ROOT/namespaces/user-profile"
GLOBAL_NS_ONE_MEMORY="$GLOBAL_NS_ONE/.learnings"
GLOBAL_NS_TWO_MEMORY="$GLOBAL_NS_TWO/.learnings"
REGISTRY_FILE="$BOTH_STATE/memory-and-improvement/project-memory-registry.txt"

mkdir -p "$BOTH_HOME/.codex/skills/memory-and-improvement" "$BOTH_STATE" "$PROJECT_BOTH_A" "$PROJECT_BOTH_B" "$GLOBAL_NS_ONE" "$GLOBAL_NS_TWO"
make_project_fixture "$PROJECT_BOTH_A" "Nightly both-scope should update the primary registered project" "nightly.both.project.a"
make_project_fixture "$PROJECT_BOTH_B" "Nightly both-scope should update the secondary registered project" "nightly.both.project.b"
make_project_fixture "$GLOBAL_NS_ONE" "Nightly both-scope should update the first global namespace" "nightly.both.global.one"
make_project_fixture "$GLOBAL_NS_TWO" "Nightly both-scope should update the second global namespace" "nightly.both.global.two"

mkdir -p "$(dirname "$REGISTRY_FILE")"
cat > "$REGISTRY_FILE" <<EOF
$PROJECT_BOTH_A/.learnings
$PROJECT_BOTH_B/.learnings
EOF

both_output="$(
    env \
        HOME="$BOTH_HOME" \
        XDG_STATE_HOME="$BOTH_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_BOTH_A" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        bash "$NIGHTLY_SCRIPT" --scope both --writeback true --min-recurrence 2
)"

assert_contains "$both_output" "Nightly maintenance complete for scope=both"
assert_contains_file "$PROJECT_BOTH_A/.learnings/SUMMARY.md" "Nightly both-scope should update the primary registered project"
assert_contains_file "$PROJECT_BOTH_B/.learnings/SUMMARY.md" "Nightly both-scope should update the secondary registered project"
assert_contains_file "$GLOBAL_NS_ONE/SUMMARY.md" "Nightly both-scope should update the first global namespace"
assert_contains_file "$GLOBAL_NS_TWO/SUMMARY.md" "Nightly both-scope should update the second global namespace"
assert_contains_file "$PROJECT_BOTH_A/.learnings/LEARNINGS.md" "**Status**: promoted_to_summary"
assert_contains_file "$PROJECT_BOTH_B/.learnings/LEARNINGS.md" "**Status**: promoted_to_summary"
assert_contains_file "$GLOBAL_NS_ONE_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"
assert_contains_file "$GLOBAL_NS_TWO_MEMORY/LEARNINGS.md" "**Status**: promoted_to_summary"

repeat_output="$(
    env \
        HOME="$BOTH_HOME" \
        XDG_STATE_HOME="$BOTH_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_BOTH_A" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        bash "$NIGHTLY_SCRIPT" --scope both --writeback true --min-recurrence 2
)"

assert_contains "$repeat_output" "Nightly maintenance complete for scope=both"
assert_contains_file "$PROJECT_BOTH_A/.learnings/SUMMARY.md" "Nightly both-scope should update the primary registered project"
assert_contains_file "$PROJECT_BOTH_B/.learnings/SUMMARY.md" "Nightly both-scope should update the secondary registered project"
assert_contains_file "$GLOBAL_NS_ONE/SUMMARY.md" "Nightly both-scope should update the first global namespace"
assert_contains_file "$GLOBAL_NS_TWO/SUMMARY.md" "Nightly both-scope should update the second global namespace"

STALE_HOME="$TMP_ROOT/home-stale"
STALE_STATE="$TMP_ROOT/state-stale"
STALE_PROJECT="$TMP_ROOT/project-stale"
STALE_MISSING="$TMP_ROOT/project-missing"
STALE_REGISTRY="$STALE_STATE/memory-and-improvement/project-memory-registry.txt"

mkdir -p "$STALE_HOME/.codex/skills/memory-and-improvement" "$STALE_STATE" "$STALE_PROJECT"
make_project_fixture "$STALE_PROJECT" "Nightly project scope should keep valid project entries while pruning stale ones" "nightly.project.stale.valid"
mkdir -p "$(dirname "$STALE_REGISTRY")"
cat > "$STALE_REGISTRY" <<EOF
$STALE_PROJECT/.learnings
$STALE_MISSING/.learnings
EOF

stale_output="$(
    env \
        HOME="$STALE_HOME" \
        XDG_STATE_HOME="$STALE_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$STALE_PROJECT" \
        bash "$NIGHTLY_SCRIPT" --scope project --writeback true --min-recurrence 2
)"

assert_contains "$stale_output" "Nightly maintenance pruned missing project memory registry entry: $STALE_MISSING/.learnings"
assert_contains "$stale_output" "Nightly maintenance complete for scope=project"
assert_contains_file "$STALE_PROJECT/.learnings/SUMMARY.md" "Nightly project scope should keep valid project entries while pruning stale ones"
assert_contains_file "$STALE_REGISTRY" "$STALE_PROJECT/.learnings"
assert_not_contains_file "$STALE_REGISTRY" "$STALE_MISSING/.learnings"

ASYM_HOME="$TMP_ROOT/home-asym"
ASYM_STATE="$TMP_ROOT/state-asym"
ASYM_PROJECT="$TMP_ROOT/project-asym"
ASYM_GLOBAL_ROOT="$TMP_ROOT/global-memory-asym"
ASYM_GLOBAL_NS="$ASYM_GLOBAL_ROOT/namespaces/research-history"

mkdir -p "$ASYM_HOME/.codex/skills/memory-and-improvement" "$ASYM_STATE" "$ASYM_PROJECT" "$ASYM_GLOBAL_NS"
make_project_fixture "$ASYM_GLOBAL_NS" "Nightly both-scope should still process global memory when project scope is empty" "nightly.both.global.only"

asym_output="$(
    env \
        HOME="$ASYM_HOME" \
        XDG_STATE_HOME="$ASYM_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$ASYM_PROJECT" \
        SELF_IMPROVING_GLOBAL_ROOT="$ASYM_GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$ASYM_GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-history" \
        bash "$NIGHTLY_SCRIPT" --scope both --writeback true --min-recurrence 2
)"

assert_contains "$asym_output" "Nightly maintenance skipped project scope: no existing project memory directories found"
assert_contains "$asym_output" "Nightly maintenance complete for scope=both"
assert_contains_file "$ASYM_GLOBAL_NS/SUMMARY.md" "Nightly both-scope should still process global memory when project scope is empty"
assert_contains_file "$ASYM_GLOBAL_NS/.learnings/LEARNINGS.md" "**Status**: promoted_to_summary"

ASYM2_HOME="$TMP_ROOT/home-asym2"
ASYM2_STATE="$TMP_ROOT/state-asym2"
ASYM2_PROJECT="$TMP_ROOT/project-asym2"
ASYM2_GLOBAL_ROOT="$TMP_ROOT/global-memory-asym2"

mkdir -p "$ASYM2_HOME/.codex/skills/memory-and-improvement" "$ASYM2_STATE" "$ASYM2_PROJECT" "$ASYM2_GLOBAL_ROOT/namespaces"
make_project_fixture "$ASYM2_PROJECT" "Nightly both-scope should still process project memory when global scope is empty" "nightly.both.project.only"

asym2_output="$(
    env \
        HOME="$ASYM2_HOME" \
        XDG_STATE_HOME="$ASYM2_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$ASYM2_PROJECT" \
        SELF_IMPROVING_GLOBAL_ROOT="$ASYM2_GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$ASYM2_GLOBAL_ROOT/namespaces" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-history" \
        bash "$NIGHTLY_SCRIPT" --scope both --writeback true --min-recurrence 2
)"

assert_contains "$asym2_output" "Nightly maintenance skipped global scope: no existing global memory directories found"
assert_contains "$asym2_output" "Nightly maintenance complete for scope=both"
assert_contains_file "$ASYM2_PROJECT/.learnings/SUMMARY.md" "Nightly both-scope should still process project memory when global scope is empty"
assert_contains_file "$ASYM2_PROJECT/.learnings/LEARNINGS.md" "**Status**: promoted_to_summary"

SPW_HOME="$TMP_ROOT/home-spw"
SPW_STATE="$TMP_ROOT/state-spw"
SPW_PROJECT="$TMP_ROOT/project-spw"
SPW_SKILL="$TMP_ROOT/skill-spw.md"

mkdir -p "$SPW_HOME/.codex/skills/memory-and-improvement" "$SPW_STATE" "$SPW_PROJECT"
cat > "$SPW_SKILL" <<'EOF'
# Memory-and-Improvement Skill

## Adaptive Routing Strategy

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF

cat > "$SPW_HOME/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
skill_policy_writeback = true

[maintenance]
scope = "project"
EOF

spw_output="$(
    env \
        HOME="$SPW_HOME" \
        XDG_STATE_HOME="$SPW_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$SPW_PROJECT" \
        SELF_IMPROVING_SKILL_FILE="$SPW_SKILL" \
        bash "$NIGHTLY_SCRIPT"
)"

assert_contains "$spw_output" "Nightly maintenance skipped project scope: no existing project memory directories found"
assert_contains "$spw_output" "Nightly maintenance skipped skill policy writeback: no existing project memory directory found"
assert_contains "$spw_output" "Nightly maintenance complete for scope=project"
assert_contains_file "$SPW_SKILL" "- none promoted yet"

GIT_HOME="$TMP_ROOT/home-git"
GIT_STATE="$TMP_ROOT/state-git"
GIT_PROJECT="$TMP_ROOT/project-git"

mkdir -p "$GIT_HOME/.codex/skills/memory-and-improvement" "$GIT_STATE" "$GIT_PROJECT"
cat > "$GIT_HOME/.gitconfig" <<'EOF'
[init]
    defaultBranch = main
EOF
make_project_fixture "$GIT_PROJECT" "Nightly maintenance should create a real git commit when git_commit is enabled" "nightly.git.commit"

git_output="$(
    env \
        HOME="$GIT_HOME" \
        XDG_STATE_HOME="$GIT_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$GIT_PROJECT" \
        bash "$NIGHTLY_SCRIPT" --scope project --writeback true --git-commit true --min-recurrence 2
)"

assert_contains "$git_output" "Nightly maintenance complete for scope=project"
assert_contains "$git_output" "Committed memory changes in"
if [[ ! -d "$GIT_PROJECT/.learnings/.git" ]]; then
    printf 'Expected nightly git commit path to initialize git in %s\n' "$GIT_PROJECT/.learnings" >&2
    exit 1
fi

git_commit_count="$(git -C "$GIT_PROJECT/.learnings" rev-list --count HEAD)"
if [[ "$git_commit_count" -lt 1 ]]; then
    printf 'Expected nightly maintenance to create at least one git commit, found %s\n' "$git_commit_count" >&2
    exit 1
fi

git_last_subject="$(git -C "$GIT_PROJECT/.learnings" log -1 --pretty=%s)"
if [[ "$git_last_subject" != "memory: nightly maintenance $(date +%F)" ]]; then
    printf 'Expected nightly commit subject to match nightly format, got: %s\n' "$git_last_subject" >&2
    exit 1
fi

git_repeat_output="$(
    env \
        HOME="$GIT_HOME" \
        XDG_STATE_HOME="$GIT_STATE" \
        SELF_IMPROVING_PROJECT_ROOT="$GIT_PROJECT" \
        bash "$NIGHTLY_SCRIPT" --scope project --writeback true --git-commit true --min-recurrence 2
)"

assert_contains "$git_repeat_output" "No changes to commit in"
git_repeat_commit_count="$(git -C "$GIT_PROJECT/.learnings" rev-list --count HEAD)"
if [[ "$git_repeat_commit_count" != "$git_commit_count" ]]; then
    printf 'Expected no-op nightly rerun not to create an extra commit\n' >&2
    exit 1
fi

printf 'nightly-maintenance assertions passed\n'
