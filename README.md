# CodexKit Sync

An unofficial, local-first Windows toolkit for exporting, installing, checking,
and repairing a portable Codex working environment in OneDrive.

This is a community project. It is not affiliated with, sponsored by, or
endorsed by OpenAI. OpenAI, ChatGPT, and Codex are trademarks of their
respective owner. No OpenAI logos are distributed with this project.

## What it manages

- Codex and Agents skills
- portable hooks and global guidance
- optional linked global memory
- per-device environment inventories
- plugin inventory
- optional Codex projects and automations
- optional session and desktop-sidebar synchronization
- a managed ChatGPT launcher with controlled Pull/Push synchronization

Credentials, command-approval policy, caches, logs, and the Codex SQLite state
database are deliberately excluded.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or newer
- OneDrive
- Codex/ChatGPT desktop or Codex CLI
- Node.js for desktop-state and thread-catalog helpers

Git is not required for installation or normal use.

## Install from a release ZIP

1. Download the latest release ZIP and its `.sha256` file.
2. Verify the checksum.
3. Extract the ZIP.
4. Open PowerShell in the extracted directory.
5. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexKitSync.ps1 -Recommended
```

This installs the bundled `codexkit-sync` skill, exports a private CodexKit
under OneDrive, and applies the recommended links. It does not enable session
or desktop-state synchronization.

To export without installing links:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexKitSync.ps1
```

To use a different destination:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexKitSync.ps1 `
  -DestinationRoot "D:\OneDrive\CodexKit" -Recommended
```

## Private-data features

Session transcripts and desktop state may contain prompts, responses, local
paths, project names, and pasted secrets. They are disabled by default.

Enabling them requires both an explicit feature switch and acknowledgement:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexKitSync.ps1 `
  -IncludeSessions -IncludeDesktopState -AcceptPrivateDataRisk
```

Do not use the same synchronized conversation actively on two machines.

## Daily commands

From the private OneDrive CodexKit:

```powershell
.\Install-CodexKitForWindows.ps1 -Status
.\Install-CodexKitForWindows.ps1 -Repair
.\Switch-CodexMachine.cmd
```

Use the installed `ChatGPT` Start-menu shortcut for the managed Pull/start/Push
lifecycle.

## Safety model

- Existing targets are backed up before replacement.
- Conflicts stop before mutation.
- Important copies are verified with SHA-256.
- Desktop-state synchronization is fail-closed.
- `state_5.sqlite` is never copied or linked.
- Session synchronization is opt-in.
- The public release contains no exported user data.

Read [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and
[Uninstall](docs/UNINSTALL.md) before enabling optional state synchronization.

## Supported scope

The initial public release is intentionally Windows- and OneDrive-focused.
Codex internal storage can change between desktop releases; unsupported layouts
must fail with a diagnostic rather than being modified speculatively.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributors use Git, but end users do
not need it.

## License

MIT. See [LICENSE](LICENSE).

