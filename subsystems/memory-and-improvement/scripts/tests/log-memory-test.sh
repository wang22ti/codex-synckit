#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_SCRIPT="$SKILL_DIR/scripts/capture/log-memory.sh"

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

assert_equals() {
    local actual="$1"
    local expected="$2"

    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected %s but got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/log-memory-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_TRUE="$TMP_ROOT/home-true"
PROJECT_TRUE="$TMP_ROOT/project-true"

mkdir -p "$HOME_TRUE/.codex/skills/memory-and-improvement" "$PROJECT_TRUE"
cat > "$HOME_TRUE/.gitconfig" <<'EOF'
[init]
    defaultBranch = main
EOF
cat > "$HOME_TRUE/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = true
EOF

true_output="$(
    env \
        HOME="$HOME_TRUE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_TRUE" \
        bash "$LOG_SCRIPT" \
            --scope project \
            --type learning \
            --summary "Config enables git autocommit for log-memory"
)"

assert_contains "$true_output" "Appended LRN-"
assert_contains_file "$PROJECT_TRUE/.learnings/LEARNINGS.md" "Config enables git autocommit for log-memory"
if [[ ! -d "$PROJECT_TRUE/.learnings/.git" ]]; then
    printf 'Expected git-autocommit=true config to initialize git in %s\n' "$PROJECT_TRUE/.learnings" >&2
    exit 1
fi

true_commit_count="$(git -C "$PROJECT_TRUE/.learnings" rev-list --count HEAD)"
if [[ "$true_commit_count" -lt 1 ]]; then
    printf 'Expected at least one git commit, found %s\n' "$true_commit_count" >&2
    exit 1
fi

HOME_FALSE="$TMP_ROOT/home-false"
PROJECT_FALSE="$TMP_ROOT/project-false"

mkdir -p "$HOME_FALSE/.codex/skills/memory-and-improvement" "$PROJECT_FALSE"
cat > "$HOME_FALSE/.gitconfig" <<'EOF'
[init]
    defaultBranch = main
EOF
cat > "$HOME_FALSE/.codex/skills/memory-and-improvement/config.toml" <<'EOF'
[defaults]
git_autocommit = true
EOF

false_output="$(
    env \
        HOME="$HOME_FALSE" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_FALSE" \
        bash "$LOG_SCRIPT" \
            --scope project \
            --type learning \
            --summary "CLI override disables git autocommit" \
            --git-autocommit false
)"

assert_contains "$false_output" "Appended LRN-"
assert_contains_file "$PROJECT_FALSE/.learnings/LEARNINGS.md" "CLI override disables git autocommit"
if [[ -d "$PROJECT_FALSE/.learnings/.git" ]]; then
    printf 'Expected --git-autocommit false to prevent git repo initialization in %s\n' "$PROJECT_FALSE/.learnings" >&2
    exit 1
fi

HOME_CONCURRENT="$TMP_ROOT/home-concurrent"
PROJECT_CONCURRENT="$TMP_ROOT/project-concurrent"

mkdir -p "$HOME_CONCURRENT/.codex/skills/memory-and-improvement" "$PROJECT_CONCURRENT"

for i in 1 2 3 4 5 6; do
    env \
        HOME="$HOME_CONCURRENT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_CONCURRENT" \
        bash "$LOG_SCRIPT" \
            --scope project \
            --type learning \
            --summary "Concurrent logging entry $i" \
            --pattern-key "concurrent.logging.entry.$i" \
            --git-autocommit false \
            >"$TMP_ROOT/concurrent-$i.out" 2>&1 &
done

wait

CONCURRENT_FILE="$PROJECT_CONCURRENT/.learnings/LEARNINGS.md"

for i in 1 2 3 4 5 6; do
    assert_contains_file "$CONCURRENT_FILE" "Concurrent logging entry $i"
done

heading_count="$(grep -Ec '^## \[LRN-[0-9]{8}-[0-9]{3}\]' "$CONCURRENT_FILE")"
unique_heading_count="$(grep -Eo 'LRN-[0-9]{8}-[0-9]{3}' "$CONCURRENT_FILE" | sort | uniq | wc -l | tr -d ' ')"
assert_equals "$heading_count" "6"
assert_equals "$unique_heading_count" "6"

printf 'log-memory assertions passed\n'
