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

Codex SyncKit does not replace OneDrive; it makes Codex safe and practical to
use on top of OneDrive.

## What can be synchronized

| Category | Default | What it provides |
| --- | --- | --- |
| Skills, hooks, and global guidance | On | The same Codex capabilities and instructions on every PC |
| Global memory | On with recommended setup | Shared long-term context without copying device-local maintenance state |
| Environment and plugin inventories | On | A comparison snapshot of each PC; plugins are reported, not copied |
| Codex projects | Optional | The same project workspace under the normal Windows Documents location |
| Codex automations | Optional | Shared automation definitions; only one designated machine should run a given schedule |
| Conversation history | Off | Lets another PC reopen and continue the same Codex tasks; it may contain complete prompts and responses |
| Sidebar and project organization | Off | Carries task titles, pins, project grouping, ordering, and workspace hints between PCs |
| Credentials, approvals, caches, logs, local preferences, `state_5.sqlite` | Never | These remain device-local for security and stability |

Conversation history and sidebar organization are the privacy-sensitive
features. They exist only for people who want their active Codex tasks and
desktop organization to follow them to another PC. They are disabled by
default because they can contain conversation text, project names, and local
paths. See [Privacy](docs/PRIVACY.md) before enabling them.

## Comparison with other approaches

| Solution | Primary purpose | Understands Codex layout | User setup | Best fit |
| --- | --- | --- | --- | --- |
| **Codex SyncKit** | A ready-to-use Codex environment across Windows PCs, transported by OneDrive | Yes | One installer; no Git or manual links | People who want Codex to feel like the same workspace on every PC |
| [OneDrive](https://support.microsoft.com/en-us/onedrive/sync-your-computer-s-files-and-folders-with-onedrive) alone | Cloud file and folder synchronization | No | You must decide what hidden data to copy and how Codex finds it | Ordinary documents and folders |
| [Syncthing](https://docs.syncthing.net/intro/getting-started.html) | Direct folder synchronization between paired devices | No | Install on each device, pair device IDs, and select folders | General file sync without relying on a central cloud folder |
| [chezmoi](https://www.chezmoi.io/what-does-chezmoi-do/) | Declarative dotfile management across machines | No | Learn its source-state, templates, and Git-oriented workflow | Technical users managing cross-platform shell and application configuration |
| [Git](https://git-scm.com/about) plus custom scripts | Versioned configuration under complete user control | Only what you build | Design the repository, exclusions, links, migration, and conflict rules yourself | Developers who want custom behavior and full history |

General-purpose tools are broader and may be a better choice for general files
or cross-platform dotfiles. Codex SyncKit is narrower: it packages the
Codex-specific decisions and safety rules so users do not have to design that
system themselves.

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
state synchronization remain off unless explicitly enabled.

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
