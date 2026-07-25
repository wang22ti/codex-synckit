#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Sync-CodexProjectWorkspaces.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-project-sync-" + [guid]::NewGuid().ToString("N"))
$local = Join-Path $testRoot "local"
$shared = Join-Path $testRoot "shared"
$baseline = Join-Path $testRoot "state\baseline.json"

try {
    New-Item -ItemType Directory -Force -Path $local, $shared | Out-Null
    Set-Content -LiteralPath (Join-Path $shared "shared.txt") -Value "shared" -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Pull -LocalRoot $local -SharedRoot $shared -BaselinePath $baseline
    if ($LASTEXITCODE -ne 0) { throw "Initial pull failed." }
    Assert-True (Test-Path -LiteralPath (Join-Path $local "shared.txt") -PathType Leaf) "pull should copy shared-only files"

    Set-Content -LiteralPath (Join-Path $local "local.txt") -Value "local" -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Push -LocalRoot $local -SharedRoot $shared -BaselinePath $baseline
    if ($LASTEXITCODE -ne 0) { throw "Push failed." }
    Assert-True (Test-Path -LiteralPath (Join-Path $shared "local.txt") -PathType Leaf) "push should copy local-only files"

    Set-Content -LiteralPath (Join-Path $shared "shared.txt") -Value "remote update" -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Pull -LocalRoot $local -SharedRoot $shared -BaselinePath $baseline
    if ($LASTEXITCODE -ne 0) { throw "Update pull failed." }
    Assert-True ((Get-Content -LiteralPath (Join-Path $local "shared.txt") -Raw) -match "remote update") "pull should install a one-sided remote update"

    Set-Content -LiteralPath (Join-Path $local "shared.txt") -Value "local conflict" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $shared "shared.txt") -Value "remote conflict" -Encoding UTF8
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Pull -LocalRoot $local -SharedRoot $shared -BaselinePath $baseline 2>&1
        $conflictExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($conflictExitCode -ne 0) "two-sided edits should stop before overwrite"
    Assert-True ((Get-Content -LiteralPath (Join-Path $local "shared.txt") -Raw) -match "local conflict") "conflict must preserve local data"
    Assert-True ((Get-Content -LiteralPath (Join-Path $shared "shared.txt") -Raw) -match "remote conflict") "conflict must preserve shared data"

    Write-Host "[OK] project workspace directional sync tests passed" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test path outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
