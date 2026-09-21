#requires -version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Elevate,
    [switch]$RestartOneDrive
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreFolderListFromGPO'
$names = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'OneDriveExcludedFolders.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$protected = @('.git', '.codex', '.learnings', 'sessions', 'archived_sessions', 'session-data', 'tmp', 'temp', 'build', 'dist', 'output', 'assets', 'logs')
foreach ($name in $names) {
    if ($name -notmatch '^[a-zA-Z0-9_.-]+$' -or $name -in @('.', '..') -or $name -in $protected) {
        throw "Unsafe global folder exclusion: $name"
    }
}
function Get-MissingNames {
    $key = Get-Item -LiteralPath $policyPath -ErrorAction SilentlyContinue
    $values = @()
    if ($key) { $values = @($key.GetValueNames() | ForEach-Object { $key.GetValue($_) }) }
    return @($names | Where-Object { $_ -notin $values })
}
function Add-MissingFolderValues([string]$Path, [string[]]$Names) {
    # New-Item -Force on an existing registry key clears its values in Windows
    # PowerShell 5.1. Never recreate an existing policy key.
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path | Out-Null }
    foreach ($name in $Names) {
        $key = Get-Item -LiteralPath $Path
        $values = @($key.GetValueNames() | ForEach-Object { $key.GetValue($_) })
        if ($name -in $values) { continue }
        $valueName = $name
        $index = 0
        while ($null -ne $key.GetValue($valueName)) {
            $index++; $valueName = "CodexKit-$name-$index"
        }
        New-ItemProperty -LiteralPath $Path -Name $valueName -Value $name -PropertyType String | Out-Null
    }
}
function Restart-NormalOneDrive {
    if (-not $RestartOneDrive) { return }
    $session = (Get-Process -Id $PID).SessionId
    $running = @(Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
    if (-not $running.Count) { return }
    $exe = $running[0].Path
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { throw 'Cannot locate running OneDrive executable for restart.' }
    & $exe /shutdown
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (-not @(Get-Process -Id $running.Id -ErrorAction SilentlyContinue).Count) { break }
        Start-Sleep -Milliseconds 500
    }
    if (@(Get-Process -Id $running.Id -ErrorAction SilentlyContinue).Count) {
        throw 'OneDrive did not shut down gracefully. Restart it manually to load the policy.'
    }
    Start-Process -FilePath $exe -ArgumentList '/background' -WindowStyle Hidden | Out-Null
    Write-Host '[OK] OneDrive restarted in the normal Windows session.'
}
$missing = @(Get-MissingNames)
if (-not $missing.Count) {
    Write-Host "[OK] OneDrive folder exclusions: all $($names.Count) configured (machine policy)."
    return
}
if (-not $Apply) {
    Write-Host "[MISSING] OneDrive folder exclusions: $($missing -join ', ')"
    return
}
# Check the installed policy template before changing a machine's registry.
$supported = $false
foreach ($root in @((Join-Path $env:ProgramFiles 'Microsoft OneDrive'), (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'))) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($version in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $template = Join-Path $version.FullName 'adm\OneDrive.admx'
        if ((Test-Path -LiteralPath $template) -and
            ([IO.File]::ReadAllText($template).Contains('EnableODIgnoreFolderListFromGPO'))) { $supported = $true; break }
    }
}
if (-not $supported) {
    throw 'Installed OneDrive folder-exclusion policy support was not found. Update OneDrive, then retry.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (-not $Elevate) { throw 'Machine policy requires an administrator. Run with -Apply -Elevate to request Windows UAC.' }
    Write-Host 'Requesting Windows UAC to add OneDrive dependency/cache exclusions for this machine.'
    $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Apply'
    )
    if (-not $child.WaitForExit(120000)) {
        throw 'The elevated OneDrive policy helper has not completed after two minutes. Check the Windows UAC prompt; do not launch a duplicate installer.'
    }
    if (@(Get-MissingNames).Count) { throw 'OneDrive policy verification failed after elevation. Check the policy backup and elevated helper result before retrying.' }
    Write-Host '[OK] OneDrive exclusions installed. Existing cloud content is not removed.'
    Restart-NormalOneDrive
    if (-not $RestartOneDrive) { Write-Host '[INFO] Restart OneDrive to load the policy.' }
    return
}
# Back up exact previous values/types locally. Add only missing values; preserve custom policy.
$backupRoot = Join-Path $env:LOCALAPPDATA 'CodexKit\onedrive-policy-backups'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$key = Get-Item -LiteralPath $policyPath -ErrorAction SilentlyContinue
$before = @()
if ($key) {
    $before = @($key.GetValueNames() | ForEach-Object {
        [ordered]@{ name = $_; kind = [string]$key.GetValueKind($_); value = $key.GetValue($_) }
    })
}
$backup = Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.json')
[ordered]@{ path = $policyPath; existed = [bool]$key; values = $before; requested = $names } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backup -Encoding UTF8
Add-MissingFolderValues -Path $policyPath -Names $missing
if (@(Get-MissingNames).Count) { throw 'OneDrive exclusion read-back verification failed.' }
Write-Host "[OK] Added $($missing.Count) OneDrive folder exclusions. Backup: $backup"
Write-Host '[INFO] Restart OneDrive normally. Existing cloud content is not removed by this policy.'
