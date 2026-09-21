# OneDrive small-file prevention

Use this workflow when installing/repairing a Kit or diagnosing stalled sync.

## Sources and boundaries

Codex can install Node dependencies, create Python environments/bytecode, run
web builds and tests, render document previews, and generate diagnostic trees.
A junction inside OneDrive pointing at an external dependency cache can expose
thousands of files to OneDrive. Keeping the target outside OneDrive alone does
not make that junction safe. Ordinary applications and Git also generate many
small files; file counts do not establish which application created them.

`scripts/OneDriveExcludedFolders.json` is the single list shared by the machine
policy, workspace Pull/Push, and reusable-package export. It covers Node
dependencies, `.venv`, Python bytecode/test/type/lint caches, npm/pnpm caches,
Next/Nuxt/Parcel/Turbo generated directories, and reserved `.codex-local` scratch.
Keep dependency manifests and lockfiles synchronized so each machine can
reinstall dependencies. Do not put authored files in these excluded directories.

Do not globally exclude `.git`, `.codex`, `.learnings`, `sessions`, `tmp`, `temp`,
`build`, `dist`, `output`, `assets`, or `logs`. These names may contain unpushed
history, conversation continuity, audit records, or requested deliverables.
Inspect custom dependency directories such as `runtime_deps` individually;
their name alone is insufficient to change synchronization. Never infer that
all files under `tmp` can be discarded. The package exporter has additional
scope-specific exclusions; do not promote those to machine-wide policy.

For new disposable work use `%LOCALAPPDATA%\CodexKit\scratch\<task-id>` or
`%TEMP%`, or `.codex-local` after verifying the policy on the current machine.
Keep package/browser/model/plugin caches, local SQLite/WAL databases, debug
logs, extracted SDK schemas, and disposable rendering frames outside OneDrive.
Copy final artifacts and required source assets back to the project. Prefer an
external working directory or explicit runtime import path over creating a
junction/symlink inside OneDrive. Existing authored project layouts must be
inspected before moving anything. Standard Codex caches under `.codex` and
`.cache` in the local profile already lie outside OneDrive; do not relocate them
into the Kit or blanket-exclude the profile's conversation links.

## Installation and verification

`Install-CodexKitForWindows.ps1 -Recommended` and `-Repair` apply the policy,
preserving custom entries and backing up previous registry values/types under
`%LOCALAPPDATA%\CodexKit\onedrive-policy-backups`. Missing entries require Windows
UAC once per machine. Only the policy helper elevates; OneDrive restarts in the
original non-elevated session after a change. Unsupported clients or declined
UAC produce a warning; dependency filtering in controlled workspace sync remains
active. `-SkipOneDriveExclusions` explicitly skips machine-policy changes for
isolated installer tests or deliberate opt-out. `-Status` only reads policy.

The Managed launcher's normal `-Repair` step applies new rules on other machines
after OneDrive has downloaded the updated Kit. A direct desktop launch that
bypasses Managed does not install policy. Run `-Repair` explicitly in that case.
When already configured, no UAC or restart occurs.

Standalone apply/check:

```powershell
& '<skill>\scripts\Set-OneDriveFolderExclusions.ps1' -Apply -Elevate -RestartOneDrive
& '<skill>\scripts\Set-OneDriveFolderExclusions.ps1'
```

Policy: `HKLM\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreFolderListFromGPO`.
It matches complete folder names case-insensitively across the machine, without
wildcards. It prevents new matching folders and new files inside existing
matching folders from being uploaded. It does not purge previously synchronized
cloud content or guarantee that an existing upload/download queue clears.
Do not promise retroactive exclusion. Any cleanup/migration of existing cloud
content needs a separate exact-path plan that preserves the local dependency
target, source files, and other machines' copies.

Workspace sync prunes excluded folders before traversal/hashing, skips actual
directory/file links, and filters old baselines as well as both file maps so a
new exclusion cannot be interpreted as a user deletion. OneDrive cloud
placeholders are not automatically links: use `LinkType`, not the generic
`ReparsePoint` flag. Previously copied excluded data is left intact.

## Diagnose remaining stalls

Use read-only OneDrive metadata or a bounded filesystem inventory; avoid
hydrating every online-only file. Count outermost dependency trees once, then
inspect real links and their targets. Correlate recent transfer/log activity
with changing queue state; distinguish dependency churn from large-file
transfers, locked/open files, invalid names/paths, conflict copies, network or
account errors, quota exhaustion, and disk space. Do not decode undocumented
status numbers into confident diagnoses. Avoid editing OneDrive databases.

Official references:
- [Folder exclusion policy](https://learn.microsoft.com/en-us/sharepoint/use-group-policy#exclude-specific-kinds-of-folders-from-being-uploaded)
- [OneDrive restrictions, including junctions and symbolic links](https://support.microsoft.com/en-us/onedrive/restrictions-and-limitations-in-onedrive-and-sharepoint)

Regression checks: workspace tests must cover excluded folders, case matching,
old-baseline retention, link targets, and preservation of `tmp`, `.git`, source,
and final artifacts. Validate generated installer status on a fake profile;
never elevate fixture tests or alter the live machine policy from tests.

Registry regression: Windows PowerShell 5.1 `New-Item -Force` on an existing
registry key clears its values. Create the key only when absent, then add
missing values. `scripts/tests/OneDriveFolderPolicy.test.ps1` uses a disposable
HKCU key to verify preservation of existing names/types, name collisions, and
idempotency without touching OneDrive policy. A failed read-back after UAC is
an installation failure, not evidence that the user declined authorization.
