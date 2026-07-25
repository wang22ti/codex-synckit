#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LANDING_EN="$SKILL_DIR/README.md"
LANDING_ZH="$SKILL_DIR/README.zh-CN.md"
README_EN="$SKILL_DIR/TECHNICAL.md"
README_ZH="$SKILL_DIR/TECHNICAL.zh-CN.md"
SKILL_MD="$SKILL_DIR/SKILL.md"
MAINTAINER_REF="$SKILL_DIR/references/maintainer-reference.md"
HOOKS_SETUP="$SKILL_DIR/references/hooks-setup.md"
SCRIPTS_DIR="$SKILL_DIR/scripts"

fail() {
    printf 'docs consistency check failed: %s\n' "$1" >&2
    exit 1
}

assert_file() {
    local path="$1"

    [[ -f "$path" ]] || fail "missing file: $path"
}

assert_contains() {
    local path="$1"
    local pattern="$2"

    grep -Fq -- "$pattern" "$path" || fail "missing pattern '$pattern' in $path"
}

assert_any_contains() {
    local path="$1"
    shift
    local pattern

    for pattern in "$@"; do
        if grep -Fq -- "$pattern" "$path"; then
            return 0
        fi
    done

    fail "missing any expected pattern in $path: $*"
}

assert_not_contains() {
    local path="$1"
    local pattern="$2"

    if grep -Fq -- "$pattern" "$path"; then
        fail "unexpected pattern '$pattern' in $path"
    fi
}

assert_max_lines() {
    local path="$1"
    local max_lines="$2"
    local actual_lines=""

    actual_lines="$(wc -l < "$path")"
    [[ "$actual_lines" -le "$max_lines" ]] || fail "expected $path to stay within $max_lines lines but found $actual_lines"
}

assert_h2_sequence() {
    local path="$1"
    shift
    local actual=""
    local expected=""
    local heading=""

    actual="$(grep '^## ' "$path")"
    for heading in "$@"; do
        expected="${expected}${expected:+$'\n'}## $heading"
    done

    [[ "$actual" == "$expected" ]] || fail "unexpected H2 sequence in $path"
}

assert_file "$README_EN"
assert_file "$README_ZH"
assert_file "$LANDING_EN"
assert_file "$LANDING_ZH"
assert_file "$SKILL_MD"
assert_file "$MAINTAINER_REF"
assert_file "$HOOKS_SETUP"
assert_file "$SKILL_DIR/scripts/shared/memory-config.sh"
assert_file "$SKILL_DIR/config/defaults.toml"

# The landing READMEs stay concise and follow the main project structure.
assert_max_lines "$LANDING_EN" 200
assert_max_lines "$LANDING_ZH" 200
assert_contains "$LANDING_EN" "## Installation and use"
assert_contains "$LANDING_EN" "## How it works"
assert_contains "$LANDING_EN" "## What it remembers"
assert_contains "$LANDING_EN" "## Compared with other memory approaches"
assert_contains "$LANDING_EN" "## Limitations"
assert_contains "$LANDING_EN" "TECHNICAL.md"
assert_h2_sequence "$LANDING_EN" \
    "Installation and use" \
    "How it works" \
    "What it remembers" \
    "Compared with other memory approaches" \
    "Limitations"
assert_contains "$LANDING_ZH" "## 安装与使用"
assert_contains "$LANDING_ZH" "## 工作原理"
assert_contains "$LANDING_ZH" "## 记录什么"
assert_contains "$LANDING_ZH" "## 与其他记忆方式对比"
assert_contains "$LANDING_ZH" "## 限制"
assert_contains "$LANDING_ZH" "TECHNICAL.zh-CN.md"
assert_h2_sequence "$LANDING_ZH" \
    "安装与使用" \
    "工作原理" \
    "记录什么" \
    "与其他记忆方式对比" \
    "限制"

# Required technical sections stay present in the detailed references.
assert_contains "$README_EN" "## Why This Memory System"
assert_contains "$README_EN" "## Closed-Loop Runtime Model"
assert_contains "$README_EN" "## Maintainer Reference"
assert_contains "$README_EN" "## Anti-Overpromotion"
assert_contains "$README_EN" "## Global Configuration"
assert_contains "$README_ZH" "## 为什么要做成这样"
assert_contains "$README_ZH" "## 闭环运行模型"
assert_contains "$README_ZH" "## 维护参考入口"
assert_contains "$README_ZH" "## 不要过度升级"
assert_any_contains "$README_ZH" "## Global Configuration" "## 全局配置"
assert_contains "$SKILL_MD" "## Closed-Loop Runtime Contract"
assert_contains "$SKILL_MD" "## Runtime Routing Summary"
assert_contains "$MAINTAINER_REF" "## Closed-Loop Policy"

# Core runtime contract should remain documented without freezing exact prose.
assert_contains "$SKILL_MD" "Capture favors recall. Promotion favors precision."
assert_contains "$SKILL_MD" "make an explicit recall decision before every reply"
assert_contains "$SKILL_MD" "If recall was skipped, why is that skip safe for this turn?"
assert_contains "$SKILL_MD" "do not force user-visible \"no recall needed\" or \"no reflect needed\" filler"
assert_contains "$SKILL_MD" "run an audit-focused subagent"
assert_contains "$MAINTAINER_REF" "make an explicit recall decision before every reply"
assert_contains "$MAINTAINER_REF" "If recall was skipped, why is that skip safe for this turn?"
assert_contains "$MAINTAINER_REF" "do not force user-visible \"no recall needed\" filler"
assert_contains "$MAINTAINER_REF" "do not force a user-visible \"no reflect needed\" note"
assert_contains "$MAINTAINER_REF" "run an audit-focused subagent"
assert_contains "$HOOKS_SETUP" "Recall -> Reason -> Respond/Act -> Reflect"
assert_contains "$HOOKS_SETUP" "scripts/hooks/activator.sh"
assert_contains "$HOOKS_SETUP" "scripts/activator.sh"
assert_contains "$HOOKS_SETUP" "run an audit-focused subagent"
assert_not_contains "$SKILL_MD" "explicitly state why skipping recall is safe for this turn"
assert_not_contains "$SKILL_MD" "otherwise explicitly note that no durable candidate was found and why"
assert_not_contains "$README_EN" "explicitly state why the turn is trivial or self-contained enough to skip recall safely"
assert_not_contains "$README_EN" "explicitly state that no durable memory candidate was found and why"
assert_not_contains "$README_ZH" "这个跳过必须说清楚，不能静默略过"
assert_not_contains "$README_ZH" "明确说明这轮为什么还没有 durable memory candidate"
assert_not_contains "$HOOKS_SETUP" "explicitly state why skipping recall is safe"
assert_not_contains "$HOOKS_SETUP" "explicitly state why there is no durable candidate to log"

# Global-config docs should preserve the real contract, but wording can evolve.
assert_contains "$README_EN" "~/.codex/skills/memory-and-improvement/config.toml"
assert_contains "$README_EN" "memory-and-improvement/config/defaults.toml"
assert_contains "$README_EN" "1. CLI arguments"
assert_contains "$README_EN" "2. environment variables"
assert_contains "$README_EN" "3. global config file"
assert_contains "$README_EN" "4. built-in defaults"
assert_contains "$README_EN" "Unknown or misspelled keys fail loudly"
assert_contains "$README_EN" "state_root/logs"
assert_contains "$README_EN" "log_dir"
assert_contains "$README_EN" "global_root/namespaces"
assert_contains "$README_EN" "global_namespaces_root"
assert_contains "$README_EN" "nightly-maintenance.sh"
assert_contains "$README_EN" "interval-maintenance.sh"
assert_contains "$README_EN" "maintenance.scope"
assert_contains "$README_EN" "changing config later does not rewrite an existing crontab"
assert_contains "$README_EN" 'also refresh the live crontab with `bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --apply`'
assert_contains "$README_EN" '`SELF_IMPROVING_GLOBAL_MEMORY_DIR`'
assert_contains "$README_ZH" "~/.codex/skills/memory-and-improvement/config.toml"
assert_contains "$README_ZH" "memory-and-improvement/config/defaults.toml"
assert_contains "$README_ZH" "1. CLI arguments"
assert_contains "$README_ZH" "2. environment variables"
assert_contains "$README_ZH" "3. global config file"
assert_contains "$README_ZH" "4. built-in defaults"
assert_contains "$README_ZH" "未知 key 或拼错的 key 会直接报错"
assert_contains "$README_ZH" "state_root/logs"
assert_contains "$README_ZH" "log_dir"
assert_contains "$README_ZH" "global_root/namespaces"
assert_contains "$README_ZH" "global_namespaces_root"
assert_contains "$README_ZH" "nightly-maintenance.sh"
assert_contains "$README_ZH" "interval-maintenance.sh"
assert_contains "$README_ZH" "maintenance.scope"
assert_contains "$README_ZH" "不会自动改写已经安装好的 crontab"
assert_contains "$README_ZH" 'bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --apply'
assert_contains "$README_ZH" "SELF_IMPROVING_GLOBAL_MEMORY_DIR"

config_keys=(
    "global_root"
    "global_namespaces_root"
    "state_root"
    "log_dir"
    "codex_home"
    "codex_skills_dir"
    "global_namespace"
    "git_autocommit"
    "nightly_writeback"
    "skill_policy_writeback"
    "organize_min_recurrence"
    "interval_minutes"
)

for key_name in "${config_keys[@]}"; do
    assert_contains "$README_EN" "$key_name"
    assert_contains "$README_ZH" "$key_name"
done

# Human-facing docs should not regress to stale path guidance.
assert_not_contains "$README_EN" "/home/"
assert_not_contains "$README_ZH" "/home/"
assert_not_contains "$LANDING_EN" "/home/"
assert_not_contains "$LANDING_ZH" "/home/"
assert_not_contains "$SKILL_MD" "/home/"
assert_not_contains "$MAINTAINER_REF" "/home/"
assert_not_contains "$HOOKS_SETUP" "/home/"
assert_not_contains "$README_EN" "enforced automatically"
assert_not_contains "$README_ZH" "自动强制执行"
assert_not_contains "$SKILL_MD" "enforced automatically"
assert_not_contains "$HOOKS_SETUP" "enforced automatically"

# The canonical maintainer reference must be linked from both READMEs.
assert_contains "$README_EN" "references/maintainer-reference.md"
assert_contains "$README_ZH" "references/maintainer-reference.md"
assert_contains "$HOOKS_SETUP" "UserPromptSubmit"
assert_contains "$HOOKS_SETUP" "does not run the advisory reflect helper automatically"
assert_file "$SKILL_DIR/scripts/hooks/user-prompt-recall-reminder.sh"
assert_contains "$SKILL_DIR/scripts/hooks/user-prompt-recall-reminder.sh" "install-nightly-maintenance.sh --apply"
assert_contains "$MAINTAINER_REF" 'scripts/maintenance/install-nightly-maintenance.sh --apply'
assert_contains "$MAINTAINER_REF" 'scripts/maintenance/install-windows-maintenance.ps1 -Apply'
assert_contains "$README_EN" 'when changing nightly or interval defaults in `config/defaults.toml`, also refresh the live crontab with `bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --apply`'
assert_contains "$README_ZH" '改 `config/defaults.toml` 里的 nightly/interval 默认值时，要同时用 `bash ~/.codex/skills/memory-and-improvement/scripts/maintenance/install-nightly-maintenance.sh --apply` 刷新 live crontab'
assert_contains "$README_EN" ".learnings/assets/INDEX.md"
assert_contains "$README_EN" "assets/INDEX.md"
assert_contains "$README_ZH" ".learnings/assets/INDEX.md"
assert_contains "$README_ZH" "assets/INDEX.md"
assert_contains "$SKILL_MD" ".learnings/assets/INDEX.md"
assert_contains "$SKILL_MD" "assets/INDEX.md"
assert_contains "$MAINTAINER_REF" ".learnings/assets/INDEX.md"
assert_contains "$MAINTAINER_REF" "assets/INDEX.md"

# The grouped script taxonomy should stay explicit in both READMEs.
script_groups=(
    "scripts/bootstrap/"
    "scripts/capture/"
    "scripts/recall/"
    "scripts/maintenance/"
    "scripts/hooks/"
    "scripts/shared/"
    "scripts/shortcuts/"
    "scripts/tests/"
)

for group_name in "${script_groups[@]}"; do
    [[ -d "$SCRIPTS_DIR/${group_name#scripts/}" ]] || fail "missing directory: $SCRIPTS_DIR/${group_name#scripts/}"
    assert_contains "$README_EN" "$group_name"
    assert_contains "$README_ZH" "$group_name"
done

# Core scripts must exist and remain documented.
core_scripts=(
    "hooks/activator.sh"
    "bootstrap/init-memory.sh"
    "recall/recall-memory.sh"
    "recall/reflect-memory.sh"
    "recall/review-memory.sh"
    "capture/log-memory.sh"
    "recall/search-memory.sh"
    "maintenance/suggest-promotions.sh"
    "maintenance/update-skill-policy.sh"
    "capture/log-asset.sh"
    "maintenance/interval-maintenance.sh"
)

for script_name in "${core_scripts[@]}"; do
    assert_file "$SCRIPTS_DIR/$script_name"
    assert_contains "$README_EN" "scripts/$script_name"
    assert_contains "$README_ZH" "scripts/$script_name"
    assert_contains "$SKILL_MD" "scripts/$script_name"
    assert_not_contains "$SCRIPTS_DIR/$script_name" "/home/"
done

# Shared and hook-only helpers should remain documented in the human-facing READMEs.
helper_scripts=(
    "shared/memory-paths.sh"
    "shared/memory-entry-parser.awk"
    "hooks/hook-utils.sh"
)

for script_name in "${helper_scripts[@]}"; do
    assert_file "$SCRIPTS_DIR/$script_name"
    assert_contains "$README_EN" "scripts/$script_name"
    assert_contains "$README_ZH" "scripts/$script_name"
    assert_not_contains "$SCRIPTS_DIR/$script_name" "/home/"
done

# The consistency check itself should stay documented as a drift detector.
assert_contains "$README_EN" "scripts/tests/docs-consistency-test.sh"
assert_contains "$README_ZH" "scripts/tests/docs-consistency-test.sh"

# Existing scripts and shortcut layout should remain documented and present.
[[ -d "$SCRIPTS_DIR/shortcuts" ]] || fail "missing directory: $SCRIPTS_DIR/shortcuts"
shortcut_scripts=(
    "remember-project-fact.sh"
    "remember-global-fact.sh"
    "remember-error.sh"
    "index-factual-file.sh"
    "index-asset.sh"
)
for script_name in "${shortcut_scripts[@]}"; do
    assert_file "$SCRIPTS_DIR/shortcuts/$script_name"
    assert_contains "$README_EN" "scripts/shortcuts/$script_name"
    assert_contains "$README_ZH" "scripts/shortcuts/$script_name"
    assert_contains "$SKILL_MD" "scripts/shortcuts/$script_name"
    assert_not_contains "$SCRIPTS_DIR/shortcuts/$script_name" "/home/"
done
assert_file "$SKILL_DIR/scripts/tests/shortcuts-smoke-test.sh"
assert_contains "$README_EN" "scripts/tests/shortcuts-smoke-test.sh"
assert_contains "$README_ZH" "scripts/tests/shortcuts-smoke-test.sh"
assert_file "$SKILL_DIR/scripts/tests/install-nightly-maintenance-test.sh"
assert_file "$SKILL_DIR/scripts/tests/interval-maintenance-test.sh"
assert_file "$SKILL_DIR/scripts/tests/windows-maintenance-test.ps1"
assert_file "$SKILL_DIR/scripts/tests/memory-config-test.sh"
assert_file "$SCRIPTS_DIR/maintenance/install-windows-maintenance.ps1"
assert_file "$SCRIPTS_DIR/maintenance/run-windows-maintenance.ps1"
assert_file "$SCRIPTS_DIR/maintenance/run-windows-maintenance-hidden.vbs"
assert_file "$SCRIPTS_DIR/maintenance/resolve-maintenance-settings.sh"
assert_file "$SCRIPTS_DIR/shared/file-lock.sh"
assert_contains "$README_EN" "scripts/maintenance/install-windows-maintenance.ps1"
assert_contains "$README_ZH" "scripts/maintenance/install-windows-maintenance.ps1"
assert_contains "$SKILL_MD" "scripts/maintenance/install-windows-maintenance.ps1"
assert_contains "$SKILL_MD" "scripts/shared/file-lock.sh"
assert_contains "$README_EN" "references/windows-maintenance.md"
assert_contains "$README_ZH" "references/windows-maintenance.md"

assert_file "$SCRIPTS_DIR/maintenance/suggest-promotions.sh"
assert_contains "$README_EN" "scripts/maintenance/suggest-promotions.sh"
assert_contains "$README_ZH" "scripts/maintenance/suggest-promotions.sh"
assert_contains "$SKILL_MD" "scripts/maintenance/suggest-promotions.sh"
assert_file "$SKILL_DIR/scripts/tests/suggest-promotions-test.sh"
assert_contains "$README_EN" "scripts/tests/suggest-promotions-test.sh"
assert_contains "$README_ZH" "scripts/tests/suggest-promotions-test.sh"

assert_file "$SKILL_DIR/scripts/tests/recall-memory-test.sh"
assert_contains "$README_EN" "scripts/tests/recall-memory-test.sh"
assert_contains "$README_ZH" "scripts/tests/recall-memory-test.sh"

assert_file "$SKILL_DIR/scripts/tests/reflect-memory-test.sh"
assert_contains "$README_EN" "scripts/tests/reflect-memory-test.sh"
assert_contains "$README_ZH" "scripts/tests/reflect-memory-test.sh"

assert_file "$SKILL_DIR/scripts/tests/writeback-memory-test.sh"
assert_contains "$README_EN" "scripts/tests/writeback-memory-test.sh"
assert_contains "$README_ZH" "scripts/tests/writeback-memory-test.sh"

assert_file "$SKILL_DIR/scripts/tests/update-skill-policy-test.sh"
assert_contains "$README_EN" "scripts/tests/update-skill-policy-test.sh"
assert_contains "$README_ZH" "scripts/tests/update-skill-policy-test.sh"

assert_file "$SKILL_DIR/scripts/tests/nightly-maintenance-test.sh"
assert_contains "$README_EN" "scripts/tests/nightly-maintenance-test.sh"
assert_contains "$README_ZH" "scripts/tests/nightly-maintenance-test.sh"

assert_file "$SKILL_DIR/scripts/tests/log-memory-test.sh"
assert_contains "$README_EN" "scripts/tests/log-memory-test.sh"
assert_contains "$README_ZH" "scripts/tests/log-memory-test.sh"

printf 'docs consistency assertions passed\n'
