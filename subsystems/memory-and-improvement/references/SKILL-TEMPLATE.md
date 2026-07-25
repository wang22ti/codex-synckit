# Skill Template

Template for creating Codex skills extracted from reusable learnings.

---

## SKILL.md Template

```markdown
---
name: skill-name-here
description: "Concise description of when and why to use this skill. Include trigger conditions."
---

# Skill Name

Brief introduction explaining the problem this skill solves and its origin.

## Quick Reference

| Situation | Action |
|-----------|--------|
| [Trigger 1] | [Action 1] |
| [Trigger 2] | [Action 2] |

## Background

Why this knowledge matters. What problems it prevents. Context from the original learning.

## Solution

### Step-by-Step

1. First step with code or command
2. Second step
3. Verification step

### Code Example

\`\`\`language
// Example code demonstrating the solution
\`\`\`

## Common Variations

- **Variation A**: Description and how to handle
- **Variation B**: Description and how to handle

## Gotchas

- Warning or common mistake #1
- Warning or common mistake #2

## Related

- Link to related documentation
- Link to related skill

## Source

Extracted from learning entry.
- **Learning ID**: LRN-YYYYMMDD-NNN
- **Original Category**: correction | insight | knowledge_gap | best_practice
- **Extraction Date**: YYYY-MM-DD
- **Skill Path**: ~/.codex/skills/skill-name-here
```

---

## Minimal Template

For simple skills that do not need all sections:

```markdown
---
name: skill-name-here
description: "What this skill does and when to use it."
---

# Skill Name

[Problem statement in one sentence]

## Solution

[Direct solution with code or commands]

## Source

- Learning ID: LRN-YYYYMMDD-NNN
```

---

## Template with Scripts

For skills that include executable helpers:

```markdown
---
name: skill-name-here
description: "What this skill does and when to use it."
---

# Skill Name

[Introduction]

## Quick Reference

| Command | Purpose |
|---------|---------|
| `./scripts/helper.sh` | [What it does] |
| `./scripts/validate.sh` | [What it does] |

## Usage

### Automated

\`\`\`bash
~/.codex/skills/skill-name-here/scripts/helper.sh [args]
\`\`\`

### Manual Steps

1. Step one
2. Step two

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/helper.sh` | Main utility |
| `scripts/validate.sh` | Validation checker |

## Source

- Learning ID: LRN-YYYYMMDD-NNN
```

---

## Naming Conventions

- **Skill name**: lowercase, hyphens for spaces
  - Good: `docker-m1-fixes`, `api-timeout-patterns`
  - Bad: `Docker_M1_Fixes`, `APITimeoutPatterns`

- **Description**: start with an action verb and mention the trigger
  - Good: "Handles Docker build failures on Apple Silicon. Use when builds fail with platform mismatch."
  - Bad: "Docker stuff"

- **Files**:
  - `SKILL.md` - required
  - `scripts/` - optional
  - `references/` - optional
  - `assets/` - optional

---

## Extraction Checklist

Before creating a skill from a learning:

- [ ] Learning is verified or clearly reusable
- [ ] Solution is broadly applicable
- [ ] Content is complete
- [ ] Name follows conventions
- [ ] Description is concise but informative
- [ ] Source learning ID is recorded

After creating:

- [ ] Update original learning with `promoted_to_skill` status
- [ ] Add `Skill-Path: ~/.codex/skills/skill-name-here`
- [ ] Test the skill in a fresh Codex session
