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
4. Run `bash ./tools/Test-MemorySubsystem.sh`.
5. Test an export against a disposable destination.
6. Run `tools/Test-PublicRelease.ps1` and `tools/Build-Release.ps1`.
7. Update `CHANGELOG.md`.

Never use a real generated CodexKit as a pull-request fixture.

Maintainers publish a release by pushing a version tag such as
`v0.2.0-alpha`. The release workflow rebuilds and rescans the ZIP before
creating the GitHub Release; do not upload an independently assembled archive.

## Pull requests

Describe:

- the user-visible behavior
- data that may be read, written, linked, moved, or deleted
- rollback behavior
- tests performed
- compatibility assumptions about Codex internal state

Changes that weaken private-data exclusions, path validation, hash checks,
rollback, or fail-closed startup require explicit security review.

## Maintainer and acknowledgements

Codex SyncKit is maintained by the project maintainers.

The bundled `memory-and-improvement` subsystem uses and adapts portions of the
MIT-licensed
[`self-improvement`](https://github.com/pskoett/pskoett-ai-skills/tree/20e64cec1529d9c371fdcc20c751b7ef10b68af7/plugin/skills/self-improvement)
plugin by [Peter Skøtt Pedersen](https://github.com/pskoett). Its project-level
`.learnings` structure, learning/error/feature-request records, promotion
workflow, and skill-extraction pattern provided the starting point. Only this
MIT-licensed plugin copy was used as the upstream source.

This adaptation adds project-versus-global memory routing, cross-project
namespaces, recall and search, maintenance and writeback workflows, and
Codex/Windows synchronization integration. The upstream copyright and complete
MIT license are retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
