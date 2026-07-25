# Security Policy

## Supported versions

Security fixes are applied to the latest published release. Pre-release builds
are provided for evaluation and may change without compatibility guarantees.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose credentials,
conversation contents, private paths, or permit unintended command execution.
Use GitHub's private vulnerability reporting feature for the repository.

Include:

- affected release
- Windows and PowerShell versions
- Codex/ChatGPT desktop or CLI version
- minimal reproduction without private session data
- expected and observed safety boundary

## Privileged operations

CodexKit Sync can:

- create directory links or junctions
- install hook definitions and hook scripts
- update a Start-menu shortcut
- optionally create or remove a scheduled task
- migrate selected local directories after preflight verification

Review scripts before running them. `-Recommended` deliberately excludes
sessions, desktop state, automations, profiles, and the maintenance task.

## Secrets and private data

Never publish a generated CodexKit. Generated packages can contain global
memory, project metadata, device inventories, hook paths, automation memory,
and—when explicitly enabled—complete session transcripts.

The public source release is built from an allowlist and is checked for:

- forbidden private-data directories
- user-profile paths
- common credential formats
- private-key headers
- unexpected top-level files

GitHub secret scanning is a second line of defense, not a substitute for the
local release gate.

## Supply chain

Release archives are accompanied by SHA-256 checksum files. This project does
not bundle Node.js, PowerShell, OneDrive, Codex, or ChatGPT binaries.

