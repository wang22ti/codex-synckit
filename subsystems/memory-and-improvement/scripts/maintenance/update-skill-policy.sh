#!/bin/bash
# Update the managed routing-strategy block in SKILL.md from high-signal policy corrections.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"
. "$SCRIPT_ROOT/shared/file-lock.sh"

project_root="$self_improving_project_root"
project_memory_dir=""
if [[ "$self_improving_project_memory_dir_overridden" == true ]]; then
    project_memory_dir="$self_improving_project_memory_dir"
fi
scope="project"
skill_file="${SELF_IMPROVING_SKILL_FILE:-$self_improving_skill_dir/SKILL.md}"
max_items=6
dry_run=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--scope project|both] [--project-root PATH] [--project-memory-dir PATH] [--skill-file PATH] [--max-items N] [--dry-run]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            scope="${2:-}"
            shift 2
            ;;
        --project-root)
            project_root="${2:-}"
            shift 2
            ;;
        --project-memory-dir)
            project_memory_dir="${2:-}"
            shift 2
            ;;
        --skill-file)
            skill_file="${2:-}"
            shift 2
            ;;
        --max-items)
            max_items="${2:-}"
            shift 2
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$scope" in
    project|both) ;;
    *)
        echo "Invalid scope: $scope" >&2
        exit 1
        ;;
esac

[[ "$max_items" =~ ^[0-9]+$ ]] || {
    echo "--max-items must be a non-negative integer" >&2
    exit 1
}

project_root="$(self_improving_normalize_path "$project_root")"
if [[ -n "$project_memory_dir" ]]; then
    project_memory_dir="$(self_improving_normalize_path "$project_memory_dir")"
fi
skill_file="$(self_improving_normalize_path "$skill_file")"
resolved_project_memory_dir="$(self_improving_resolve_project_memory_dir "$project_root" "$project_memory_dir")"
target_file="$resolved_project_memory_dir/LEARNINGS.md"
python_cmd=""
if command -v python3 >/dev/null 2>&1; then
    python_cmd="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    python_cmd="$(command -v python)"
else
    echo "Python 3 is required to update the skill policy" >&2
    exit 1
fi

block_lines="- none promoted yet"
if [[ -f "$target_file" ]]; then
    block_lines="$(
        "$python_cmd" - "$max_items" "$target_file" <<'PY'
import re
import sys
from pathlib import Path
from datetime import datetime

max_items = int(sys.argv[1])
files = [sys.argv[2]]

strategy_phrases = [
    "skill policy",
    "skill.md",
    "maintainer policy",
    "routing strategy",
    "routing policy",
    "promotion policy",
    "promotion strategy",
    "fallback-only",
    "defaults.toml",
    "install-nightly-maintenance.sh --apply",
    "live crontab",
]

policy_tags = {
    "routing-policy",
    "promotion-policy",
    "skill-policy",
    "maintainer-policy",
    "automation-policy",
}

excluded_tags = {
    "user-profile",
    "memory-assets",
    "papers",
    "publications",
    "paper-assets",
    "asset-policy",
}

excluded_phrases = [
    "publications.md",
    "paper pdf",
    "paper pdfs",
    "user-profile paper assets",
    "global-memory assets",
    "homepage scrape",
    "publication records",
]

def section_text(body: str, title: str) -> str:
    pattern = rf"^### {re.escape(title)}\n(.*?)(?=^### |\Z)"
    match = re.search(pattern, body, re.S | re.M)
    if not match:
        return ""
    return " ".join(line.strip() for line in match.group(1).strip().splitlines() if line.strip())

def extract_field(body: str, label: str) -> str:
    match = re.search(rf"^\*\*{re.escape(label)}\*\*: (.+)$", body, re.M)
    return match.group(1).strip() if match else ""

entries = []
for path_str in files:
    path = Path(path_str)
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r"^## \[(?P<id>[^\]]+)\][^\n]*\n(?P<body>.*?)(?=^---\s*$|\Z)", re.S | re.M)
    for match in pattern.finditer(text):
        body = match.group("body")
        entry_id = match.group("id").strip()
        priority = extract_field(body, "Priority").lower()
        status = extract_field(body, "Status").lower()
        logged = extract_field(body, "Logged")
        summary = section_text(body, "Summary")
        details = section_text(body, "Details")
        suggested = section_text(body, "Suggested Action")
        tag_match = re.search(r"^- Tags: (.+)$", body, re.M)
        tags = tag_match.group(1).strip().lower() if tag_match else ""

        if not summary:
            continue
        if priority not in {"high", "critical"}:
            continue
        if status not in {"resolved", "promoted_to_summary", "promoted_to_skill"}:
            continue

        combined = " ".join([summary, details, suggested]).lower()
        tag_set = {tag.strip() for tag in tags.split(",") if tag.strip()}
        phrase_hits = sum(1 for phrase in strategy_phrases if phrase in combined)
        has_policy_tag = bool(policy_tags & tag_set)
        has_excluded_tag = bool(excluded_tags & tag_set)
        has_excluded_phrase = any(phrase in combined for phrase in excluded_phrases)

        if not has_policy_tag and phrase_hits == 0:
            continue
        if has_excluded_tag or has_excluded_phrase:
            continue

        try:
            logged_key = datetime.fromisoformat(logged.replace("Z", "+00:00")).timestamp()
        except Exception:
            logged_key = 0

        entries.append((logged_key, entry_id, summary))

entries.sort(key=lambda item: (-item[0], item[1]))

deduped = []
seen_summaries = set()
for _, entry_id, summary in entries:
    if summary in seen_summaries:
        continue
    seen_summaries.add(summary)
    deduped.append(f"- [{entry_id}] {summary}")
    if len(deduped) >= max_items:
        break

print("\n".join(deduped or ["- none promoted yet"]))
PY
    )"
fi

managed_block="<!-- memory-auto-skill-policy:start -->
$block_lines
<!-- memory-auto-skill-policy:end -->"

if [[ "$dry_run" == true ]]; then
    printf 'Would update %s with:\n%s\n' "$skill_file" "$managed_block"
    exit 0
fi

if [[ ! -f "$skill_file" ]]; then
    echo "Skill file not found: $skill_file" >&2
    exit 1
fi

skill_lock_file="${skill_file}.lock"
self_improving_lock_acquire skill_policy "$skill_lock_file" 9

tmp_file="$(mktemp "${skill_file}.tmp.XXXXXX")" || {
    echo "Failed to allocate a temporary file for rewriting the skill policy block." >&2
    self_improving_lock_release skill_policy
    exit 1
}
cleanup() {
    rm -f "$tmp_file"
    self_improving_lock_release skill_policy
}
trap cleanup EXIT

if self_improving_contains_fixed "<!-- memory-auto-skill-policy:start -->" "$skill_file"; then
    BLOCK_CONTENT="$managed_block" perl -0pe '
        s{<!-- memory-auto-skill-policy:start -->\n[\s\S]*?<!-- memory-auto-skill-policy:end -->}{$ENV{BLOCK_CONTENT}}g
    ' "$skill_file" > "$tmp_file"
else
    cat "$skill_file" > "$tmp_file"
    cat <<EOF >> "$tmp_file"

## Adaptive Routing Strategy

This section is auto-managed by \`scripts/maintenance/update-skill-policy.sh\`.
It may rewrite only the strategy hints below; it must not rewrite the rest of this skill.

$managed_block
EOF
fi

mv "$tmp_file" "$skill_file"
trap - EXIT
self_improving_lock_release skill_policy

printf 'Updated skill policy block in %s\n' "$skill_file"
