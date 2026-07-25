# Maintainer Reference

This document is the compact canonical maintainer reference for the `memory-and-improvement` skill.

Use it for stable policy and architecture guidance that should stay synchronized across docs and scripts without bloating routine `SKILL.md` loads.

## Scope

This reference is for:

- closed-loop runtime policy
- routing boundaries
- progressive loading policy
- promotion rules
- asset policy
- anti-overpromotion guidance

This reference is not the runtime prompt for the skill. `SKILL.md` should stay focused on live operational behavior.

Stable policy docs and templates should live under `references/`. Exported diagram/image assets and their editable sources may live under `assets/`.
Within this system, project memory assets live in `.learnings/assets/INDEX.md`, while global namespace assets live in `assets/INDEX.md`.

## Closed-Loop Policy

Use the skill as a four-stage loop:

1. Recall
2. Reason
3. Respond/Act
4. Reflect

Stable policy for each stage:

- Recall: every turn begins with an explicit recall decision; non-trivial turns should start from the smallest relevant memory layer, while trivial turns may skip only with an explicit safe-skip judgment that need not be surfaced to the user unless it changes the visible response
- Reason: the main session explicitly decides whether the current layer is enough or whether deeper recall is needed
- Respond/Act: execution must honor recalled constraints, safe-skip judgments, and repo-specific conventions
- Reflect: substantial turns end with an explicit reflect decision about whether anything should be captured, kept raw, promoted later, or extracted into a skill; a no-op judgment may stay internal unless it changes what the user should be told

For this repository, `memory-and-improvement` workflow/docs/spec/roadmap/diagram work is audit-sensitive. When runtime rules and user permission allow it, the repo convention is to run an audit-focused subagent before the task is treated as complete or before moving to the next phase. If that cannot happen, the session should state the gap explicitly rather than silently weakening the rule.

## Routing Boundaries

Use this order:

1. Is the main value a reusable procedure?
2. If not, would this still help in a different repository next week?

Capture favors recall. Promotion favors precision.

Route accordingly:

- reusable procedure -> Codex skill under `~/.codex/skills/`
- cross-project durable fact, preference, history, or lesson -> global memory
- repo-specific fact, convention, failure, or request -> project memory

Raw `.learnings/*.md` is the permissive capture layer. If something seems worth recording, it is usually acceptable to capture it there first and decide about promotion later.

Important boundary:

- project memory stores repo facts and distilled lessons
- repo-local agent instructions and routing policy belong in `AGENTS.md` or explicit repo config
- global memory may include cross-project initialization context that should be recalled early

## Progressive Loading Policy

After this skill is active, make an explicit recall decision before every reply. Trivial chat may skip only when the main session explicitly judges the skip safe, and non-trivial turns should treat recall as mandatory policy. Keep the judgment explicit in the main session, but do not force user-visible "no recall needed" filler when the decision has no downstream effect.

Default read order:

1. `INIT.md` when early cross-project orientation is needed
2. `SUMMARY.md` for the shortest loading layer
3. structured factual files for compact durable facts
4. `REVIEW.md` for a concise operational snapshot
5. raw `.learnings/*.md` only when chronology, evidence, or corrections matter
6. the relevant asset index before concrete artifact files
7. concrete asset files only when the artifact itself is needed

Loading guardrails:

- before every reply, make an explicit recall decision and check the smallest relevant memory layer first unless a trivial turn has an explicit safe-skip judgment
- after recall, explicitly decide whether the current layer is enough before acting
- if recall was skipped, explicitly decide why the skip is safe for this turn, but only surface that reasoning when it affects the answer, plan, audit status, or logging outcome
- skip global memory when the task is repo-local, casual, creative, or otherwise does not depend on cross-project facts
- if nothing relevant appears at higher layers, answer without forcing deeper reads
- keep `review-memory.sh` summary/review-first by default; only fall back to raw entry previews when higher layers are absent or explicitly requested
- keep `search-memory.sh` staged by default; stop after the first layer with hits unless an explicit exhaustive search is requested
- do not open raw `.learnings/*.md` until higher layers are insufficient
- do not preload assets eagerly
- after substantial work, do a short reflect step before ending the turn, but do not force a user-visible "no reflect needed" note when the reflect judgment is a no-op

Reason escalation checklist:

1. What relevant memory, if any, did recall surface?
2. If recall was skipped, why is that skip safe for this turn?
3. Is the current layer sufficient to answer or act safely?
4. If not, which deeper source is the right next step?
5. Do repo conventions, prior failures, the safe-skip judgment, or audit requirements change the plan before edits begin?

Reason escalation rules:

- summary hit and sufficient -> proceed
- summary hit but underspecified -> open `review-memory.sh` or a structured factual file
- no summary hit but clear history dependence -> use `search-memory.sh`
- chronology, evidence, debugging context, or exact correction history needed -> open raw `.learnings/*.md`
- for `memory-and-improvement` workflow/spec/docs/diagram work, include the repo's audit convention in the plan before acting

Execution boundary:

- normal execution:
  - answers, searches, recall/review/logging flows
  - repo work that does not change `memory-and-improvement` workflow/docs/spec/roadmap/diagram behavior
- audit-aware execution:
  - substantial `memory-and-improvement` workflow/docs/spec/roadmap/diagram changes
  - work that changes runtime guidance, maintainer policy, or completion criteria

Audit-aware execution rules:

- surface the audit-sensitive status in commentary or planning language before edits begin
- keep an audit step in scope before treating the task as complete or moving to the next phase
- if subagent use is blocked by runtime rules or missing user permission, state the unmet audit requirement explicitly
- the main session remains the final decision maker even when the audit step runs

## Promotion Rules

Use `.learnings/*.md` for:

- raw capture
- corrections
- chronology
- debugging evidence
- tentative or disputed items
- any other event, observation, correction, or decision that seems worth recording

Use `SUMMARY.md` for:

- short high-frequency loading hints
- pointers to deeper factual files
- the smallest layer that should be read early

Use structured factual files for:

- stable factual snapshots
- information likely to be loaded repeatedly
- compact normalized facts that benefit from lightweight structure

Create or extend a structured factual file only when all of the following are true:

- the content is primarily factual rather than procedural
- the facts are stable across future sessions
- the facts are likely to be loaded repeatedly
- the content benefits more from normalization than from chronology

Use a skill instead when:

- the main value is a reusable method
- the content is step-by-step operational guidance
- repeatable execution matters more than factual recall

Default promotion flow:

1. log the raw fact or correction in `.learnings/*.md`
2. promote to a structured factual file only after the item is clearly stable or repeatedly needed
3. keep `SUMMARY.md` short and let it point to the factual file when appropriate
4. keep promotion selective even when capture is permissive
5. treat `suggest-promotions.sh`, `SUMMARY_CANDIDATES.md`, and `writeback-memory.sh` as a supportive promotion pipeline, not as permission to bypass review with raw recurrence alone

## Asset Policy

Assets are for durable artifacts that should be rediscoverable by path.

Index an asset when:

- the file itself is worth reopening, citing, or attaching later
- path-based rediscovery is useful
- the artifact is more than just supporting context inside a single entry

Typical asset examples:

- paper PDFs
- report PDFs
- screenshots
- figure sources
- dataset snapshots
- structured factual files that are themselves worth reopening directly

Asset rules:

- the discovery layer is the asset index: project memory uses `.learnings/assets/INDEX.md`, while global namespaces use `assets/INDEX.md`
- concrete files are opened only after the index says they are relevant
- structured factual files may also be indexed as assets when the file itself has standalone retrieval value

## Anti-Overpromotion Guidance

Most items should stay in raw history.

Do not treat `.learnings/*.md` as a temporary holding pen that everything must graduate out of.
Non-promotion is normal, not a sign that the system is incomplete.

Promote only when there is a clear payoff:

- the item is durable
- the item is repeatedly useful
- higher-layer loading would noticeably improve future sessions

Keep items raw when:

- chronology is part of the value
- the evidence trail matters
- the item is still local, tentative, or likely to change
- promotion would add maintenance cost without improving recall much
- nightly maintenance can help surface or distill candidates, but it should not erase the distinction between capture and promotion

Index assets only when the file itself is worth rediscovering. Do not index every file just because it exists.

## Maintenance Intent

When documentation needs to be synchronized:

- put the stable rule here first
- keep `README.md` and `README.zh-CN.md` as human-readable summaries
- keep `SKILL.md` focused on the behavior the agent needs during execution

Maintenance rule for installed automation:

- on Linux/macOS, update the live cron entry by re-running `scripts/maintenance/install-nightly-maintenance.sh --apply`
- on Windows, update the live scheduled task by re-running `scripts/maintenance/install-windows-maintenance.ps1 -Apply`
- changing defaults alone is not enough because installed scheduler entries freeze the effective schedule and command

If there is a conflict between a long explanatory section elsewhere and this file, update the other document to match this reference unless the runtime behavior has intentionally changed.
