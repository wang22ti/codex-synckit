[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceScripts = Split-Path -Parent $PSScriptRoot
$sourceKitRoot = (Resolve-Path -LiteralPath (Join-Path $sourceScripts "..\..\..\..")).Path
$publicSourceRoot = (Resolve-Path -LiteralPath (Join-Path $sourceScripts "..\..")).Path
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCommand) { $nodeCommand = Get-Command node -ErrorAction Stop }
$node = $nodeCommand.Source
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "codexkit-sync-tests-$PID-$([guid]::NewGuid().ToString('N'))"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Normalize-Text([string]$Text) {
    return $Text.Replace("`r`n", "`n").TrimEnd()
}

function Write-Json($Path, $Value) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20 -Compress), (New-Object Text.UTF8Encoding($false)))
}

function New-State([string]$DeviceValue, [string]$TaskId, [string]$Title) {
    [ordered]@{
        "electron-main-window-bounds" = [ordered]@{ x = $DeviceValue }
        "electron-persisted-atom-state" = [ordered]@{
            "device-only-value" = $DeviceValue
            "thread-descriptions-v1" = [ordered]@{ $TaskId = $Title }
        }
        "electron-saved-workspace-roots" = @("C:\workspace")
        "project-order" = @()
        "pinned-thread-ids" = @()
        "thread-workspace-root-hints" = [ordered]@{ $TaskId = "C:\workspace" }
        "thread-projectless-output-directories" = @{}
        "thread-writable-roots" = @{}
        "local-projects" = @{}
        "project-writable-roots" = @{}
        "thread-project-assignments" = @{}
        "projectless-thread-ids" = @($TaskId)
    }
}

function New-Fixture([string]$Name) {
    $root = Join-Path $testRoot $Name
    $kit = Join-Path $root "kit"
    $scripts = Join-Path $kit "skills\codex-skills\codexkit-sync\scripts"
    $profile = Join-Path $root "profile"
    New-Item -ItemType Directory -Force -Path $scripts,(Join-Path $kit "desktop-state"),(Join-Path $kit "session-data"),(Join-Path $profile ".codex") | Out-Null
    foreach ($name in @("Sync-CodexDesktopState.ps1", "Merge-CodexSidebarState.mjs", "Repair-CodexSessionIndex.mjs", "Repair-CodexThreadCatalog.mjs", "Switch-CodexMachine.ps1", "Start-CodexWithSync.ps1")) {
        Copy-Item -LiteralPath (Join-Path $sourceScripts $name) -Destination (Join-Path $scripts $name) -Force
    }
    [IO.File]::WriteAllText((Join-Path $kit "Install-CodexKitForWindows.ps1"), "exit 0`n", (New-Object Text.UTF8Encoding($false)))
    $switchCommand = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0skills\codex-skills\codexkit-sync\scripts\Switch-CodexMachine.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n"
    [IO.File]::WriteAllText((Join-Path $kit "Switch-CodexMachine.cmd"), $switchCommand, (New-Object Text.ASCIIEncoding))
    [pscustomobject]@{ Root = $root; Kit = $kit; Scripts = $scripts; Profile = $profile }
}

function Invoke-StateSync($Fixture, [string]$Mode) {
    $oldProfile = $env:USERPROFILE
    $oldNode = $env:CODEXKIT_NODE_EXE
    $env:USERPROFILE = $Fixture.Profile
    $env:CODEXKIT_NODE_EXE = $node
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Fixture.Scripts "Sync-CodexDesktopState.ps1") "-$Mode" -BackupRetention 1
        if ($LASTEXITCODE -ne 0) { throw "$Mode failed with exit code $LASTEXITCODE" }
    } finally {
        $env:USERPROFILE = $oldProfile
        $env:CODEXKIT_NODE_EXE = $oldNode
    }
}

try {
    $isPublicSourceTree = Test-Path -LiteralPath (Join-Path $publicSourceRoot "Install-CodexKitSync.ps1") -PathType Leaf
    if (-not $isPublicSourceTree) {
        foreach ($managedLauncher in @("Start-CodexManaged.cmd", "Start-CodexManaged.vbs")) {
            Assert-True (Test-Path -LiteralPath (Join-Path $sourceKitRoot $managedLauncher) -PathType Leaf) "Missing unified launcher: $managedLauncher"
        }
    }
    foreach ($legacyLauncher in @("Start-CodexResident.cmd", "Start-CodexResident.vbs", "Start-CodexSynced.cmd", "Start-CodexSynced.vbs")) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $sourceKitRoot $legacyLauncher))) "Legacy launcher still exists: $legacyLauncher"
    }
    $expectedManagedCmd = @'
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\codex-skills\codexkit-sync\scripts\Start-CodexWithSync.ps1" %*
set "exitCode=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %exitCode%
'@
    $expectedManagedVbs = @'
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
script = root & "\skills\codex-skills\codexkit-sync\scripts\Start-CodexWithSync.ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & script & Chr(34)
shell.Run command, 0, False
'@
    if (-not $isPublicSourceTree) {
        $managedCmdText = Normalize-Text (Get-Content -LiteralPath (Join-Path $sourceKitRoot "Start-CodexManaged.cmd") -Raw -Encoding UTF8)
        $managedVbsText = Normalize-Text (Get-Content -LiteralPath (Join-Path $sourceKitRoot "Start-CodexManaged.vbs") -Raw -Encoding UTF8)
        Assert-True ($managedCmdText -ceq (Normalize-Text $expectedManagedCmd)) "Root Managed CMD launcher differs from its canonical content"
        Assert-True ($managedVbsText -ceq (Normalize-Text $expectedManagedVbs)) "Root Managed VBS launcher differs from its canonical content"
    }
    $exporterText = Get-Content -LiteralPath (Join-Path $sourceScripts "Export-CodexKit.ps1") -Raw -Encoding UTF8
    $normalizedExporter = Normalize-Text $exporterText
    Assert-True ($normalizedExporter.Contains((Normalize-Text $expectedManagedCmd))) "Exporter CMD template differs from the root Managed launcher"
    Assert-True ($normalizedExporter.Contains((Normalize-Text $expectedManagedVbs))) "Exporter VBS template differs from the root Managed launcher"
    Assert-True ($exporterText.Contains('Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexManaged.cmd")')) "Exporter does not generate the Managed CMD launcher"
    Assert-True ($exporterText.Contains('Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexManaged.vbs")')) "Exporter does not generate the Managed VBS launcher"
    Assert-True (-not $exporterText.Contains('Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexResident.cmd")')) "Exporter still generates the Resident launcher"
    Assert-True (-not $exporterText.Contains('Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexSynced.cmd")')) "Exporter still generates the Synced launcher"

    $pull = New-Fixture "pull"
    $pullLocal = Join-Path $pull.Profile ".codex\.codex-global-state.json"
    $pullShared = Join-Path $pull.Kit "desktop-state\.codex-global-state.json"
    Write-Json $pullLocal (New-State "local-device" "01900000-0000-0000-0000-000000000001" "local task")
    Write-Json $pullShared (New-State "shared-device" "01900000-0000-0000-0000-000000000002" "shared task")
    $sharedBefore = (Get-FileHash -LiteralPath $pullShared -Algorithm SHA256).Hash
    Invoke-StateSync $pull "Pull"
    $pulled = Get-Content -LiteralPath $pullLocal -Raw | ConvertFrom-Json
    Assert-True ($pulled.'electron-persisted-atom-state'.'device-only-value' -eq "local-device") "Pull lost local device-only state"
    Assert-True (@($pulled.'projectless-thread-ids') -contains "01900000-0000-0000-0000-000000000002") "Pull did not install shared task"
    Assert-True ((Get-FileHash -LiteralPath $pullShared -Algorithm SHA256).Hash -eq $sharedBefore) "Pull rewrote the shared primary"
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $pullShared) -Filter ".codex-global-state.json.backup.*" -File).Count -eq 0) "Pull created an unnecessary shared backup"
    $pullReceipt = Get-Content -LiteralPath (Join-Path $pull.Profile ".local\state\codexkit\last-desktop-sync.json") -Raw | ConvertFrom-Json
    Assert-True ($pullReceipt.mode -eq "pull" -and ([string]$pullReceipt.organization_sha256).Length -eq 64) "Pull receipt is incomplete"
    Assert-True ($pullReceipt.thread_catalog_status -eq "database-missing") "Pull receipt did not record the thread catalog state"

    $catalog = New-Fixture "catalog"
    $catalogTask = "019f0000-0000-7000-8000-000000000099"
    Write-Json (Join-Path $catalog.Profile ".codex\.codex-global-state.json") (New-State "catalog-device" $catalogTask "catalog local")
    Write-Json (Join-Path $catalog.Kit "desktop-state\.codex-global-state.json") (New-State "shared-device" $catalogTask "catalog shared")
    $catalogSessions = Join-Path $catalog.Kit "session-data\sessions\2026\07\21"
    $catalogArchived = Join-Path $catalog.Kit "session-data\archived_sessions"
    New-Item -ItemType Directory -Force -Path $catalogSessions,$catalogArchived | Out-Null
    $catalogRollout = Join-Path $catalogSessions "rollout-2026-07-21T00-00-00-$catalogTask.jsonl"
    $catalogMeta = [ordered]@{ timestamp = "2026-07-21T00:00:00Z"; type = "session_meta"; payload = [ordered]@{ id = $catalogTask; session_id = $catalogTask; timestamp = "2026-07-21T00:00:00Z"; cwd = "C:\workspace"; source = "vscode"; thread_source = "user"; model_provider = "openai"; cli_version = "test" } }
    [IO.File]::WriteAllText($catalogRollout, (($catalogMeta | ConvertTo-Json -Depth 10 -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
    $catalogIndex = [ordered]@{ id = $catalogTask; thread_name = "Catalog imported task"; updated_at = "2026-07-21T00:00:00Z" }
    [IO.File]::WriteAllText((Join-Path $catalog.Kit "session-data\session_index.jsonl"), (($catalogIndex | ConvertTo-Json -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
    $catalogDb = Join-Path $catalog.Profile ".codex\state_5.sqlite"
    $createCatalogDb = @'
const {DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync(process.argv[2]);
db.exec("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, source TEXT NOT NULL, model_provider TEXT NOT NULL, cwd TEXT NOT NULL, title TEXT NOT NULL, sandbox_policy TEXT NOT NULL, approval_mode TEXT NOT NULL, tokens_used INTEGER NOT NULL DEFAULT 0, has_user_event INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER, cli_version TEXT NOT NULL DEFAULT '', first_user_message TEXT NOT NULL DEFAULT '', memory_mode TEXT NOT NULL DEFAULT 'enabled', preview TEXT NOT NULL DEFAULT '', recency_at INTEGER NOT NULL DEFAULT 0, history_mode TEXT NOT NULL DEFAULT 'legacy')");
db.close();
'@
    $createCatalogDbScript = Join-Path $catalog.Root "create-catalog-db.cjs"
    [IO.File]::WriteAllText($createCatalogDbScript, $createCatalogDb, (New-Object Text.UTF8Encoding($false)))
    & $node --no-warnings $createCatalogDbScript $catalogDb
    if ($LASTEXITCODE -ne 0) { throw "Could not create catalog integration fixture" }
    Invoke-StateSync $catalog "Pull"
    $readCatalogDb = @'
const {DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync(process.argv[2],{readOnly:true});
const row=db.prepare('SELECT title FROM threads WHERE id=?').get(process.argv[3]);
db.close();
if(!row || row.title!=='Catalog imported task') process.exit(7);
'@
    $readCatalogDbScript = Join-Path $catalog.Root "read-catalog-db.cjs"
    [IO.File]::WriteAllText($readCatalogDbScript, $readCatalogDb, (New-Object Text.UTF8Encoding($false)))
    & $node --no-warnings $readCatalogDbScript $catalogDb $catalogTask
    Assert-True ($LASTEXITCODE -eq 0) "Pull did not register the shared task in state_5.sqlite"
    $catalogReceipt = Get-Content -LiteralPath (Join-Path $catalog.Profile ".local\state\codexkit\last-desktop-sync.json") -Raw | ConvertFrom-Json
    Assert-True ($catalogReceipt.thread_catalog_status -eq "reconciled" -and $catalogReceipt.thread_catalog_inserted_count -eq 1) "Pull receipt did not verify the repaired thread catalog"
    $oldProfile = $env:USERPROFILE
    $oldNode = $env:CODEXKIT_NODE_EXE
    $oldDesktop = $env:CODEX_DESKTOP_EXE
    $env:USERPROFILE = $catalog.Profile
    $env:CODEXKIT_NODE_EXE = $node
    $env:CODEX_DESKTOP_EXE = Join-Path $env:WINDIR "System32\notepad.exe"
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $catalog.Scripts "Start-CodexWithSync.ps1") -NoLaunch
        Assert-True ($LASTEXITCODE -eq 0) "Managed launcher did not accept the reconciled thread catalog receipt"
    } finally {
        $env:USERPROFILE = $oldProfile
        $env:CODEXKIT_NODE_EXE = $oldNode
        $env:CODEX_DESKTOP_EXE = $oldDesktop
    }

    $push = New-Fixture "push"
    $pushLocal = Join-Path $push.Profile ".codex\.codex-global-state.json"
    $pushShared = Join-Path $push.Kit "desktop-state\.codex-global-state.json"
    Write-Json $pushLocal (New-State "local-device" "01900000-0000-0000-0000-000000000003" "local task")
    Write-Json $pushShared (New-State "shared-device" "01900000-0000-0000-0000-000000000004" "shared task")
    $localBefore = (Get-FileHash -LiteralPath $pushLocal -Algorithm SHA256).Hash
    Invoke-StateSync $push "Push"
    $pushed = Get-Content -LiteralPath $pushShared -Raw | ConvertFrom-Json
    Assert-True ($pushed.'electron-persisted-atom-state'.'device-only-value' -eq "shared-device") "Push lost shared device-only state"
    Assert-True (@($pushed.'projectless-thread-ids') -contains "01900000-0000-0000-0000-000000000003") "Push did not publish local task"
    Assert-True ((Get-FileHash -LiteralPath $pushLocal -Algorithm SHA256).Hash -eq $localBefore) "Push rewrote the local source"
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $pushLocal) -Filter ".codex-global-state.json.backup.*" -File).Count -eq 0) "Push created an unnecessary local backup"

    $launcher = New-Fixture "launcher"
    $launcherLocal = Join-Path $launcher.Profile ".codex\.codex-global-state.json"
    $launcherShared = Join-Path $launcher.Kit "desktop-state\.codex-global-state.json"
    Write-Json $launcherLocal (New-State "launcher-device" "01900000-0000-0000-0000-000000000005" "old local task")
    Write-Json $launcherShared (New-State "shared-device" "01900000-0000-0000-0000-000000000006" "launcher shared task")
    $oldProfile = $env:USERPROFILE
    $oldNode = $env:CODEXKIT_NODE_EXE
    $oldDesktop = $env:CODEX_DESKTOP_EXE
    $env:USERPROFILE = $launcher.Profile
    $env:CODEXKIT_NODE_EXE = $node
    $env:CODEX_DESKTOP_EXE = Join-Path $env:WINDIR "System32\notepad.exe"
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $launcher.Scripts "Start-CodexWithSync.ps1") -NoLaunch
        Assert-True ($LASTEXITCODE -eq 0) "Managed no-launch verification failed"
    } finally {
        $env:USERPROFILE = $oldProfile
        $env:CODEXKIT_NODE_EXE = $oldNode
        $env:CODEX_DESKTOP_EXE = $oldDesktop
    }
    $launcherReceipt = Get-Content -LiteralPath (Join-Path $launcher.Profile ".local\state\codexkit\last-desktop-sync.json") -Raw | ConvertFrom-Json
    Assert-True ($launcherReceipt.mode -eq "pull") "Managed launcher did not verify a fresh Pull receipt"

    $receiptMismatch = New-Fixture "receipt-mismatch"
    Write-Json (Join-Path $receiptMismatch.Profile ".codex\.codex-global-state.json") (New-State "local-device" "01900000-0000-0000-0000-000000000007" "local")
    Write-Json (Join-Path $receiptMismatch.Kit "desktop-state\.codex-global-state.json") (New-State "shared-device" "01900000-0000-0000-0000-000000000008" "shared")
    $mismatchInstaller = @'
param([switch]$Repair, [switch]$InstallSessionLinks, [switch]$Status)
if ($Status) {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot "skills\codex-skills\codexkit-sync\scripts\Merge-CodexSidebarState.mjs") -Value " "
}
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $receiptMismatch.Kit "Install-CodexKitForWindows.ps1"), $mismatchInstaller, (New-Object Text.UTF8Encoding($false)))
    $oldProfile = $env:USERPROFILE
    $oldNode = $env:CODEXKIT_NODE_EXE
    $oldDesktop = $env:CODEX_DESKTOP_EXE
    $oldSuppress = $env:CODEXKIT_SUPPRESS_FAILURE_POPUP
    $env:USERPROFILE = $receiptMismatch.Profile
    $env:CODEXKIT_NODE_EXE = $node
    $env:CODEX_DESKTOP_EXE = Join-Path $env:WINDIR "System32\notepad.exe"
    $env:CODEXKIT_SUPPRESS_FAILURE_POPUP = "1"
    try {
        $mismatchProcess = Start-Process -FilePath powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $receiptMismatch.Scripts "Start-CodexWithSync.ps1"), "-NoLaunch"
        ) -Wait -PassThru -WindowStyle Hidden
        Assert-True ($mismatchProcess.ExitCode -ne 0) "Managed launcher accepted a receipt after a verified file changed"
    } finally {
        $env:USERPROFILE = $oldProfile
        $env:CODEXKIT_NODE_EXE = $oldNode
        $env:CODEX_DESKTOP_EXE = $oldDesktop
        $env:CODEXKIT_SUPPRESS_FAILURE_POPUP = $oldSuppress
    }

    $failure = New-Fixture "failure"
    [IO.File]::WriteAllText((Join-Path $failure.Scripts "Sync-CodexDesktopState.ps1"), "exit 7`n", (New-Object Text.UTF8Encoding($false)))
    $oldProfile = $env:USERPROFILE
    $env:USERPROFILE = $failure.Profile
    try {
        $failureProcess = Start-Process -FilePath powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $failure.Scripts "Switch-CodexMachine.ps1"), "-Action", "Push"
        ) -Wait -PassThru -WindowStyle Hidden
        Assert-True ($failureProcess.ExitCode -ne 0) "Switch helper swallowed a failing nested sync exit code"
    } finally {
        $env:USERPROFILE = $oldProfile
    }

    $launcherFailure = New-Fixture "launcher-failure"
    [IO.File]::WriteAllText((Join-Path $launcherFailure.Kit "Switch-CodexMachine.cmd"), "@exit /b 7`r`n", (New-Object Text.ASCIIEncoding))
    $oldProfile = $env:USERPROFILE
    $oldDesktop = $env:CODEX_DESKTOP_EXE
    $oldSuppress = $env:CODEXKIT_SUPPRESS_FAILURE_POPUP
    $env:USERPROFILE = $launcherFailure.Profile
    $env:CODEX_DESKTOP_EXE = Join-Path $env:WINDIR "System32\notepad.exe"
    $env:CODEXKIT_SUPPRESS_FAILURE_POPUP = "1"
    try {
        $launcherFailureProcess = Start-Process -FilePath powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $launcherFailure.Scripts "Start-CodexWithSync.ps1"), "-NoLaunch"
        ) -Wait -PassThru -WindowStyle Hidden
        Assert-True ($launcherFailureProcess.ExitCode -ne 0) "Managed launcher did not fail closed after Pull failure"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $launcherFailure.Profile ".local\state\codexkit\last-desktop-sync.json"))) "Failed launcher wrote a false sync receipt"
    } finally {
        $env:USERPROFILE = $oldProfile
        $env:CODEX_DESKTOP_EXE = $oldDesktop
        $env:CODEXKIT_SUPPRESS_FAILURE_POPUP = $oldSuppress
    }

    Write-Host "Sync-CodexDesktopState tests passed" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
