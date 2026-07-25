---
name: codexkit-sync
description: Export, rebuild, install, and verify a portable Windows CodexKit in OneDrive. Use when the user asks to sync Codex skills, MiniMax skills, hooks, profiles, per-device environment inventories, global memory, Codex automations, plugin inventory, or the memory-maintenance scheduled task across Windows machines; manage the Export-CodexKit PowerShell script; install CodexKit with junctions; clean old CodexKit backups; or explicitly export sessions.
---

# CodexKit Sync

Use the bundled `scripts/Export-CodexKit.ps1` as the canonical exporter.

## Defaults

- Default destination: `%USERPROFILE%\OneDrive\CodexKit`.
- Export Codex skills to `skills\codex-skills`.
- Export MiniMax skills to `skills\minimax-skills`.
- Export Agents skills to `skills\agents-skills`.
- Include hooks, sanitized profiles, per-device environment inventories, global memory, plugin inventory, and memory-task settings.
- Exclude credentials, logs, caches, machine approval rules, and sessions.
- Never add `-IncludeSessions` unless the user explicitly requests session export after being warned about privacy and concurrent-write conflicts.

## Export Or Rebuild

Run with Windows PowerShell 5.1 and bypass only for this script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Export-CodexKit.ps1" -Force
```

For a clean rebuild:

1. Resolve and verify the OneDrive root.
2. Restrict deletion to the exact `CodexKit` directory and explicitly named `CodexKit-backup-*` directories.
3. Delete only after the user explicitly requests cleanup or replacement.
4. Run the exporter without `-IncludeSessions`.
5. Verify `manifest.json`, warnings, skill buckets, global memory, and scheduled-task files.

## Install On Windows

For the normal setup, use the unified recommended mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -Recommended
```

`-Recommended` installs the three skill links, global guidance links, hooks, linked global memory, captures the current device environment inventory, and installs a CodexKit-managed ChatGPT Start menu shortcut. It deliberately excludes profiles, Codex configuration, sessions, Codex automations, and the memory-maintenance scheduled task. Model, reasoning, feature, and other Codex preferences are selected locally on each machine. `environment\devices\<computer>.json` is a comparison snapshot, not an application or WSL migration mechanism.

The user-visible shortcut name is always `ChatGPT`, and every machine launches `Start-CodexManaged.vbs`. There are no Resident/Synced machine roles. `-InstallResidentStartMenuShortcut` remains accepted only for command-line compatibility and installs the same Managed shortcut. The memory-maintenance task may still belong to one designated automation host, but that does not change its launcher behavior. `-Repair` converts legacy launcher targets to Managed while refreshing the current Appx icon. Legacy `Codex.lnk` and older mode-labeled shortcuts are removed only when their arguments point to this KitRoot's launchers.

Install the memory-maintenance task only on the single designated maintenance host by explicitly adding `-InstallMemoryTask`. On other machines, remove an accidentally installed task with `-RemoveMemoryTask`.

Do not add `-InstallSessionLinks` by default.

The optional default-project redirect uses `CodexKit\CodexProjects` as the
OneDrive-backed source and the current Windows Documents folder's `Codex`
directory as the link target:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -InstallCodexProjectsLink
```

If `Documents\Codex` already contains projects, fully close ChatGPT and add
`-MigrateExistingCodexProjects`. When `CodexKit\CodexProjects` is empty, the
installer copies and verifies the complete local tree. When both sides contain
files, it performs a preflight union: identical relative files are deduplicated,
local-only files are added and verified by SHA-256, and the original local
directory is retained as a timestamped rollback backup. A same-path
content/type conflict stops before mutation and writes a device-local conflict
report under `.local\state\codexkit`. Preserve an existing OneDrive shared root
directory and copy children into it; Windows PowerShell 5.1 exposes OneDrive
cloud placeholders as reparse points, so detect real junctions/symlinks by
non-empty `LinkType`, not by the `ReparsePoint` attribute alone.

The optional automation redirect uses `CodexKit\automations` as the shared
source and `%USERPROFILE%\.codex\automations` as the link target. It is not part
of `-Recommended`. Fully close ChatGPT, then migrate each machine's existing
local automations:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -InstallAutomationsLink -MigrateExistingAutomations
```

The merge uses the same preflight, SHA-256 verification, backup, and rollback
rules as project migration. Same-path `automation.toml` or `memory.md`
differences are conflicts. If the shared tree already has `.run-jitter-salt`,
the local salt is ignored and remains only in the rollback backup. Never link
or copy `.codex\state_5.sqlite`. Once enabled, `-Repair` preserves the automation
link. Only one machine should run Managed ChatGPT at a time to avoid duplicate
execution of a shared schedule.

Codex automations do not replace the Windows memory-maintenance task. Keep that
Task Scheduler job installed on only the currently designated maintenance
machine, because the memory files themselves already synchronize through
OneDrive.

The installer first moves existing targets to timestamped backups. Backup retention is applied only after the replacement succeeds; if link creation or copying fails, the original target is restored automatically. Directory symlinks may fail without Developer Mode or elevation; junction fallback is expected and valid.

`-InstallHooks` installs a BOM-free `hooks.json`, copies the referenced scripts into `.codex\bin`, validates those script paths and PowerShell syntax, and ensures `[features] hooks = true` in `.codex\config.toml`.

Installation checks do not establish Codex trust. Non-managed command hooks are skipped until the exact definitions are trusted on that machine. Open the Codex CLI, run `/hooks`, trust both definitions, then fully restart the desktop app. Trust hashes remain device-local and must not be copied from another machine.

If `codex` is not on `PATH`, rerun the installer with `-InstallHooks -OpenHooksTrust`. It locates the CLI bundled with the Codex desktop app and opens it directly. Install the standalone CLI only if no bundled executable can be found.

On current Windows builds, prefer the runnable extracted CLI under `%LOCALAPPDATA%\OpenAI\Codex\bin\<build>\codex.exe`. A `Get-Command codex.exe` result inside `%ProgramFiles%\WindowsApps` may be visible but denied when executed directly, so use it only as a later fallback.

The generated installer immediately merges
`%USERPROFILE%\.local\state\memory-and-improvement\project-memory-registry.txt`
into `CodexKit\memory-system\project-memory-registry.tsv`. Existing shared rows are retained, local rows receive the current computer name, and OneDrive rows remain device-neutral.

`-InstallGlobalMemoryLink` backs up the existing local global-memory tree and links `%USERPROFILE%\global-memory` to `CodexKit\global-memory`. Changes then synchronize through OneDrive automatically. Avoid editing the same file on two machines simultaneously.

`-InstallGlobalMemory` remains available for one-time snapshot installation. Do not combine it with `-InstallGlobalMemoryLink`.

When global memory is linked, the installer disables maintenance Git commits so `.git` metadata does not synchronize across machines. OneDrive supplies file synchronization and version history.

`-InstallGlobalGuidanceLinks` links `.codex\AGENTS.md` and `.codex\AGENTS.override.md` to `CodexKit\rules\global`, so global guidance updates synchronize automatically. `.codex\rules` remains device-local because it stores machine command approval policy.

Device-local memory state is deliberately not synchronized: maintenance logs, interval timestamps, hook reflect markers, removed-project archives, Task Scheduler instances, and Git metadata. Project `.learnings` outside OneDrive also remain local.

The shared registry minimizes writes and can recover valid rows from OneDrive conflict-copy TSV files, but two machines should still avoid registering or unregistering projects at exactly the same time.

## Verification

Run the read-only health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -Status
```

`-Status` must not modify files or merge registries. It reports links, guidance, hooks, the latest real hook marker, the scheduled task, the shared project-memory registry, and plugins missing from the local machine compared with `plugins\inventory.json`. It also verifies the SHA-256 hashes and generation time recorded in `manifest.json` for the installer, README, managed launchers, skill-source inventory, and the complete `codexkit-sync` skill. Manifest drift is reported as `[STALE]` with changed, untracked, and missing counts; it requires a fresh export, not `-Repair`.

Plugin status compares `marketplace/plugin` presence, not exact cached versions. Codex desktop updates bundled plugin versions independently. Missing plugins are reported for local installation or account connection; plugin caches are never linked through OneDrive.

When the cache contains both `marketplace/plugin` and its renamed `marketplace-remote/plugin` counterpart, export only the `-remote` identity. The non-remote directory is treated as a stale migration cache so another machine is not told to install both package names.

To repair only missing, outdated, or incorrectly linked recommended components:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -Repair
```

`-Repair` is idempotent. Correct links and current hooks are left untouched, and Task Scheduler is not changed when its state cannot be read.

## Device And Path Migration

The installer records device-local installation identity at:

```text
%USERPROFILE%\.local\state\codexkit\installation.json
```

It records the device name, user profile, Codex home, Agents root, and current KitRoot. When a machine is renamed, the Windows username/profile changes, OneDrive moves to another drive, or CodexKit moves within OneDrive:

1. Run `-Status` to identify changed identity or paths.
2. Run `-Repair`.
3. The installer repoints links, regenerates machine-local hooks, and migrates local project-registry rows that belonged to the previous identity of this same machine. It repairs the scheduled task only when `-InstallMemoryTask` is explicitly supplied.
4. Hook definitions may require `/hooks` trust again after their absolute paths change.

OneDrive registry rows remain device-neutral. Rows belonging to other devices are never rewritten.

If the Windows profile directory itself is moved or renamed, preserve `.local\state\codexkit\installation.json` at the same relative location under the new profile before running `-Repair`; that device-local state is what identifies the previous device name and path safely.

## Backup Retention

Installer backups use `<target>.backup.<timestamp>` and default to the two newest backups per target. Older matching backups in the same parent directory are removed only after a new backup is created.

Override the retention count when needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\OneDrive\CodexKit\Install-CodexKitForWindows.ps1" -Repair -BackupRetention 3
```

Use `-BackupRetention 0` only when no rollback copy should remain. The cleanup is restricted to the exact target backup prefix and never scans or deletes Codex work directories.

## Managed Stale Files

Each export compares the previous `manifest.json` with the files produced by the current run. Files managed by the previous export but absent from the current export are removed. This keeps deleted skills and previously enabled session/raw-config exports from lingering in OneDrive.

Only paths recorded in the previous manifest are eligible for cleanup. Hand-created files and directories that were never managed by the exporter are preserved.

Confirm:

- `.codex\skills` targets `CodexKit\skills\codex-skills`.
- `.codex\minimax-skills` targets `CodexKit\skills\minimax-skills`.
- `.agents\skills` targets `CodexKit\skills\agents-skills`.
- `.codex\AGENTS.md` targets `CodexKit\rules\global\AGENTS.md`.
- `.codex\config.toml` contains `[features] hooks = true`.
- `hooks.json` parses and referenced scripts exist in `.codex\bin`.
- after a real prompt, `.local\state\memory-and-improvement\user-prompt-hook.last-run.json` exists and its `source` is `codex`, not `codexkit-self-test`.
- `global-memory` is a directory link targeting `CodexKit\global-memory`.
- On the designated maintenance host only, `Codex Memory Maintenance` is `Ready`; manually trigger it when testing and require result `0`. Other machines should normally report the task as optional/missing.
- local `sessions` and `archived_sessions` remain ordinary directories unless the user explicitly enabled session links.
- when default-project synchronization is enabled, the Windows Documents
  `Codex` directory is a directory link targeting `CodexKit\CodexProjects`.
- when automation synchronization is enabled, `.codex\automations` is a
  directory link targeting `CodexKit\automations`; `.codex\state_5.sqlite`
  remains local.
- The user-visible shortcut is named `ChatGPT` and targets `Start-CodexManaged.vbs` on every machine. The shortcut uses the current Appx `ChatGPT.exe` icon, Managed mode is recorded in `installation.json`, and no stale CodexKit-managed `Codex.lnk` or mode-labeled shortcut remains.

## Session Safety

Session JSONL files can contain complete conversations, local paths, pasted credentials, and private data. OneDrive synchronization can produce conflicts when the same conversation is actively edited on two machines.

Only after explicit informed approval:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Export-CodexKit.ps1" -IncludeSessions -Force
```

Prefer one-time export over live session junctions unless the user explicitly needs cross-machine continuity. If live links are requested, install with `-Recommended -InstallSessionLinks` on the first machine or `-Repair -InstallSessionLinks` on an already installed machine after exporting with `-IncludeSessions -Force`.

The installer reports session link state in `-Status`, creates links only after `session-data\sessions`, `session-data\archived_sessions`, and `session-data\session_index.jsonl` exist, and prints OneDrive conflict guidance. Every machine uses the same Managed lifecycle. The running-device marker is advisory; do not actively edit the same conversation on two machines, and wait for OneDrive before opening a conversation that was just updated elsewhere.

Session links include `.codex\session_index.jsonl` because it stores thread-title metadata. Do not live-link `.codex\.codex-global-state.json` by default; it influences sidebar projects, prompt history, pinned state, workspace hints, and desktop host state, so treat it as a separate optional desktop-state sync decision.

When the user explicitly wants the desktop sidebar/project state synchronized, export with `-IncludeDesktopState` and install with `-InstallDesktopStateLink`. The shared file lives at `desktop-state\.codex-global-state.json`, and the installer should report it in `-Status`.

Codex desktop may atomically replace `.codex-global-state.json`, which can break single-file symlinks or hardlinks after installation. If the live desktop-state link does not persist, prefer controlled copy sync through the root `Switch-CodexMachine.cmd`: run `-Action Push` after closing Codex on the machine just used, wait for OneDrive, then run `-Action Pull` before opening Codex on the next machine.

Controlled desktop-state Push/Pull must protect task and project organization from catastrophic regressions. `Pull` treats the shared organization as authoritative and installs it into the local state while preserving device-only UI fields. `Push` treats the local organization as authoritative and publishes it to the shared primary. Only explicit `Sync` performs a three-way merge. Before overwriting either side, compare file size, workspace/task markers, and thread references with the existing shared/local state and the device-local merge baseline. Block and quarantine a candidate that collapses from a structured state to a small shell; never overwrite the good reference automatically. Keep only the shared `desktop-state\.codex-global-state.json` and one timestamped backup in OneDrive; conflict and quarantine diagnostics remain device-local under `%USERPROFILE%\.local\state\codexkit`. `-AllowStateRegression` is an explicit recovery/reset override only, not a normal launcher option.

Directional sync must not rewrite its authoritative source: Pull writes only the local state and device-local organization baseline; Push writes only the shared primary and baseline; explicit Sync may write both. Capture hashes of local, shared, baseline, and session-index inputs before generating output and abort before commit if any input changes. Replace each destination from a same-directory temporary file without first deleting the destination, and restore the pre-write backup if a commit fails. Backup-retention cleanup is best-effort after a successful commit and must not invalidate an otherwise valid sync receipt.

For user-facing switching, prefer root `Switch-CodexMachine.cmd`. It wraps `scripts\Switch-CodexMachine.ps1`, which offers a menu and coordinates desktop-state `Push`/`Pull`, session-link repair, and status checks.

For startup automation, use root `Start-CodexManaged.vbs` on every machine for hidden background launch. Keep `Start-CodexManaged.cmd` for troubleshooting with visible logs. The launcher performs an authoritative Pull before launch, waits for its ChatGPT process to exit, and performs an authoritative Push afterward. It never hot-replaces desktop state in a running process and must not start a second managed instance while ChatGPT is already running on that same machine.

Managed launch is fail-closed: every nested installer/sync command must return zero, and the Pull must produce a fresh device-local `%USERPROFILE%\.local\state\codexkit\last-desktop-sync.json` receipt containing the current device, mode, completion time, script hashes, state hashes, organization hash, and thread-catalog verification before ChatGPT may open. Recompute every receipt hash immediately before launch and reject any post-Pull change. A hidden-launch failure must show a Windows popup and point to `Start-CodexManaged.cmd` for visible diagnostics. This prevents an outdated OneDrive skill copy or a silently failed Pull from opening ChatGPT with stale sidebar state.

Managed launchers maintain the single advisory marker `desktop-state\codex-running.json`. It always exposes `running` as `1` or `0` and also records a per-device mode, process id, start time, and heartbeat. Before launching, warn with an explicit Yes/No prompt when another device has a fresh marker. Refresh the heartbeat every 60 seconds, clear only the current device on normal exit, and prune entries older than five minutes so a crash or power loss cannot leave a permanent false lock. This is an advisory OneDrive coordination signal, not a distributed lock: do not block recovery or assume instantaneous cross-device propagation, and do not create per-device state snapshots or marker backups.

Desktop sidebar organization remains editable on every machine. Pull/Push transfer only organizational fields such as projects, task assignments, workspace hints, descriptions, order, and pins; preserve window bounds, permission state, browser tabs, active workspace, and other device-only fields from each machine's own file. Use explicit `-Action Sync` only when a genuine three-way merge is wanted; in that mode non-conflicting additions, changes, and deletions from both machines survive, and the currently synchronizing machine wins same-field conflicts with device-local diagnostics.

The controlled sync also validates `session-data\session_index.jsonl`. When no other device has a fresh running heartbeat, remove duplicate rows by task ID and retain the row with the newest `updated_at` value (last row wins ties). Abort without changing the index on malformed JSON, retain one rollback copy under `%USERPROFILE%\.local\state\codexkit\session-index-backups`, and defer repair whenever another device is active.

Task visibility also depends on the device-local `%USERPROFILE%\.codex\state_5.sqlite` `threads` catalog; linked rollout files and `session_index.jsonl` alone do not guarantee that another desktop app lists a task. Before a managed Pull launches ChatGPT, run `Repair-CodexThreadCatalog.mjs` while the app is closed. It transactionally registers only missing top-level tasks that have both a shared title-index row and a shared rollout file, preserves every existing database row, ignores legacy child-rollout aliases whose filename ID differs from the canonical `session_id`, runs SQLite integrity and post-insert checks, and checkpoints the WAL before the launch receipt is hashed. Never copy or live-link `state_5.sqlite` between machines.

The desktop launcher must discover packaged builds from their Appx manifest and the registered `codex` protocol instead of assuming a fixed executable name. Current builds may retain the `OpenAI.Codex` package identity while declaring `app\ChatGPT.exe` as the desktop entry point; older builds used `Codex.exe`. Process monitoring must follow the resolved manifest executable and must exclude the bundled CLI at `app\resources\codex.exe`.

Treat the Windows Codex-to-ChatGPT change as an in-place application migration, not a coexistence scenario. Keep package lookup narrowly scoped to the explicit `OpenAI.Codex` and `OpenAI.ChatGPT` identities plus the `codex` protocol; do not add broad ChatGPT process or package discovery.

## Editing

When changing behavior:

1. Edit the bundled exporter.
2. Parse it with `System.Management.Automation.Language.Parser`.
3. Test export in an isolated workspace.
4. Test the generated installer against a fake user profile with Windows
   PowerShell 5.1, including pre-existing empty shared roots and hidden files.
5. Copy the validated exporter to `%USERPROFILE%\Downloads\Export-CodexKit.ps1` only when maintaining a machine-specific convenience entry point.
