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
- Made one-click setup distinguish a new Kit from an existing shared Kit,
  preventing later PCs from exporting stale local conversations, sidebar
  state, skills, or memory over OneDrive data.
- Added fail-closed checks for nonempty unrecognized destinations and
  initialize/join installer regression coverage.
- Added issue and pull-request templates with a private security-reporting
  route.
- Added full memory-subsystem CI coverage, local Markdown-link validation, and
  post-build scanning of the extracted Release archive.
- Added a tag-driven workflow that builds, verifies, and publishes GitHub
  Release assets.
- Added a versioned product marker and installer hash check before another PC
  executes an existing shared Kit installer.
- Made tag releases wait for the full reusable test workflow and forced Shell
  and AWK files to retain LF line endings across Windows checkouts.
