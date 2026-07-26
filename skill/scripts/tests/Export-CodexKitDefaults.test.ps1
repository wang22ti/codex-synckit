#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-synckit-defaults-" + [guid]::NewGuid().ToString("N"))
$sourceCodex = Join-Path $testRoot "source\.codex"
$sourceAgents = Join-Path $testRoot "source\.agents"
$sourceMemory = Join-Path $testRoot "source\global-memory"
$defaultDestination = Join-Path $testRoot "default-kit"
$optOutDestination = Join-Path $testRoot "opt-out-kit"
$exporter = Join-Path (Split-Path -Parent $PSScriptRoot) "Export-CodexKit.ps1"
$syncSkillSource = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

try {
    foreach ($directory in @(
        (Join-Path $sourceCodex "sessions\2026\01\01"),
        (Join-Path $sourceCodex "archived_sessions"),
        (Join-Path $sourceCodex "skills"),
        (Join-Path $sourceCodex "skills\memory-and-improvement"),
        (Join-Path $sourceCodex "minimax-skills"),
        (Join-Path $sourceAgents "skills"),
        $sourceMemory
    )) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    Set-Content -LiteralPath (Join-Path $sourceCodex "sessions\2026\01\01\test.jsonl") -Value '{"type":"test"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceCodex "session_index.jsonl") -Value '{"id":"test","title":"Test"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceCodex ".codex-global-state.json") -Value '{"projects":{},"thread-projects":{}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceCodex "skills\memory-and-improvement\SKILL.md") -Value '# memory subsystem fixture' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceMemory "README.md") -Value '# private global memory fixture' -Encoding UTF8
    Copy-Item -LiteralPath $syncSkillSource -Destination (Join-Path $sourceCodex "skills\codexkit-sync") -Recurse

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $sourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $defaultDestination `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "Default export failed with exit code $LASTEXITCODE." }

    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "session-data\sessions\2026\01\01\test.jsonl") -PathType Leaf) "default export should include conversations"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "session-data\session_index.jsonl") -PathType Leaf) "default export should include the title index"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "desktop-state\.codex-global-state.json") -PathType Leaf) "default export should include desktop organization"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "global-memory\README.md") -PathType Leaf) "default export should include the selected memory subsystem data"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "skills\codex-skills\memory-and-improvement\SKILL.md") -PathType Leaf) "default export should include the selected memory subsystem skill"
    $defaultManifest = Get-Content -LiteralPath (Join-Path $defaultDestination "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$defaultManifest.product -eq "codex-synckit") "manifest should identify Codex SyncKit"
    Assert-True ([int]$defaultManifest.manifest_version -eq 1) "manifest should record its schema version"
    Assert-True (@($defaultManifest.files | Where-Object {
        [string]$_.path -eq "Install-CodexKitForWindows.ps1" -and
        [string]$_.sha256 -match '^[0-9A-Fa-f]{64}$'
    }).Count -eq 1) "manifest should record the generated installer hash"
    Assert-True ([bool]$defaultManifest.include_sessions) "manifest should record default session inclusion"
    Assert-True ([bool]$defaultManifest.include_desktop_state) "manifest should record default desktop-state inclusion"
    Assert-True ([bool]$defaultManifest.include_memory_subsystem) "manifest should record memory subsystem inclusion"
    $managedVbsPath = Join-Path $defaultDestination "Start-CodexManaged.vbs"
    $managedVbsBytes = [IO.File]::ReadAllBytes($managedVbsPath)
    Assert-True (-not (
        $managedVbsBytes.Length -ge 3 -and
        $managedVbsBytes[0] -eq 0xEF -and
        $managedVbsBytes[1] -eq 0xBB -and
        $managedVbsBytes[2] -eq 0xBF
    )) "hidden launcher must be UTF-8 without BOM so Windows Script Host can compile it"
    $managedVbs = Get-Content -LiteralPath $managedVbsPath -Raw -Encoding UTF8
    Assert-True ($managedVbs -match 'managed-launch-last\.log') "hidden launcher should retain the last managed-start log"
    Assert-True ($managedVbs -match 'shell\.Popup') "hidden launcher should show a popup when managed startup fails"
    Assert-True ($managedVbs -match 'shell\.Run\(command,\s*0,\s*True\)') "hidden launcher should wait for the managed process and inspect its exit code"
    $compileOutput = & cscript.exe //Nologo $managedVbsPath /CompileTest 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "hidden launcher should compile under Windows Script Host: $($compileOutput -join ' ')"
    foreach ($cmdName in @("Start-CodexManaged.cmd", "Switch-CodexMachine.cmd")) {
        $cmdBytes = [IO.File]::ReadAllBytes((Join-Path $defaultDestination $cmdName))
        Assert-True (-not (
            $cmdBytes.Length -ge 3 -and
            $cmdBytes[0] -eq 0xEF -and
            $cmdBytes[1] -eq 0xBB -and
            $cmdBytes[2] -eq 0xBF
        )) "$cmdName must be UTF-8 without BOM so cmd.exe recognizes its first command"
    }

    $linkedSourceCodex = Join-Path $testRoot "linked-source\.codex"
    $linkedDestination = Join-Path $testRoot "linked-kit"
    $linkedSessions = Join-Path $linkedDestination "session-data\sessions"
    $linkedArchived = Join-Path $linkedDestination "session-data\archived_sessions"
    $linkedIndex = Join-Path $linkedDestination "session-data\session_index.jsonl"
    foreach ($directory in @(
        $linkedSourceCodex,
        (Join-Path $linkedSourceCodex "skills"),
        (Join-Path $linkedSourceCodex "minimax-skills"),
        $linkedSessions,
        $linkedArchived
    )) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $linkedRollout = Join-Path $linkedSessions "linked-session.jsonl"
    [IO.File]::WriteAllText($linkedRollout, "{`"type`":`"session_meta`"}`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($linkedIndex, "{`"id`":`"linked`",`"thread_name`":`"Linked`"}`n", (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath $syncSkillSource -Destination (Join-Path $linkedSourceCodex "skills\codexkit-sync") -Recurse
    cmd /c mklink /J "$(Join-Path $linkedSourceCodex 'sessions')" "$linkedSessions" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create live-linked sessions fixture." }
    cmd /c mklink /J "$(Join-Path $linkedSourceCodex 'archived_sessions')" "$linkedArchived" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create live-linked archived sessions fixture." }
    New-Item -ItemType HardLink -Path (Join-Path $linkedSourceCodex "session_index.jsonl") -Target $linkedIndex | Out-Null
    Set-Content -LiteralPath (Join-Path $linkedSourceCodex ".codex-global-state.json") -Value '{"projects":{},"thread-projects":{}}' -Encoding UTF8
    $linkedRolloutHashBefore = (Get-FileHash -LiteralPath $linkedRollout -Algorithm SHA256).Hash
    $linkedIndexHashBefore = (Get-FileHash -LiteralPath $linkedIndex -Algorithm SHA256).Hash

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $linkedSourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $linkedDestination `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "Live-linked export failed with exit code $LASTEXITCODE." }

    Assert-True ((Get-FileHash -LiteralPath $linkedRollout -Algorithm SHA256).Hash -eq $linkedRolloutHashBefore) "live-linked session export must not rewrite a rollout onto itself"
    Assert-True ((Get-FileHash -LiteralPath $linkedIndex -Algorithm SHA256).Hash -eq $linkedIndexHashBefore) "live-linked session export must not rewrite a hard-linked title index onto itself"
    Assert-True (([IO.File]::ReadAllBytes($linkedRollout))[0] -ne 0) "live-linked rollout must not become zero-prefixed"

    $legacyDocuments = Join-Path $testRoot "legacy-profile\Documents"
    $sharedProjects = Join-Path $defaultDestination "CodexProjects"
    New-Item -ItemType Directory -Force -Path $legacyDocuments, $sharedProjects | Out-Null
    Set-Content -LiteralPath (Join-Path $sharedProjects "existing.txt") -Value "preserved" -Encoding UTF8
    $legacyTarget = Join-Path $legacyDocuments "Codex"
    cmd /c mklink /J "$legacyTarget" "$sharedProjects" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create legacy Junction fixture." }
    $savedUserProfile = $env:USERPROFILE
    try {
        $env:USERPROFILE = Join-Path $testRoot "legacy-profile"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $defaultDestination "Install-CodexKitForWindows.ps1") `
            -KitRoot $defaultDestination `
            -DocumentsRoot $legacyDocuments `
            -InstallCodexProjectsLink `
            -DisableMemorySubsystem
        if ($LASTEXITCODE -ne 0) { throw "Legacy project-workspace migration failed with exit code $LASTEXITCODE." }
    } finally {
        $env:USERPROFILE = $savedUserProfile
    }
    $migratedItem = Get-Item -LiteralPath $legacyTarget -Force
    Assert-True ($migratedItem.PSIsContainer -and [string]::IsNullOrWhiteSpace([string]$migratedItem.LinkType)) "legacy project Junction should become a real directory"
    Assert-True (Test-Path -LiteralPath (Join-Path $legacyTarget "existing.txt") -PathType Leaf) "legacy project data should remain available locally"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $sourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $optOutDestination `
        -ExcludeSessions `
        -ExcludeDesktopState `
        -ExcludeMemorySubsystem `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "Opt-out export failed with exit code $LASTEXITCODE." }

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "session-data\session_index.jsonl") -PathType Leaf)) "session opt-out should omit the title index"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "desktop-state\.codex-global-state.json") -PathType Leaf)) "desktop-state opt-out should omit organization data"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "global-memory") -PathType Container)) "memory opt-out should not create a global-memory directory"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "skills\codex-skills\memory-and-improvement") -PathType Container)) "memory opt-out should omit the memory subsystem skill"
    $optOutManifest = Get-Content -LiteralPath (Join-Path $optOutDestination "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$optOutManifest.include_sessions) "manifest should record session opt-out"
    Assert-True (-not [bool]$optOutManifest.include_desktop_state) "manifest should record desktop-state opt-out"
    Assert-True (-not [bool]$optOutManifest.include_memory_subsystem) "manifest should record memory subsystem opt-out"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $sourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $defaultDestination `
        -ExcludeSessions `
        -ExcludeDesktopState `
        -ExcludeMemorySubsystem `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "In-place opt-out export failed with exit code $LASTEXITCODE." }

    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "session-data\sessions\2026\01\01\test.jsonl") -PathType Leaf) "stale cleanup must never delete existing conversations"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "desktop-state\.codex-global-state.json") -PathType Leaf) "stale cleanup must never delete existing desktop organization"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "global-memory\README.md") -PathType Leaf) "memory opt-out must never delete existing private memory"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "skills\codex-skills\memory-and-improvement\SKILL.md") -PathType Leaf) "memory opt-out must not delete a previously installed subsystem copy"

    Write-Host "[OK] default continuity export, memory selection, and explicit opt-outs passed" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test path outside the temp directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
