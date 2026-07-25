#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFLECT_SCRIPT="$SKILL_DIR/scripts/recall/reflect-memory.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        exit 1
    fi
}

project_root="$(mktemp -d)"
trap 'rm -rf "$project_root"' EXIT

correction_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event correction \
        --summary "User corrected the repo-specific recall behavior"
)"
assert_contains "$correction_output" "Resolved-Scope: project"
assert_contains "$correction_output" "Primary-Action: log_learning"
assert_contains "$correction_output" "Suggested-Type: learning"

summary_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event decision \
        --summary "Recurring default convention for repo audit flow"
)"
assert_contains "$summary_output" "Primary-Action: log_learning"
assert_contains "$summary_output" "Secondary-Action: consider_summary"

failure_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event failure \
        --summary "Command failed because the hook script path was missing"
)"
assert_contains "$failure_output" "Primary-Action: log_error"
assert_contains "$failure_output" "Suggested-Type: error"

skill_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event implementation \
        --summary "Defined a reusable workflow for audit-focused repo review" \
        --details "This repeatable process should likely become a skill candidate."
)"
assert_contains "$skill_output" "Primary-Action: consider_skill"
assert_contains "$skill_output" "Resolved-Scope: project"
assert_contains "$skill_output" "Secondary-Action: log_learning"
assert_contains "$skill_output" "Skill-Hint: consider extracting a reusable procedure instead of only logging raw memory"
assert_contains "$skill_output" "Promotion-Hint: the wording suggests a stable or recurring pattern worth later summary review"

feature_request_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event feature_request \
        --summary "Need a helper for structured reflect suggestions"
)"
assert_contains "$feature_request_output" "Primary-Action: log_feature_request"
assert_contains "$feature_request_output" "Suggested-Type: feature_request"

global_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --scope global \
        --namespace user-profile \
        --event decision \
        --summary "Preferred name wording changed for user profile responses"
)"
assert_contains "$global_output" "Resolved-Scope: global"
assert_contains "$global_output" "Resolved-Namespace: user-profile"

repo_profile_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event implementation \
        --summary "Refined the profile page layout for this repo"
)"
assert_contains "$repo_profile_output" "Resolved-Scope: project"

repo_publication_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event implementation \
        --summary "Refined the publication page layout for this repo"
)"
assert_contains "$repo_publication_output" "Resolved-Scope: project"

no_action_output="$(
    bash "$REFLECT_SCRIPT" \
        --project-root "$project_root" \
        --event other \
        --summary "No durable info from this turn"
)"
assert_contains "$no_action_output" "Primary-Action: no_action"
assert_contains "$no_action_output" "Suggested-Type: none"

printf 'reflect-memory assertions passed\n'
