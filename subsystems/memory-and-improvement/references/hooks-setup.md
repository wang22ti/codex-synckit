# Codex Hook Setup

Configure the minimal hook integration for the `memory-and-improvement` skill.

## Overview

Recommended default:

- `SessionStart`: tell the main session where project and global memory live, and how to load them
- after this skill is active, make an explicit recall decision before every reply; either perform the smallest relevant recall step first or make an internal safe-skip judgment
- after meaningful work, make an explicit reflect decision and run `reflect-memory.sh` before the final response when appropriate

Optional additions:

- `UserPromptSubmit`: emit a per-turn reminder to recall before replying and reflect before the final response

The hook layer should not decide what belongs in project memory vs global memory.
The hook layer should not decide recall routing, safe-skip justification, or what memory candidate should be logged.
That routing decision belongs to the main session, which should follow `SKILL.md` and call `log-memory.sh` directly when something is worth remembering.
The current setup injects the closed-loop contract on `SessionStart`; the main session remains responsible for Recall -> Reason -> Respond/Act -> Reflect, while `UserPromptSubmit` only reinforces that responsibility. For audit-sensitive `memory-and-improvement` work, the session should run an audit-focused subagent when runtime rules and user permission allow it, or explicitly note the unmet audit requirement.
For the dedicated summary-first recall helper during later turns, use `scripts/recall/recall-memory.sh`.
Its `auto` mode is only a lightweight scope heuristic after the main session has already decided recall is needed; it may resolve to `project`, `global`, or `both`, but it does not replace the main session's judgment about whether memory is relevant at all.
For meaningful turns that may need a structured post-task check, use `scripts/recall/reflect-memory.sh`.
The explicit judgment requirement belongs to the main session. The `UserPromptSubmit` hook does not run the advisory reflect helper automatically.
After the recall decision, the session should run a short reasoning checklist:

- what relevant memory did recall surface?
- if recall was skipped, why is that skip safe for this turn?
- is the current layer enough?
- if not, should the next step be `review-memory.sh`, `search-memory.sh`, a structured factual file, or raw `.learnings/*.md`?
- do repo conventions, prior failures, or the safe-skip judgment change the plan before edits begin?

Helper behavior reminder:

- `review-memory.sh` should stay summary/review-first by default and only expose raw entry previews when higher layers are absent or explicitly requested
- `search-memory.sh` should stop after the first layer with hits unless an explicit exhaustive search is requested

Execution boundary reminder:

- normal execution can proceed without an audit step when the task does not change `memory-and-improvement` workflow/docs/spec/roadmap/diagram behavior
- audit-aware execution should say so in commentary or planning language before edits begin, keep the audit step in scope, and explicitly note if runtime rules or user permission prevent subagent use

## Recommended Setup

Create or update `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "~/.codex/skills/memory-and-improvement/scripts/hooks/activator.sh"
          }
        ]
      }
    ]
  }
}
```

Optional `UserPromptSubmit` reminder:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "~/.codex/skills/memory-and-improvement/scripts/hooks/activator.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.codex/skills/memory-and-improvement/scripts/hooks/user-prompt-recall-reminder.sh"
          }
        ]
      }
    ]
  }
}
```

If your local hook config was created before the hook helper split, replace the old
`~/.codex/skills/memory-and-improvement/scripts/activator.sh` entry with
`~/.codex/skills/memory-and-improvement/scripts/hooks/activator.sh`.
If your Codex runtime does not expand `~` in hook commands, use the absolute path instead.

## Verification

### Test Activator Hook

1. Enable the `SessionStart` hook.
2. Start a new Codex session.
3. Verify you see the memory location, loading guide, the explicit recall-decision instruction, and the explicit reflect-decision instruction in hook context.

### Test UserPromptSubmit Hook

1. Enable the optional `UserPromptSubmit` hook.
2. Start or continue a Codex session.
3. Send a new prompt.
4. Verify you see a reminder to recall before replying and reflect before the final response, with no automatic `reflect-memory.sh` result injected by the hook.

## Troubleshooting

### Hook Not Triggering

1. Verify the absolute script path exists.
2. If `hooks.json` still points to `scripts/activator.sh`, update it to `scripts/hooks/activator.sh`.
3. Restart Codex after changing `hooks.json`.
4. Keep the setup minimal: `SessionStart` only.
5. If you add more hooks later, keep them narrow; do not move project-vs-global routing or final logging judgment into the hook layer.

### Permission Denied

```bash
chmod +x ~/.codex/skills/memory-and-improvement/scripts/hooks/activator.sh
chmod +x ~/.codex/skills/memory-and-improvement/scripts/capture/extract-skill.sh
chmod +x ~/.codex/skills/memory-and-improvement/scripts/bootstrap/init-memory.sh
chmod +x ~/.codex/skills/memory-and-improvement/scripts/recall/review-memory.sh
chmod +x ~/.codex/skills/memory-and-improvement/scripts/capture/log-memory.sh
chmod +x ~/.codex/skills/memory-and-improvement/scripts/maintenance/writeback-memory.sh
```

## Security Notes

- Hook scripts should only print memory locations and loading guidance.
- Hook scripts should only inject memory locations and operating guidance; they must not run reflection or decide project-vs-global routing and final logging actions.
- Do not log secrets, tokens, or raw private configs into `./.learnings/` or `~/global-memory/`.
