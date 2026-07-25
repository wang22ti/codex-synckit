#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$SKILL_DIR/scripts/bootstrap/init-memory.sh"
LOG_ASSET_SCRIPT="$SKILL_DIR/scripts/capture/log-asset.sh"
REVIEW_SCRIPT="$SKILL_DIR/scripts/recall/review-memory.sh"
SEARCH_SCRIPT="$SKILL_DIR/scripts/recall/search-memory.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_ROOT="$TMP_DIR/project"
GLOBAL_ROOT="$TMP_DIR/global-memory"
STATE_ROOT="$TMP_DIR/state"
mkdir -p "$PROJECT_ROOT"

export SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT"
export SELF_IMPROVING_GLOBAL_ROOT="$GLOBAL_ROOT"
export SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT="$GLOBAL_ROOT/namespaces"
export SELF_IMPROVING_GLOBAL_NAMESPACE="user-profile"
export XDG_STATE_HOME="$STATE_ROOT"

bash "$INIT_SCRIPT" --scope both --project-root "$PROJECT_ROOT" >/dev/null

PDF_FILE="$TMP_DIR/rebuttal.pdf"
FACT_FILE="$GLOBAL_ROOT/namespaces/user-profile/FUNDING_HISTORY.md"

printf 'pdf placeholder\n' > "$PDF_FILE"
cat <<'EOF' > "$FACT_FILE"
# Funding History

- 2025: Example Fellowship
EOF

bash "$LOG_ASSET_SCRIPT" \
    --scope project \
    --project-root "$PROJECT_ROOT" \
    --title "Rebuttal PDF" \
    --type paper_pdf \
    --canonical-path "$PDF_FILE" \
    --summary "Representative rebuttal artifact" \
    --tags "paper,rebuttal" \
    --related-memory-ids "LRN-20260401-001" >/dev/null

bash "$LOG_ASSET_SCRIPT" \
    --scope project \
    --project-root "$PROJECT_ROOT" \
    --title "Rebuttal PDF Updated" \
    --type paper_pdf \
    --canonical-path "$TMP_DIR/./rebuttal.pdf" \
    --summary "Representative rebuttal artifact updated" \
    --tags "paper,rebuttal,updated" \
    --status active >/dev/null

PROFILE_FILE="$GLOBAL_ROOT/namespaces/user-profile/PROFILE.md"
PUBLICATIONS_FILE="$GLOBAL_ROOT/namespaces/user-profile/PUBLICATIONS.md"

cat <<'EOF' > "$PROFILE_FILE"
# Profile
EOF

cat <<'EOF' > "$PUBLICATIONS_FILE"
# Publications
EOF

bash "$LOG_ASSET_SCRIPT" \
    --scope global \
    --project-root "$PROJECT_ROOT" \
    --namespace user-profile \
    --title "Funding History Fact File" \
    --type structured_fact_file \
    --canonical-path "$FACT_FILE" \
    --summary "Structured funding history for the user profile namespace" \
    --tags "funding,profile" >/dev/null &

bash "$LOG_ASSET_SCRIPT" \
    --scope global \
    --project-root "$PROJECT_ROOT" \
    --namespace user-profile \
    --title "Profile Fact File" \
    --type structured_fact_file \
    --canonical-path "$PROFILE_FILE" \
    --summary "Structured profile file for the user profile namespace" \
    --tags "profile,user" >/dev/null &

bash "$LOG_ASSET_SCRIPT" \
    --scope global \
    --project-root "$PROJECT_ROOT" \
    --namespace user-profile \
    --title "Publications Fact File" \
    --type structured_fact_file \
    --canonical-path "$PUBLICATIONS_FILE" \
    --summary "Structured publications file for the user profile namespace" \
    --tags "publications,profile" >/dev/null &

wait

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

project_index="$(cat "$PROJECT_ROOT/.learnings/assets/INDEX.md")"
assert_contains "$project_index" "Rebuttal PDF Updated"
assert_contains "$project_index" "paper_pdf"
assert_contains "$project_index" "Representative rebuttal artifact updated"
assert_contains "$project_index" "Status: active"
project_asset_ids="$(printf '%s\n' "$project_index" | rg -o 'AST-[0-9]{8}-[0-9]{3}' | sort | uniq | wc -l | tr -d ' ')"
if [[ "$project_asset_ids" != "1" ]]; then
    printf 'Expected project asset update to keep a single asset id, got %s\n' "$project_asset_ids" >&2
    exit 1
fi

global_index="$(cat "$GLOBAL_ROOT/namespaces/user-profile/assets/INDEX.md")"
assert_contains "$global_index" "Funding History Fact File"
assert_contains "$global_index" "structured_fact_file"
assert_contains "$global_index" "$FACT_FILE"
assert_contains "$global_index" "Profile Fact File"
assert_contains "$global_index" "Publications Fact File"

unique_asset_ids="$(printf '%s\n' "$global_index" | rg -o 'AST-[0-9]{8}-[0-9]{3}' | sort | uniq | wc -l | tr -d ' ')"
if [[ "$unique_asset_ids" != "3" ]]; then
    printf 'Expected 3 unique global asset ids, got %s\n' "$unique_asset_ids" >&2
    exit 1
fi

review_output="$(bash "$REVIEW_SCRIPT" --scope both --project-root "$PROJECT_ROOT" --namespace user-profile)"
assert_contains "$review_output" "Project indexed assets:"
assert_contains "$review_output" "Global indexed assets:"
assert_contains "$review_output" "Funding History Fact File"

search_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --namespace user-profile --type asset --query funding)"
assert_contains "$search_output" "Type: asset"
assert_contains "$search_output" "[AST-"
assert_contains "$search_output" "Structured funding history for the user profile namespace"

status_search_output="$(bash "$SEARCH_SCRIPT" --scope global --project-root "$PROJECT_ROOT" --namespace user-profile --type asset --status active --query funding)"
assert_contains "$status_search_output" "Status: active"
assert_contains "$status_search_output" "Structured funding history for the user profile namespace"

printf 'log-asset assertions passed\n'
