# Contributing

## Development requirements

- Windows PowerShell 5.1
- Node.js
- a disposable test directory

Git is used by contributors only. It is not an end-user requirement.

## Workflow

1. Change the canonical exporter under `skill/scripts/Export-CodexKit.ps1`.
2. Parse every PowerShell file with the PowerShell language parser.
3. Run the Node and PowerShell regression tests.
4. Test an export against a disposable destination.
5. Run `tools/Test-PublicRelease.ps1`.
6. Update `CHANGELOG.md`.

Never use a real generated CodexKit as a pull-request fixture.

## Pull requests

Describe:

- the user-visible behavior
- data that may be read, written, linked, moved, or deleted
- rollback behavior
- tests performed
- compatibility assumptions about Codex internal state

Changes that weaken private-data exclusions, path validation, hash checks,
rollback, or fail-closed startup require explicit security review.

