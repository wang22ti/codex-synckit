#!/bin/bash
# Skill extraction helper for Codex skills.
# Usage: extract-skill.sh <skill-name> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

SKILLS_DIR="$self_improving_codex_skills_dir"
TEMPLATE_FILE="$self_improving_skill_dir/references/SKILL-TEMPLATE.md"
SKILL_NAME=""
DRY_RUN=false
SOURCE_FILE=""
LEARNING_ID="[TODO: Add original learning ID]"
EXTRACTION_DATE="$(date +%F)"

usage() {
    cat <<EOF
Usage: $(basename "$0") <skill-name> [options]

Create a new Codex skill scaffold from a reusable learning.

Arguments:
  skill-name     Name of the skill (lowercase, hyphens for spaces)

Options:
  --dry-run      Show what would be created without creating files
  --output-dir   Override the output directory (default: $self_improving_codex_skills_dir)
  --source-file  Source memory file for the learning being promoted
  --learning-id  Learning ID being promoted
  -h, --help     Show this help message

Examples:
  $(basename "$0") docker-fixes
  $(basename "$0") api-timeout-patterns --dry-run
  $(basename "$0") pnpm-setup --output-dir ~/.codex/skills
  $(basename "$0") review-memory --source-file ~/global-memory/namespaces/research-principle/.learnings/LEARNINGS.md --learning-id LRN-20260331-001
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --output-dir)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "--output-dir requires a path argument" >&2
                usage >&2
                exit 1
            fi
            SKILLS_DIR="$2"
            shift 2
            ;;
        --source-file)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "--source-file requires a path argument" >&2
                usage >&2
                exit 1
            fi
            SOURCE_FILE="$2"
            shift 2
            ;;
        --learning-id)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "--learning-id requires a value" >&2
                usage >&2
                exit 1
            fi
            LEARNING_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$SKILL_NAME" ]]; then
                SKILL_NAME="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$SKILL_NAME" ]]; then
    echo "Skill name is required" >&2
    usage >&2
    exit 1
fi

if ! [[ "$SKILL_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid skill name. Use lowercase letters, numbers, and hyphens only." >&2
    exit 1
fi

if [[ "$SKILLS_DIR" != /* ]]; then
    SKILLS_DIR="$(cd "$PWD" && pwd)/${SKILLS_DIR#./}"
fi

if [[ -z "$SOURCE_FILE" ]]; then
    SOURCE_FILE="$self_improving_project_memory_dir/LEARNINGS.md"
elif [[ "$SOURCE_FILE" != /* ]]; then
    SOURCE_FILE="$(cd "$PWD" && pwd)/${SOURCE_FILE#./}"
fi

SKILL_PATH="$SKILLS_DIR/$SKILL_NAME"

render_template() {
    if [[ -n "$self_improving_skill_markdown_template" ]]; then
        local title
        local rendered
        title="$(echo "$SKILL_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"
        rendered="$(printf '%s\n' "$self_improving_skill_markdown_template" \
            | perl -0pe '
                s/name: skill-name-here/name: '"$SKILL_NAME"'/g;
                s/skill-name-here/'"$SKILL_NAME"'/g;
                s/^# Skill Name$/# '"$title"'/m;
                s/LRN-YYYYMMDD-NNN/'"$LEARNING_ID"'/g;
                s/YYYY-MM-DD/'"$EXTRACTION_DATE"'/g;
            ')"
        printf '<!-- Generated from asset template: %s -->\n\n' "$TEMPLATE_FILE"
        printf '%s\n' "$rendered"
        printf '\n## Source Learning\n\n'
        printf 'This skill was extracted from a reusable learning.\n'
        printf -- '- Learning ID: %s\n' "$LEARNING_ID"
        printf -- '- Original File: %s\n' "$SOURCE_FILE"
        printf -- '- Skill Path: %s\n' "$SKILL_PATH"
    else
        cat <<EOF
---
name: $SKILL_NAME
description: "[TODO: Add a concise description of what this skill does and when to use it]"
---

# $(echo "$SKILL_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

[TODO: Brief introduction explaining the skill's purpose]

## Quick Reference

| Situation | Action |
|-----------|--------|
| [Trigger condition] | [What to do] |

## Usage

[TODO: Detailed usage instructions]

## Source Learning

This skill was extracted from a reusable learning.
- Learning ID: $LEARNING_ID
- Original File: $SOURCE_FILE
- Skill Path: $SKILL_PATH
EOF
    fi
}

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run - would create:"
    echo "  $SKILL_PATH/"
    echo "  $SKILL_PATH/SKILL.md"
    echo
    render_template
    exit 0
fi

if [[ -d "$SKILL_PATH" ]]; then
    echo "Skill already exists: $SKILL_PATH" >&2
    exit 1
fi

mkdir -p "$SKILL_PATH"
render_template > "$SKILL_PATH/SKILL.md"

echo "Created: $SKILL_PATH/SKILL.md"
echo "Next: customize the TODOs, then update the originating learning to Status: promoted_to_skill."
