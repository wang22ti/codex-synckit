#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTERVAL_SCRIPT="$SKILL_DIR/scripts/maintenance/interval-maintenance.sh"

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

make_project_fixture() {
    local root="$1"
    local summary_text="${2:-Interval maintenance should honor project memory routing during config-driven writeback}"
    local pattern_key="${3:-interval.maintenance.writeback}"
    local memory_dir="$root/.learnings"

    mkdir -p "$memory_dir"
    cat > "$memory_dir/LEARNINGS.md" <<EOF
# Project Learnings

---

## [LRN-IM-001] insight

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

make_skill_policy_fixture() {
    local root="$1"
    local id="${2:-LRN-SP-INT-001}"
    local summary_text="${3:-Changing nightly defaults in defaults.toml must be paired with install-nightly-maintenance.sh --apply}"
    local memory_dir="$root/.learnings"

    mkdir -p "$memory_dir"
    cat > "$memory_dir/LEARNINGS.md" <<EOF
# Project Learnings

---

## [$id] correction

**Logged**: 2026-04-03T10:00:00Z
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
$summary_text

### Details
This is a maintainer policy for the memory-and-improvement skill itself, not a namespace-specific fact.

### Suggested Action
Treat live crontab refresh as part of the routing strategy for installed automation changes.

### Metadata
- Source: user_feedback
- Related Files: none
- Tags: automation-policy,maintainer-policy,routing-policy

---
EOF
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/interval-maintenance-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT_ROOT="$TMP_ROOT/project"
PROJECT_MEMORY="$PROJECT_ROOT/.learnings"
STATE_ROOT="$TMP_ROOT/state"
STATE_FILE="$STATE_ROOT/interval-maintenance.last-run"
SKILL_FILE="$TMP_ROOT/skill.md"

mkdir -p "$PROJECT_ROOT" "$PROJECT_MEMORY" "$STATE_ROOT"
make_skill_policy_fixture "$PROJECT_ROOT" "LRN-IM-001" "Changing nightly defaults in defaults.toml must be paired with install-nightly-maintenance.sh --apply"

cat > "$SKILL_FILE" <<'EOF'
# Memory-and-Improvement Skill

## Adaptive Routing Strategy

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF

first_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        SELF_IMPROVING_SKILL_FILE="$SKILL_FILE" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --skill-policy-writeback true \
            --state-file "$STATE_FILE"
)"

assert_contains "$first_run" "Nightly maintenance complete for scope=project"
assert_contains "$first_run" "Interval maintenance marked successful completion"
grep -Fq "[LRN-IM-001]" "$SKILL_FILE" || {
    printf 'Expected interval maintenance to forward skill policy writeback\n' >&2
    exit 1
}
[[ -f "$STATE_FILE" ]] || {
    printf 'Expected state file to exist: %s\n' "$STATE_FILE" >&2
    exit 1
}

first_state="$(cat "$STATE_FILE")"
[[ "$first_state" =~ ^[0-9]+$ ]] || {
    printf 'Expected numeric state file, got: %s\n' "$first_state" >&2
    exit 1
}

second_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$STATE_FILE"
)"

assert_contains "$second_run" "Interval maintenance skipped:"

second_state="$(cat "$STATE_FILE")"
[[ "$second_state" == "$first_state" ]] || {
    printf 'Expected state file to remain unchanged between skipped runs\n' >&2
    exit 1
}

junk_state_file="$STATE_ROOT/interval-maintenance-junk.last-run"
printf 'not-a-timestamp\n' > "$junk_state_file"

junk_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$junk_state_file"
)"

assert_contains "$junk_run" "Nightly maintenance complete for scope=project"
assert_contains "$junk_run" "Interval maintenance marked successful completion"

junk_state="$(cat "$junk_state_file")"
[[ "$junk_state" =~ ^[0-9]+$ ]] || {
    printf 'Expected junk state file to be rewritten with a numeric epoch, got: %s\n' "$junk_state" >&2
    exit 1
}

stale_state_file="$STATE_ROOT/interval-maintenance-stale.last-run"
printf '1\n' > "$stale_state_file"

stale_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$stale_state_file"
)"

assert_contains "$stale_run" "Nightly maintenance complete for scope=project"
assert_contains "$stale_run" "Interval maintenance marked successful completion"

stale_state="$(cat "$stale_state_file")"
[[ "$stale_state" =~ ^[0-9]+$ ]] || {
    printf 'Expected stale state file to contain a numeric epoch, got: %s\n' "$stale_state" >&2
    exit 1
}

if [[ "$stale_state" -le 1 ]]; then
    printf 'Expected stale state file to be refreshed to a newer epoch, got: %s\n' "$stale_state" >&2
    exit 1
fi

no_change_state_file="$STATE_ROOT/interval-maintenance-no-change.last-run"
no_change_epoch="$(( $(date +%s) - 3600 ))"
printf '%s\n' "$no_change_epoch" > "$no_change_state_file"
find "$PROJECT_MEMORY" -type f -exec touch -d "@$((no_change_epoch - 60))" {} +
touch -d "@$((no_change_epoch - 60))" "$PROJECT_MEMORY" "$SKILL_FILE"

no_change_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$no_change_state_file"
)"

assert_contains "$no_change_run" "Interval maintenance skipped: no relevant memory changes since epoch=$no_change_epoch"

no_change_state="$(cat "$no_change_state_file")"
[[ "$no_change_state" == "$no_change_epoch" ]] || {
    printf 'Expected no-change state file to remain unchanged after skip\n' >&2
    exit 1
}

touch "$PROJECT_MEMORY"

changed_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$no_change_state_file"
)"

assert_contains "$changed_run" "Nightly maintenance complete for scope=project"
assert_contains "$changed_run" "Interval maintenance marked successful completion"

delete_state_file="$STATE_ROOT/interval-maintenance-delete.last-run"
delete_epoch="$(( $(date +%s) - 3600 ))"
printf '%s\n' "$delete_epoch" > "$delete_state_file"
touch -d "@$((delete_epoch - 60))" "$PROJECT_MEMORY"
find "$PROJECT_MEMORY" -type f -exec touch -d "@$((delete_epoch - 60))" {} +
delete_probe="$PROJECT_MEMORY/delete-me.txt"
printf 'temporary\n' > "$delete_probe"
touch -d "@$((delete_epoch - 60))" "$delete_probe"
rm -f "$delete_probe"

delete_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$delete_state_file"
)"

assert_contains "$delete_run" "Nightly maintenance complete for scope=project"
assert_contains "$delete_run" "Interval maintenance marked successful completion"

stale_registry_project="$TMP_ROOT/stale-registry-project"
stale_registry_file="$STATE_ROOT/memory-and-improvement/project-memory-registry.txt"
mkdir -p "$(dirname "$stale_registry_file")"
cat > "$stale_registry_file" <<EOF
$stale_registry_project/.learnings
EOF
stale_registry_state_file="$STATE_ROOT/interval-maintenance-stale-registry.last-run"
stale_registry_epoch="$(( $(date +%s) - 3600 ))"
printf '%s\n' "$stale_registry_epoch" > "$stale_registry_state_file"
find "$PROJECT_MEMORY" -type f -exec touch -d "@$((stale_registry_epoch - 60))" {} +
touch -d "@$((stale_registry_epoch - 60))" "$PROJECT_MEMORY"

stale_registry_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$stale_registry_state_file"
)"

assert_contains "$stale_registry_run" "Nightly maintenance pruned missing project memory registry entry: $stale_registry_project/.learnings"
assert_contains "$stale_registry_run" "Nightly maintenance complete for scope=project"

new_file_state_file="$STATE_ROOT/interval-maintenance-new-file.last-run"
new_file_epoch="$(( $(date +%s) - 3600 ))"
printf '%s\n' "$new_file_epoch" > "$new_file_state_file"
find "$PROJECT_MEMORY" -type f -exec touch -d "@$((new_file_epoch - 60))" {} +
touch -d "@$((new_file_epoch - 60))" "$PROJECT_MEMORY"
printf 'new\n' > "$PROJECT_MEMORY/new-file.txt"

new_file_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$PROJECT_ROOT" \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$new_file_state_file"
)"

assert_contains "$new_file_run" "Nightly maintenance complete for scope=project"
assert_contains "$new_file_run" "Interval maintenance marked successful completion"

GLOBAL_ROOT="$TMP_ROOT/global-memory"
GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces"
GLOBAL_NAMESPACE_ONE="$GLOBAL_NAMESPACES_ROOT/research-principle"
GLOBAL_NAMESPACE_TWO="$GLOBAL_NAMESPACES_ROOT/research-history"
GLOBAL_STATE_FILE="$STATE_ROOT/interval-maintenance-global.last-run"
GLOBAL_EPOCH="$(( $(date +%s) - 3600 ))"

mkdir -p "$GLOBAL_NAMESPACE_ONE/.learnings" "$GLOBAL_NAMESPACE_TWO/.learnings"
cat > "$GLOBAL_NAMESPACE_ONE/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
cat > "$GLOBAL_NAMESPACE_TWO/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
printf '%s\n' "$GLOBAL_EPOCH" > "$GLOBAL_STATE_FILE"
find "$GLOBAL_ROOT" -exec touch -d "@$((GLOBAL_EPOCH - 60))" {} +
rm -rf "$GLOBAL_NAMESPACE_TWO"
touch "$GLOBAL_NAMESPACES_ROOT"

global_namespace_change_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_NAMESPACES_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope global \
            --namespace research-principle \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$GLOBAL_STATE_FILE"
)"

assert_contains "$global_namespace_change_run" "Nightly maintenance complete for scope=global"
assert_contains "$global_namespace_change_run" "Interval maintenance marked successful completion"

GLOBAL_NO_CHANGE_ROOT="$TMP_ROOT/global-memory-no-change"
GLOBAL_NO_CHANGE_NAMESPACES="$GLOBAL_NO_CHANGE_ROOT/namespaces"
GLOBAL_NO_CHANGE_NAMESPACE="$GLOBAL_NO_CHANGE_NAMESPACES/research-principle"
GLOBAL_NO_CHANGE_STATE_FILE="$STATE_ROOT/interval-maintenance-global-no-change.last-run"
GLOBAL_NO_CHANGE_EPOCH="$(( $(date +%s) - 3600 ))"

mkdir -p "$GLOBAL_NO_CHANGE_NAMESPACE/.learnings"
cat > "$GLOBAL_NO_CHANGE_NAMESPACE/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
printf '%s\n' "$GLOBAL_NO_CHANGE_EPOCH" > "$GLOBAL_NO_CHANGE_STATE_FILE"
find "$GLOBAL_NO_CHANGE_ROOT" -exec touch -d "@$((GLOBAL_NO_CHANGE_EPOCH - 60))" {} +

global_no_change_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_NO_CHANGE_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_NO_CHANGE_NAMESPACES" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope global \
            --namespace research-principle \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$GLOBAL_NO_CHANGE_STATE_FILE"
)"

assert_contains "$global_no_change_run" "Interval maintenance skipped: no relevant memory changes since epoch=$GLOBAL_NO_CHANGE_EPOCH"

GLOBAL_CREATE_ROOT="$TMP_ROOT/global-memory-create"
GLOBAL_CREATE_NAMESPACES="$GLOBAL_CREATE_ROOT/namespaces"
GLOBAL_CREATE_NAMESPACE_ONE="$GLOBAL_CREATE_NAMESPACES/research-principle"
GLOBAL_CREATE_STATE_FILE="$STATE_ROOT/interval-maintenance-global-create.last-run"
GLOBAL_CREATE_EPOCH="$(( $(date +%s) - 3600 ))"

mkdir -p "$GLOBAL_CREATE_NAMESPACE_ONE/.learnings"
cat > "$GLOBAL_CREATE_NAMESPACE_ONE/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
printf '%s\n' "$GLOBAL_CREATE_EPOCH" > "$GLOBAL_CREATE_STATE_FILE"
find "$GLOBAL_CREATE_ROOT" -exec touch -d "@$((GLOBAL_CREATE_EPOCH - 60))" {} +
mkdir -p "$GLOBAL_CREATE_NAMESPACES/user-profile/.learnings"
cat > "$GLOBAL_CREATE_NAMESPACES/user-profile/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
touch "$GLOBAL_CREATE_NAMESPACES"

global_namespace_create_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_CREATE_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_CREATE_NAMESPACES" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope global \
            --namespace research-principle \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$GLOBAL_CREATE_STATE_FILE"
)"

assert_contains "$global_namespace_create_run" "Nightly maintenance complete for scope=global"
assert_contains "$global_namespace_create_run" "Interval maintenance marked successful completion"

BOTH_PROJECT_ONLY_ROOT="$TMP_ROOT/both-project-only"
BOTH_PROJECT_ONLY_MEMORY="$BOTH_PROJECT_ONLY_ROOT/.learnings"
BOTH_PROJECT_ONLY_GLOBAL_ROOT="$TMP_ROOT/both-project-only-global"
BOTH_PROJECT_ONLY_NAMESPACES="$BOTH_PROJECT_ONLY_GLOBAL_ROOT/namespaces"
BOTH_PROJECT_ONLY_NAMESPACE="$BOTH_PROJECT_ONLY_NAMESPACES/research-principle"
BOTH_PROJECT_ONLY_STATE_FILE="$STATE_ROOT/interval-maintenance-both-project-only.last-run"
BOTH_PROJECT_ONLY_EPOCH="$(( $(date +%s) - 3600 ))"

mkdir -p "$BOTH_PROJECT_ONLY_MEMORY" "$BOTH_PROJECT_ONLY_NAMESPACE/.learnings"
cat > "$BOTH_PROJECT_ONLY_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
cat > "$BOTH_PROJECT_ONLY_NAMESPACE/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
printf '%s\n' "$BOTH_PROJECT_ONLY_EPOCH" > "$BOTH_PROJECT_ONLY_STATE_FILE"
find "$BOTH_PROJECT_ONLY_ROOT" "$BOTH_PROJECT_ONLY_GLOBAL_ROOT" -exec touch -d "@$((BOTH_PROJECT_ONLY_EPOCH - 60))" {} +
touch "$BOTH_PROJECT_ONLY_MEMORY/LEARNINGS.md"

both_project_only_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$BOTH_PROJECT_ONLY_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$BOTH_PROJECT_ONLY_GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$BOTH_PROJECT_ONLY_NAMESPACES" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope both \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$BOTH_PROJECT_ONLY_STATE_FILE"
)"

assert_contains "$both_project_only_run" "Nightly maintenance complete for scope=both"
assert_contains "$both_project_only_run" "Interval maintenance marked successful completion"

BOTH_GLOBAL_ONLY_ROOT="$TMP_ROOT/both-global-only"
BOTH_GLOBAL_ONLY_MEMORY="$BOTH_GLOBAL_ONLY_ROOT/.learnings"
BOTH_GLOBAL_ONLY_GLOBAL_ROOT="$TMP_ROOT/both-global-only-global"
BOTH_GLOBAL_ONLY_NAMESPACES="$BOTH_GLOBAL_ONLY_GLOBAL_ROOT/namespaces"
BOTH_GLOBAL_ONLY_NAMESPACE="$BOTH_GLOBAL_ONLY_NAMESPACES/research-principle"
BOTH_GLOBAL_ONLY_STATE_FILE="$STATE_ROOT/interval-maintenance-both-global-only.last-run"
BOTH_GLOBAL_ONLY_EPOCH="$(( $(date +%s) - 3600 ))"

mkdir -p "$BOTH_GLOBAL_ONLY_MEMORY" "$BOTH_GLOBAL_ONLY_NAMESPACE/.learnings"
cat > "$BOTH_GLOBAL_ONLY_MEMORY/LEARNINGS.md" <<'EOF'
# Project Learnings
EOF
cat > "$BOTH_GLOBAL_ONLY_NAMESPACE/.learnings/LEARNINGS.md" <<'EOF'
# Global Learnings
EOF
printf '%s\n' "$BOTH_GLOBAL_ONLY_EPOCH" > "$BOTH_GLOBAL_ONLY_STATE_FILE"
find "$BOTH_GLOBAL_ONLY_ROOT" "$BOTH_GLOBAL_ONLY_GLOBAL_ROOT" -exec touch -d "@$((BOTH_GLOBAL_ONLY_EPOCH - 60))" {} +
touch "$BOTH_GLOBAL_ONLY_NAMESPACE/.learnings/LEARNINGS.md"

both_global_only_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$BOTH_GLOBAL_ONLY_ROOT" \
        SELF_IMPROVING_GLOBAL_ROOT="$BOTH_GLOBAL_ONLY_GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$BOTH_GLOBAL_ONLY_NAMESPACES" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope both \
            --interval-minutes 30 \
            --writeback false \
            --state-file "$BOTH_GLOBAL_ONLY_STATE_FILE"
)"

assert_contains "$both_global_only_run" "Nightly maintenance complete for scope=both"
assert_contains "$both_global_only_run" "Interval maintenance marked successful completion"

WRITEBACK_PROJECT="$TMP_ROOT/writeback-project"
WRITEBACK_STATE_FILE="$STATE_ROOT/interval-maintenance-writeback.last-run"
WRITEBACK_EPOCH="$(( $(date +%s) - 3600 ))"
mkdir -p "$WRITEBACK_PROJECT"
make_project_fixture "$WRITEBACK_PROJECT" "Interval maintenance should forward writeback=true into nightly project summary generation" "interval.project.writeback"
printf '%s\n' "$WRITEBACK_EPOCH" > "$WRITEBACK_STATE_FILE"
find "$WRITEBACK_PROJECT" -exec touch -d "@$((WRITEBACK_EPOCH - 60))" {} +
touch "$WRITEBACK_PROJECT/.learnings/LEARNINGS.md"

writeback_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$WRITEBACK_PROJECT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$WRITEBACK_PROJECT" \
            --interval-minutes 30 \
            --writeback true \
            --state-file "$WRITEBACK_STATE_FILE"
)"

assert_contains "$writeback_run" "Nightly maintenance complete for scope=project"
assert_contains "$writeback_run" "Interval maintenance marked successful completion"
assert_contains_file "$WRITEBACK_PROJECT/.learnings/SUMMARY.md" "Interval maintenance should forward writeback=true into nightly project summary generation"

SKILL_FALSE_PROJECT="$TMP_ROOT/skill-false-project"
SKILL_FALSE_SKILL="$TMP_ROOT/skill-false.md"
SKILL_FALSE_STATE_FILE="$STATE_ROOT/interval-maintenance-skill-false.last-run"
SKILL_FALSE_EPOCH="$(( $(date +%s) - 3600 ))"
mkdir -p "$SKILL_FALSE_PROJECT"
make_skill_policy_fixture "$SKILL_FALSE_PROJECT" "LRN-SP-INT-002"
cat > "$SKILL_FALSE_SKILL" <<'EOF'
# Memory-and-Improvement Skill

## Adaptive Routing Strategy

<!-- memory-auto-skill-policy:start -->
- none promoted yet
<!-- memory-auto-skill-policy:end -->
EOF
printf '%s\n' "$SKILL_FALSE_EPOCH" > "$SKILL_FALSE_STATE_FILE"
find "$SKILL_FALSE_PROJECT" -exec touch -d "@$((SKILL_FALSE_EPOCH - 60))" {} +
touch "$SKILL_FALSE_PROJECT/.learnings/LEARNINGS.md"

skill_false_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$SKILL_FALSE_PROJECT" \
        SELF_IMPROVING_SKILL_FILE="$SKILL_FALSE_SKILL" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$SKILL_FALSE_PROJECT" \
            --interval-minutes 30 \
            --writeback false \
            --skill-policy-writeback false \
            --state-file "$SKILL_FALSE_STATE_FILE"
)"

assert_contains "$skill_false_run" "Nightly maintenance complete for scope=project"
assert_contains_file "$SKILL_FALSE_SKILL" "- none promoted yet"
assert_not_contains_file "$SKILL_FALSE_SKILL" "[LRN-SP-INT-002]"

GIT_PROJECT="$TMP_ROOT/git-project"
GIT_STATE_FILE="$STATE_ROOT/interval-maintenance-git.last-run"
GIT_EPOCH="$(( $(date +%s) - 3600 ))"
GIT_HOME="$TMP_ROOT/git-home"
mkdir -p "$GIT_PROJECT" "$GIT_HOME"
cat > "$GIT_HOME/.gitconfig" <<'EOF'
[init]
    defaultBranch = main
EOF
make_project_fixture "$GIT_PROJECT" "Interval maintenance should forward git-commit=true into nightly git commits" "interval.project.git"
printf '%s\n' "$GIT_EPOCH" > "$GIT_STATE_FILE"
find "$GIT_PROJECT" -exec touch -d "@$((GIT_EPOCH - 60))" {} +
touch "$GIT_PROJECT/.learnings/LEARNINGS.md"

git_run="$(
    env \
        HOME="$GIT_HOME" \
        SELF_IMPROVING_PROJECT_ROOT="$GIT_PROJECT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope project \
            --project-root "$GIT_PROJECT" \
            --interval-minutes 30 \
            --writeback true \
            --git-commit true \
            --state-file "$GIT_STATE_FILE"
)"

assert_contains "$git_run" "Nightly maintenance complete for scope=project"
assert_contains "$git_run" "Committed memory changes in"
assert_contains_file "$GIT_PROJECT/.learnings/SUMMARY.md" "Interval maintenance should forward git-commit=true into nightly git commits"
if [[ ! -d "$GIT_PROJECT/.learnings/.git" ]]; then
    printf 'Expected interval maintenance to initialize git in %s\n' "$GIT_PROJECT/.learnings" >&2
    exit 1
fi
git_interval_subject="$(git -C "$GIT_PROJECT/.learnings" log -1 --pretty=%s)"
if [[ "$git_interval_subject" != "memory: nightly maintenance $(date +%F)" ]]; then
    printf 'Expected interval-forwarded nightly commit subject to match nightly format, got: %s\n' "$git_interval_subject" >&2
    exit 1
fi

BOTH_FORWARD_PROJECT="$TMP_ROOT/both-forward-project"
BOTH_FORWARD_GLOBAL_ROOT="$TMP_ROOT/both-forward-global"
BOTH_FORWARD_NAMESPACES="$BOTH_FORWARD_GLOBAL_ROOT/namespaces"
BOTH_FORWARD_NAMESPACE="$BOTH_FORWARD_NAMESPACES/research-principle"
BOTH_FORWARD_STATE_FILE="$STATE_ROOT/interval-maintenance-both-forward.last-run"
BOTH_FORWARD_EPOCH="$(( $(date +%s) - 3600 ))"
mkdir -p "$BOTH_FORWARD_PROJECT" "$BOTH_FORWARD_NAMESPACE"
make_project_fixture "$BOTH_FORWARD_PROJECT" "Interval maintenance both-scope should update project memory summaries" "interval.both.project"
make_project_fixture "$BOTH_FORWARD_NAMESPACE" "Interval maintenance both-scope should update global memory summaries" "interval.both.global"
printf '%s\n' "$BOTH_FORWARD_EPOCH" > "$BOTH_FORWARD_STATE_FILE"
find "$BOTH_FORWARD_PROJECT" "$BOTH_FORWARD_GLOBAL_ROOT" -exec touch -d "@$((BOTH_FORWARD_EPOCH - 60))" {} +
touch "$BOTH_FORWARD_PROJECT/.learnings/LEARNINGS.md"

both_forward_run="$(
    env \
        SELF_IMPROVING_PROJECT_ROOT="$BOTH_FORWARD_PROJECT" \
        SELF_IMPROVING_GLOBAL_ROOT="$BOTH_FORWARD_GLOBAL_ROOT" \
        SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$BOTH_FORWARD_NAMESPACES" \
        SELF_IMPROVING_GLOBAL_NAMESPACE="research-principle" \
        XDG_STATE_HOME="$STATE_ROOT" \
        bash "$INTERVAL_SCRIPT" \
            --scope both \
            --interval-minutes 30 \
            --writeback true \
            --state-file "$BOTH_FORWARD_STATE_FILE"
)"

assert_contains "$both_forward_run" "Nightly maintenance complete for scope=both"
assert_contains_file "$BOTH_FORWARD_PROJECT/.learnings/SUMMARY.md" "Interval maintenance both-scope should update project memory summaries"
assert_contains_file "$BOTH_FORWARD_NAMESPACE/SUMMARY.md" "Interval maintenance both-scope should update global memory summaries"

printf 'interval-maintenance assertions passed\n'
