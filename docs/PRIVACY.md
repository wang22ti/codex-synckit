# Privacy

## Public source versus private output

The public repository contains only program source, tests, and documentation.
The exporter creates a separate private CodexKit for each user.

Never publish the generated private directory.

## Data categories

Default exports include:

- user-installed skills
- portable hook definitions
- sanitized configuration snapshots
- global guidance
- global memory
- device environment inventory
- plugin inventory
- session transcripts and their title index
- desktop sidebar and project organization

Session transcripts can contain prompts, responses, file paths, source
fragments, pasted credentials, and other sensitive material.

## Deliberately excluded

- authentication files
- shell and Codex history
- machine command-approval rules
- caches and logs
- private keys and common credential files
- the Codex SQLite state database

Use `-ExcludeSessions` or `-ExcludeDesktopState` when those categories should
not be included. Exclusion is risk reduction, not a guarantee that other
free-form content contains no secret. Protect the OneDrive account and never
publish or share the generated private package without reviewing it.

## Telemetry

Codex SyncKit does not add telemetry or transmit analytics. OneDrive, Codex,
ChatGPT, PowerShell, Node.js, and the operating system remain governed by their
own policies.
