#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_SCRIPT="$SKILL_DIR/scripts/maintenance/git-memory.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-git-opt-out.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/project" "$TEST_ROOT/parent/memory/namespaces/project/.learnings"

run_memory() {
    env HOME="$TEST_ROOT/home" \
        SELF_IMPROVING_PROJECT_REGISTRY_FILE="$TEST_ROOT/registry.tsv" \
        SELF_IMPROVING_PROJECT_ROOT="$TEST_ROOT/project" \
        SELF_IMPROVING_GLOBAL_ROOT="$TEST_ROOT/parent/memory" \
        "$@"
}

git -C "$TEST_ROOT/parent" init -q
git -C "$TEST_ROOT/parent" -c user.name=Test -c user.email=test@local commit --allow-empty -qm baseline
baseline="$(git -C "$TEST_ROOT/parent" rev-parse HEAD)"
touch "$TEST_ROOT/parent/memory/.memory-no-git"
for action in init status commit; do
    run_memory bash "$GIT_SCRIPT" "$action" --scope global
    run_memory bash "$GIT_SCRIPT" "$action" --scope global \
        --global-memory-dir "$TEST_ROOT/parent/memory/namespaces/project/.learnings"
    run_memory bash "$GIT_SCRIPT" "$action" --scope project \
        --project-memory-dir "$TEST_ROOT/parent/memory/project-memory"
done

run_memory bash "$SKILL_DIR/scripts/capture/log-memory.sh" --scope global --namespace project \
    --type learning --summary 'Opt-out must preserve capture' --git-autocommit true
run_memory bash "$SKILL_DIR/scripts/maintenance/nightly-maintenance.sh" \
    --scope global --git-commit true --writeback false --skill-policy-writeback false
grep -Fq 'Opt-out must preserve capture' "$TEST_ROOT/parent/memory/namespaces/project/.learnings/LEARNINGS.md"
[[ -z "$(find "$TEST_ROOT/parent/memory" -name .git -print -quit)" ]]
[[ "$(git -C "$TEST_ROOT/parent" rev-parse HEAD)" == "$baseline" ]]
[[ -z "$(git -C "$TEST_ROOT/parent" diff --cached --name-only)" ]]

# A separate unmarked memory directory still supports ordinary Git operations.
run_memory bash "$GIT_SCRIPT" init --scope project
[[ -d "$TEST_ROOT/project/.learnings/.git" ]]
printf 'PASS: opt-out blocks all Git actions and parent staging; capture, maintenance and unmarked Git work.\n'
