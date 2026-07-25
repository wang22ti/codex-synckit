# Uninstall and rollback

Codex SyncKit preserves existing targets as timestamped
`<target>.backup.<timestamp>` entries before replacing them.

Because an installation can include different optional links, the alpha release
does not provide a destructive one-command full uninstall.

To roll back safely:

1. Fully close ChatGPT and Codex CLI.
2. Run `Install-CodexKitForWindows.ps1 -Status` and record enabled links.
3. Remove only links whose target resolves inside the intended CodexKit.
4. Restore the newest matching backup for each removed target.
5. Remove the `ChatGPT` shortcut only if it targets this CodexKit's
   `Start-CodexManaged.vbs`.
6. On the designated automation host, remove the maintenance task with:

```powershell
.\Install-CodexKitForWindows.ps1 -RemoveMemoryTask
```

7. Keep the OneDrive CodexKit until restored local directories and Codex startup
   have been verified.

Do not delete the OneDrive CodexKit first. It may be the live source behind
directory links.
