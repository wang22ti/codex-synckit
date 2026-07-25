$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Text, [string]$Needle)
    if (-not $Text.Contains($Needle)) {
        throw "Expected output to contain: $Needle"
    }
}

$skillDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installer = Join-Path $skillDir 'scripts\maintenance\install-windows-maintenance.ps1'
$runner = Join-Path $skillDir 'scripts\maintenance\run-windows-maintenance.ps1'
$bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'

if (-not (Test-Path -LiteralPath $bash)) {
    throw 'Git Bash is required for the Windows maintenance test.'
}

$preview = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
    -Mode interval `
    -Scope both `
    -IntervalMinutes 90 `
    -ProjectRoot $env:TEMP `
    -BashPath $bash
if ($LASTEXITCODE -ne 0) {
    throw 'Windows maintenance installer preview failed.'
}
$previewText = $preview -join "`n"
$previewObject = $previewText | ConvertFrom-Json
if ($previewObject.mode -ne 'interval') { throw 'Expected interval preview mode.' }
if ($previewObject.scope -ne 'both') { throw 'Expected both preview scope.' }
if ($previewObject.interval_minutes -ne 90) { throw 'Expected 90 minute preview interval.' }
Assert-Contains $previewText 'run-windows-maintenance.ps1'
Assert-Contains $previewText 'wscript.exe'
Assert-Contains $previewText 'run-windows-maintenance-hidden.vbs'
Assert-Contains (Get-Content -LiteralPath $installer -Raw) 'New-ScheduledTaskTrigger'
Assert-Contains (Get-Content -LiteralPath $installer -Raw) '-AtLogOn'

$tempRoot = Join-Path $env:TEMP ('memory-windows-test-' + [guid]::NewGuid().ToString('N'))
$fakeBash = Join-Path $tempRoot 'fake-bash.cmd'
$stateRoot = Join-Path $tempRoot 'state'
$captureFile = Join-Path $tempRoot 'captured.txt'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    @"
@echo off
echo -lc %* > "$captureFile"
exit /b 0
"@ | Set-Content -LiteralPath $fakeBash -Encoding ascii

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
        -Scope both `
        -Mode interval `
        -ProjectRoot $tempRoot `
        -Namespace research-principle `
        -GlobalRoot (Join-Path $tempRoot 'global-memory') `
        -GlobalNamespacesRoot (Join-Path $tempRoot 'global-memory\namespaces') `
        -StateRoot $stateRoot `
        -BashPath $fakeBash `
        -IntervalMinutes 90 `
        -GitCommit false `
        -Writeback false `
        -SkillPolicyWriteback false `
        -MinRecurrence 2
    if ($LASTEXITCODE -ne 0) {
        throw 'Windows maintenance runner failed.'
    }

    $captured = Get-Content -LiteralPath $captureFile -Raw
    Assert-Contains $captured 'interval-maintenance.sh'
    Assert-Contains $captured '--interval-minutes'
    Assert-Contains $captured '--scope'
    Assert-Contains $captured "'90'"
    Assert-Contains $captured "'both'"

    $logFile = Join-Path $stateRoot 'logs\windows-maintenance.log'
    if (-not (Test-Path -LiteralPath $logFile)) {
        throw 'Expected Windows maintenance log file to be created.'
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'windows-maintenance assertions passed'
