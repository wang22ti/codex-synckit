# Windows Maintenance

Use Windows Task Scheduler with Git for Windows when WSL cron is unavailable.
The Windows layer schedules and launches the existing Bash maintenance scripts; it does not duplicate memory organization logic.
When Git Bash does not provide `flock`, interval maintenance uses an atomic directory lock fallback.

## Requirements

- Windows PowerShell 5.1 or later
- Git for Windows with `bash.exe`
- Codex running under the same interactive Windows user that owns the task

## Preview

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "$HOME\.codex\skills\memory-and-improvement\scripts\maintenance\install-windows-maintenance.ps1"
```

Without `-Apply`, the installer prints the resolved task configuration and does not change Task Scheduler.
It reads the same built-in and user `config.toml` defaults as the Bash scheduler.

## Install

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "$HOME\.codex\skills\memory-and-improvement\scripts\maintenance\install-windows-maintenance.ps1" `
  -Apply
```

Common overrides:

```powershell
# Every 6 hours
.\install-windows-maintenance.ps1 -Mode interval -IntervalMinutes 360 -Apply

# Daily at 04:00
.\install-windows-maintenance.ps1 -Mode fixed -Hour 4 -Minute 0 -Apply
```

The task is named `Codex Memory Maintenance` by default and runs for the current interactive user. Interval mode installs both a repeating trigger and a logon catch-up trigger; `interval-maintenance.sh` prevents an early or duplicate maintenance run. Logs are written under:

The scheduled action starts through `wscript.exe` and `run-windows-maintenance-hidden.vbs`, so PowerShell and Git Bash run without opening a console window.

```text
%USERPROFILE%\.local\state\memory-and-improvement\logs\windows-maintenance.log
```

Interval state is stored in:

```text
%USERPROFILE%\.local\state\memory-and-improvement\interval-maintenance.last-run
```

## Shared Project Registry

When this skill is installed from a OneDrive-backed CodexKit, registered project memories are stored in:

```text
<OneDrive>\CodexKit\memory-system\project-memory-registry.tsv
```

The TSV columns are `storage`, `device`, and `path`.

- Local paths use `local`, the Windows computer name, and the absolute normalized path.
- OneDrive paths use `onedrive`, `-` for the device, and a path relative to the OneDrive root.
- Each machine ignores local records owned by other devices.
- OneDrive records are resolved using that machine's current OneDrive root.
- The CodexKit installer merges the machine's legacy registry into this shared TSV.
- Re-registering an existing path does not rewrite the shared file.
- If OneDrive creates a `project-memory-registry*.tsv` conflict copy, registry reads include it and the next registry update folds its valid records back into the canonical file.

The older machine-local registry under `%USERPROFILE%\.local\state\memory-and-improvement` remains readable and is migrated on the next registry update.

The following state intentionally remains local to each Windows device:

- maintenance logs and last-run timestamps
- hook reflect markers
- removed-project-memory archives
- the installed Task Scheduler task
- Git metadata used for local memory history

Project `.learnings` directories outside OneDrive are also local. Their registry rows synchronize, but another device ignores those rows because they carry the originating device name.

## Verify

```powershell
Get-ScheduledTask -TaskName 'Codex Memory Maintenance'
Start-ScheduledTask -TaskName 'Codex Memory Maintenance'
Get-Content "$HOME\.local\state\memory-and-improvement\logs\windows-maintenance.log" -Tail 50
```

Re-run the installer with `-Apply` after changing maintenance schedule defaults because installed tasks freeze their effective schedule and command arguments.
