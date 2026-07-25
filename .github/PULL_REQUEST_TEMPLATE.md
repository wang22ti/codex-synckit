## Summary

Describe the user-visible behavior and why it is needed.

## Data and rollback

- Data read, written, linked, moved, or deleted:
- Backup and rollback behavior:
- Compatibility assumptions:

## Verification

- [ ] PowerShell and Node regression tests pass.
- [ ] `bash ./tools/Test-MemorySubsystem.sh` passes when the memory subsystem is affected.
- [ ] `tools/Test-PublicRelease.ps1` passes.
- [ ] No generated CodexKit, conversations, memory, credentials, or private paths are included.
- [ ] `CHANGELOG.md` and relevant documentation are updated.
