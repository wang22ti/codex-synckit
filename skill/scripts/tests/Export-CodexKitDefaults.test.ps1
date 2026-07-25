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

try {
    foreach ($directory in @(
        (Join-Path $sourceCodex "sessions\2026\01\01"),
        (Join-Path $sourceCodex "archived_sessions"),
        (Join-Path $sourceCodex "skills"),
        (Join-Path $sourceCodex "minimax-skills"),
        (Join-Path $sourceAgents "skills"),
        $sourceMemory
    )) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    Set-Content -LiteralPath (Join-Path $sourceCodex "sessions\2026\01\01\test.jsonl") -Value '{"type":"test"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceCodex "session_index.jsonl") -Value '{"id":"test","title":"Test"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceCodex ".codex-global-state.json") -Value '{"projects":{},"thread-projects":{}}' -Encoding UTF8

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
    $defaultManifest = Get-Content -LiteralPath (Join-Path $defaultDestination "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$defaultManifest.include_sessions) "manifest should record default session inclusion"
    Assert-True ([bool]$defaultManifest.include_desktop_state) "manifest should record default desktop-state inclusion"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $sourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $optOutDestination `
        -ExcludeSessions `
        -ExcludeDesktopState `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "Opt-out export failed with exit code $LASTEXITCODE." }

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "session-data\session_index.jsonl") -PathType Leaf)) "session opt-out should omit the title index"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $optOutDestination "desktop-state\.codex-global-state.json") -PathType Leaf)) "desktop-state opt-out should omit organization data"
    $optOutManifest = Get-Content -LiteralPath (Join-Path $optOutDestination "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$optOutManifest.include_sessions) "manifest should record session opt-out"
    Assert-True (-not [bool]$optOutManifest.include_desktop_state) "manifest should record desktop-state opt-out"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter `
        -SourceCodexHome $sourceCodex `
        -SourceAgentsRoot $sourceAgents `
        -SourceGlobalMemory $sourceMemory `
        -DestinationRoot $defaultDestination `
        -ExcludeSessions `
        -ExcludeDesktopState `
        -Force
    if ($LASTEXITCODE -ne 0) { throw "In-place opt-out export failed with exit code $LASTEXITCODE." }

    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "session-data\sessions\2026\01\01\test.jsonl") -PathType Leaf) "stale cleanup must never delete existing conversations"
    Assert-True (Test-Path -LiteralPath (Join-Path $defaultDestination "desktop-state\.codex-global-state.json") -PathType Leaf) "stale cleanup must never delete existing desktop organization"

    Write-Host "[OK] default continuity export and explicit opt-outs passed" -ForegroundColor Green
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
