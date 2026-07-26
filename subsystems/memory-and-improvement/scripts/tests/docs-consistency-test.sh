#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
README_EN="$SKILL_DIR/README.md"
README_ZH="$SKILL_DIR/README.zh-CN.md"
SKILL_MD="$SKILL_DIR/SKILL.md"
MAINTAINER_REF="$SKILL_DIR/references/maintainer-reference.md"
HOOKS_SETUP="$SKILL_DIR/references/hooks-setup.md"
TECHNICAL_EN="$SKILL_DIR/docs/TECHNICAL.md"
TECHNICAL_ZH="$SKILL_DIR/docs/TECHNICAL.zh-CN.md"

fail() {
    printf 'docs consistency check failed: %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
    [[ -d "$1" ]] || fail "missing directory: $1"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "missing pattern '$2' in $1"
}

assert_not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "unexpected pattern '$2' in $1"
    fi
}

assert_max_lines() {
    local actual
    actual="$(wc -l < "$1")"
    [[ "$actual" -le "$2" ]] ||
        fail "expected $1 to stay within $2 lines but found $actual"
}

for path in "$README_EN" "$README_ZH" "$SKILL_MD" "$MAINTAINER_REF" "$HOOKS_SETUP"; do
    assert_file "$path"
done

if [[ -d "$SKILL_DIR/docs" ]]; then
    assert_file "$TECHNICAL_EN"
    assert_file "$TECHNICAL_ZH"
    assert_contains "$README_EN" "docs/TECHNICAL.md"
    assert_contains "$README_ZH" "docs/TECHNICAL.zh-CN.md"
fi

# README is a user entry point, not the complete technical specification.
assert_max_lines "$README_EN" 180
assert_max_lines "$README_ZH" 180

english_sections=(
    "## Installation and use"
    "## How it works"
    "## What it stores"
    "## Maintenance"
    "## Limitations"
)
chinese_sections=(
    "## 安装与使用"
    "## 工作原理"
    "## 存储什么"
    "## 维护"
    "## 限制"
)
for section in "${english_sections[@]}"; do assert_contains "$README_EN" "$section"; done
for section in "${chinese_sections[@]}"; do assert_contains "$README_ZH" "$section"; done

# Human-facing routing and storage boundaries remain explicit.
for pattern in \
    "<project>/.learnings/" \
    "~/global-memory/namespaces/<name>/.learnings/" \
    ".learnings/assets/INDEX.md" \
    "assets/INDEX.md" \
    "Capture favors recall; promotion favors precision"; do
    assert_contains "$README_EN" "$pattern"
done
for pattern in \
    "<project>/.learnings/" \
    "~/global-memory/namespaces/<name>/.learnings/" \
    ".learnings/assets/INDEX.md" \
    "assets/INDEX.md" \
    "记录偏向高召回，升级偏向高精度"; do
    assert_contains "$README_ZH" "$pattern"
done

# README must describe the Hook-integrated runtime, not present the helpers as
# a separate command-line workflow.
for pattern in \
    "A Hook-integrated, Markdown-first memory runtime for Codex" \
    "not a standalone collection of shell commands" \
    "After installation, use Codex normally. No memory command needs to be run by" \
    "SessionStart" \
    "UserPromptSubmit" \
    "user-profile/SUMMARY.md" \
    "Active Codex session" \
    "Scheduled maintenance"; do
    assert_contains "$README_EN" "$pattern"
done
for pattern in \
    "配合 Codex Hook 运行" \
    "不是一组需要用户单独执行的 Shell 命令" \
    "日常工作不需要手动运行记忆脚本" \
    "SessionStart" \
    "UserPromptSubmit" \
    "user-profile/SUMMARY.md" \
    "当前 Codex 会话" \
    "维护计划任务"; do
    assert_contains "$README_ZH" "$pattern"
done

for group in hooks recall capture bootstrap maintenance shortcuts; do
    assert_dir "$SKILL_DIR/scripts/$group"
    assert_contains "$README_EN" "scripts/$group/"
    assert_contains "$README_ZH" "scripts/$group/"
done

# Detailed implementation inventory is linked instead of expanded inline.
assert_contains "$README_EN" "references/maintainer-reference.md"
assert_contains "$README_ZH" "references/maintainer-reference.md"
assert_contains "$README_EN" "references/hooks-setup.md"
assert_contains "$README_ZH" "references/hooks-setup.md"
assert_contains "$README_EN" "references/windows-maintenance.md"
assert_contains "$README_ZH" "references/windows-maintenance.md"

# Configuration is summarized without duplicating the full schema.
config_patterns=(
    "~/.codex/skills/memory-and-improvement/config.toml"
    "config/defaults.toml"
)
for pattern in "${config_patterns[@]}"; do
    assert_contains "$README_EN" "$pattern"
    assert_contains "$README_ZH" "$pattern"
done
assert_contains "$README_EN" "Manual script execution is intended for setup, verification, debugging,"
assert_contains "$README_ZH" "手动运行脚本只用于安装、验证、"

# Runtime docs must match the current reminder-first hook behavior and its
# narrow user-profile summary exception.
assert_contains "$SKILL_MD" "## Closed-Loop Runtime Contract"
assert_contains "$SKILL_MD" "## Runtime Routing Summary"
assert_contains "$SKILL_MD" "does not run general project/global recall or reflection itself"
assert_contains "$HOOKS_SETUP" "Recall -> Reason -> Respond/Act -> Reflect"
assert_contains "$HOOKS_SETUP" "do not run general project/global recall or reflection"
assert_contains "$HOOKS_SETUP" "user-profile/SUMMARY.md"
assert_not_contains "$README_EN" "auto-run a previous-turn reflect"
assert_not_contains "$README_ZH" "自动执行上一轮"
assert_not_contains "$HOOKS_SETUP" "auto-run a previous-turn reflect"

# Private machine paths never belong in reusable docs.
for path in "$README_EN" "$README_ZH" "$SKILL_MD" "$MAINTAINER_REF" "$HOOKS_SETUP"; do
    assert_not_contains "$path" "/home/zitai/"
done

printf 'docs consistency assertions passed\n'
