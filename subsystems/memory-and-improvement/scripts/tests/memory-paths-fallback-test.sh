#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATHS_SCRIPT="$SKILL_DIR/scripts/shared/memory-paths.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-paths-fallback-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
HOME_ROOT="$TMP_ROOT/home"
PROJECT_ROOT="$TMP_ROOT/project"
SAMPLE_FILE="$TMP_ROOT/sample.txt"

mkdir -p "$FAKE_BIN" "$HOME_ROOT" "$PROJECT_ROOT"

for cmd_name in dirname realpath grep; do
    cmd_path="$(command -v "$cmd_name")"
    ln -s "$cmd_path" "$FAKE_BIN/$cmd_name"
done

cat > "$SAMPLE_FILE" <<'EOF'
alpha
LRN-20260402-001
beta
EOF

fallback_output="$(
    env \
        PATH="$FAKE_BIN" \
        HOME="$HOME_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        SAMPLE_FILE="$SAMPLE_FILE" \
        /bin/bash -c '
            source "'"$PATHS_SCRIPT"'"
            printf "has_rg=%s\n" "$(self_improving_has_ripgrep && printf true || printf false)"
            printf "match=%s\n" "$(self_improving_extract_matches "LRN-[0-9]{8}-[0-9]{3}" "$SAMPLE_FILE")"
            if self_improving_contains_fixed "alpha" "$SAMPLE_FILE"; then
                printf "fixed=true\n"
            else
                printf "fixed=false\n"
            fi
            if self_improving_contains_regex "beta$" "$SAMPLE_FILE"; then
                printf "regex=true\n"
            else
                printf "regex=false\n"
            fi
        '
)"

assert_contains "$fallback_output" "has_rg=false"
assert_contains "$fallback_output" "match=LRN-20260402-001"
assert_contains "$fallback_output" "fixed=true"
assert_contains "$fallback_output" "regex=true"

printf 'memory-paths fallback assertions passed\n'
