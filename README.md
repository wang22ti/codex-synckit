# Codex SyncKit

[简体中文](README.zh-CN.md) | English

**Carry the same Codex working environment between Windows PCs through
OneDrive—without Git, manual junctions, or copying hidden folders by hand.**

Codex SyncKit exports the parts of Codex that are useful across machines into a
private OneDrive folder, safely connects each PC to that shared source, and
installs a managed `ChatGPT` shortcut. After the one-time setup, normal use is
simply opening ChatGPT from that shortcut. There are no daily PowerShell
commands to remember.

## Why use it

- **Built for Codex:** it understands skills, hooks, guidance, memory, projects,
  automations, conversations, and desktop sidebar state.
- **No Git for end users:** install from a ZIP with one PowerShell command.
- **Safe by default:** existing data is backed up, important copies are checked
  with SHA-256, conflicts stop before mutation, and desktop synchronization
  fails closed.
- **Private state stays private:** credentials, command approvals, caches, logs,
  local preferences, and the Codex SQLite database are deliberately excluded.
- **One consistent launch path:** the managed shortcut coordinates the state
  that must be pulled before ChatGPT opens and pushed after it closes.

## How it works

1. The bootstrap installer creates a private `CodexKit` directory in OneDrive
   containing the selected shared Codex data.
2. It connects each Windows PC to that directory with verified links, hooks,
   and a managed Start-menu shortcut.
3. OneDrive transports file changes between PCs. Codex SyncKit supplies the
   Codex-specific layout, installation, validation, backup, and conflict
   safeguards that ordinary folder synchronization does not provide.

## What can be synchronized

| Category | Default | What it provides |
| --- | --- | --- |
| Skills, hooks, and global guidance | On | The same Codex capabilities and instructions on every PC |
| Global memory | On with recommended setup | Shared long-term context without copying device-local maintenance state |
| Environment and plugin inventories | On | A comparison snapshot of each PC; plugins are reported, not copied |
| Codex projects | Optional | The same project workspace under the normal Windows Documents location |
| Codex automations | Optional | Shared automation definitions; only one designated machine should run a given schedule |
| Conversation history | On | Lets another PC reopen and continue the same Codex tasks; it may contain complete prompts and responses |
| Sidebar and project organization | On | Carries task titles, pins, project grouping, ordering, and workspace hints between PCs |
| Credentials, approvals, caches, logs, local preferences, `state_5.sqlite` | Never | These remain device-local for security and stability |

Conversation history and sidebar organization are privacy-sensitive because
they can contain conversation text, project names, and local paths. They are
enabled by default because carrying active Codex tasks and their organization
between PCs is a core purpose of Codex SyncKit. Keep the generated `CodexKit`
folder private and see [Privacy](docs/PRIVACY.md) for the data boundary.

## Comparison with continuity features in other agents

| Solution | Conversation or task continuity | Rules and memory | Cross-device scope |
| --- | --- | --- | --- |
| **Codex SyncKit** | Synchronizes complete conversations, task titles, pins, groups, and ordering | Synchronizes skills, hooks, global guidance, and long-term memory | Treats Codex conversations, organization, capabilities, and installation state as one portable environment |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code/cli-usage) | Continues the latest conversation or resumes one by session ID | [`CLAUDE.md`](https://docs.anthropic.com/en/docs/claude-code/memory) stores project- and user-level guidance | Official features focus on session resume and file-based memory; sharing across PCs still requires moving the relevant files and state |
| [Cursor](https://docs.cursor.com/en/context/memories) | Memories preserve project context across conversations | Automatically generated, project-scoped Memories | Focuses on agent memory and rules rather than complete conversation, sidebar, plugin, and environment migration |
| [Windsurf Cascade](https://docs.windsurf.com/windsurf/cascade/memories) | Memories preserve context across conversations | Automatic Memories stay on the current device; shared rules can live in `.windsurf/rules/` or `AGENTS.md` | Automatic Memories do not cross devices; durable sharing primarily uses project files |
| [Cline](https://docs.cline.bot/core-workflows/task-management) | Saves complete task history and can resume conversations, code changes, commands, and decisions | Context is retained in task history | Task history is stored locally; cross-device use needs a separate storage or synchronization strategy |

Most of these products address session recovery, memory, or reusable rules
inside one agent. Codex SyncKit instead treats Codex conversations,
organization, skills, hooks, memory, and installation state as one portable
environment.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or newer
- OneDrive
- Codex/ChatGPT desktop or Codex CLI
- Node.js for desktop-state and task-catalog helpers

Git is not required for installation or normal use.

## Install from a release ZIP

1. Download the latest release ZIP and its `.sha256` file.
2. Verify the checksum and extract the ZIP.
3. Open PowerShell in the extracted directory.
4. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1 -Recommended
```

This installs the bundled skill under its compatibility ID,
`codexkit-sync`, exports the private OneDrive package, applies the recommended
links, and creates the managed `ChatGPT` shortcut. Conversation and desktop
state synchronization are enabled by default. Add `-ExcludeSessions` or
`-ExcludeDesktopState` only if you deliberately do not want those categories
in the private package.

## Normal use and synchronization precautions

There is no daily command workflow. Open ChatGPT from the managed Start-menu
shortcut.

- Before moving to another PC, close ChatGPT and wait until OneDrive reports
  that the `CodexKit` folder is up to date.
- Do not use the same synchronized conversation on two PCs at the same time.
- If conversation or sidebar synchronization is enabled, use only one managed
  ChatGPT instance at a time and let its closing synchronization finish.
- Never publish or share the generated private `CodexKit` directory. It may
  contain memory, project metadata, environment details, and—when enabled—full
  conversation history.
- Do not manually copy or link credentials, command-approval rules,
  `state_5.sqlite`, caches, or logs between machines.
- OneDrive conflict copies and a stale running-device warning should be treated
  as a signal to stop and verify which PC has the newest state.

For privacy boundaries, recovery, and removal, see
[Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and
[Uninstall](docs/UNINSTALL.md).

## Current scope

The alpha release is intentionally focused on Windows and OneDrive. Codex
internal storage may change between desktop releases; unsupported layouts must
stop with a diagnostic rather than being modified speculatively.

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The project
is available under the [MIT License](LICENSE).

Codex SyncKit is an independent community project. It is not affiliated with,
sponsored by, or endorsed by OpenAI. OpenAI, ChatGPT, and Codex are trademarks
of their respective owners. No OpenAI logos are distributed with this project.
