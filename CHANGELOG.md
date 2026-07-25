# Changelog

## 0.1.0-alpha - 2026-07-25

- Renamed the public project from CodexKit Sync to Codex SyncKit.
- Initial public-source packaging.
- Added a PowerShell bootstrap installer.
- Added an allowlist-based public release builder.
- Added private-data and credential release gates.
- Added Windows CI for PowerShell parsing and regression tests.
- Added manifest drift checks for core CodexKit files.
- Documented privacy, security, compatibility, and uninstall boundaries.
- Made conversation and desktop-organization synchronization part of the
  default recommended setup, with explicit opt-out switches.
- Prevented stale-file cleanup from deleting conversation or desktop-state
  data, including when a file cannot be hashed while ChatGPT is using it.
- Bundled the optional `memory-and-improvement` long-term memory subsystem in
  the public source and Release.
- Required an explicit Yes or No installation choice for the memory subsystem,
  with matching switches for unattended installation.
- Added a double-click setup entry point and simplified installation to
  download, extract, and launch.
