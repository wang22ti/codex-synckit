# Entry Examples

Concrete examples of well-formatted project and global entries.

## Project Fact or Convention

```markdown
## [LRN-20250115-001] correction

**Logged**: 2025-01-15T10:00:00Z
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
Repository keeps shared test fixtures in `tests/fixtures/`

### Details
I initially searched under `fixtures/` at repo root, but this repository
stores reusable fixtures under `tests/fixtures/`.

### Suggested Action
Check `tests/fixtures/` before creating new test data paths in this repository.

### Metadata
- Source: user_feedback
- Related Files: tests/fixtures/
- Tags: tests, fixtures, repo_convention
- Pattern-Key: repo.tests.fixtures
- Recurrence-Count: 1
- First-Seen: 2025-01-15
- Last-Seen: 2025-01-15

---
```

## Learning: Correction

```markdown
## [LRN-20250115-002] correction

**Logged**: 2025-01-15T10:30:00Z
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
Incorrectly assumed pytest fixtures are scoped to function by default

### Details
When writing test fixtures, I assumed all fixtures were function-scoped.
User corrected that while function scope is the default, this repository
uses module-scoped fixtures for database connections to improve performance.

### Suggested Action
When creating fixtures that involve expensive setup, check existing fixture
patterns before defaulting to function scope.

### Metadata
- Source: user_feedback
- Related Files: tests/conftest.py
- Tags: pytest, testing, fixtures

---
```

## Learning: Knowledge Gap (Resolved)

```markdown
## [LRN-20250115-003] knowledge_gap

**Logged**: 2025-01-15T14:22:00Z
**Priority**: medium
**Status**: resolved
**Area**: config

### Summary
Project uses pnpm not npm for package management

### Details
Attempted to run `npm install` but this repository uses pnpm workspaces.
Lock file is `pnpm-lock.yaml`, not `package-lock.json`.

### Suggested Action
Check for `pnpm-lock.yaml` or `pnpm-workspace.yaml` before assuming npm.
Use `pnpm install` for this repository.

### Metadata
- Source: error
- Related Files: pnpm-lock.yaml, pnpm-workspace.yaml
- Tags: package-manager, pnpm, setup

### Resolution
- **Resolved**: 2025-01-15T14:30:00Z
- **Commit/PR**: N/A - knowledge update
- **Notes**: Repository convention confirmed and remembered

---
```

## Global Fact or Preference

```markdown
## [LRN-20250115-004] correction

**Logged**: 2025-01-15T15:00:00Z
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
User prefers concise rebuttal drafts with explicit claim-evidence structure

### Details
This preference is not specific to one repository and should carry across
future research-writing tasks.

### Suggested Action
Store in `~/global-memory/namespaces/research-principle/.learnings/LEARNINGS.md` and
promote to `SUMMARY.md` if it keeps recurring.

### Metadata
- Source: user_feedback
- Related Files: none
- Tags: preference, writing, rebuttal
- Pattern-Key: research-principle.rebuttal.preference
- Recurrence-Count: 1
- First-Seen: 2025-01-15
- Last-Seen: 2025-01-15

---
```

## Learning: Promoted to SUMMARY.md

```markdown
## [LRN-20250115-005] best_practice

**Logged**: 2025-01-15T16:00:00Z
**Priority**: high
**Status**: promoted_to_summary
**Area**: backend

### Summary
API responses must include correlation ID from request headers

### Details
This is a cross-project API rule that should live in
`~/global-memory/namespaces/research-principle/SUMMARY.md`.

### Suggested Action
Promote the rule into the `research-principle` namespace summary for fast recall.

### Metadata
- Source: user_feedback
- Related Files: src/middleware/correlation.ts
- Tags: api, observability, tracing

---
```

## Learning: Promoted to Skill

```markdown
## [LRN-20250116-001] best_practice

**Logged**: 2025-01-16T09:00:00Z
**Priority**: high
**Status**: promoted_to_skill
**Area**: backend

### Summary
Must regenerate API client after OpenAPI spec changes

### Details
When modifying API endpoints, the TypeScript client must be regenerated.
Forgetting this causes type mismatches that only appear at runtime.

### Suggested Action
Extract a reusable API-change checklist skill that runs the codegen step
after endpoint changes.

### Metadata
- Source: error
- Related Files: openapi.yaml, src/client/api.ts
- Tags: api, codegen, typescript
- Skill-Path: ~/.codex/skills/api-change-checklist

---
```

## Error Entry

```markdown
## [ERR-20250115-001] docker_build

**Logged**: 2025-01-15T09:15:00Z
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
Docker build fails on Apple Silicon due to platform mismatch

### Error
```
error: failed to solve: python:3.11-slim: no match for platform linux/arm64
```

### Context
- Command: `docker build -t myapp .`
- Dockerfile uses `FROM python:3.11-slim`
- Running on Apple Silicon

### Suggested Fix
Add platform flag or update the Dockerfile to specify the expected platform.

### Metadata
- Reproducible: yes
- Related Files: Dockerfile
- Pattern-Key: infra.docker.platform-mismatch
- Recurrence-Count: 1
- First-Seen: 2025-01-15
- Last-Seen: 2025-01-15

---
```

## Feature Request

```markdown
## [FEAT-20250115-001] export_to_csv

**Logged**: 2025-01-15T16:45:00Z
**Priority**: medium
**Status**: pending
**Area**: backend

### Requested Capability
Export analysis results to CSV format

### User Context
User runs weekly reports and needs to share results with non-technical
stakeholders in Excel. Current workflow is manual.

### Complexity Estimate
simple

### Suggested Implementation
Add `--output csv` to the analyze command and reuse the existing JSON
output pattern.

### Metadata
- Frequency: recurring
- Related Features: analyze command, json output
- Pattern-Key: feature.export.csv
- Recurrence-Count: 1
- First-Seen: 2025-01-15
- Last-Seen: 2025-01-15

---
```
