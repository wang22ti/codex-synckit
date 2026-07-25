#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DestinationRoot,
    [switch]$Recommended,
    [switch]$IncludeSessions,
    [switch]$IncludeDesktopState,
    [switch]$InstallSessionLinks,
    [switch]$AcceptPrivateDataRisk,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-OneDriveRoot {
    foreach ($candidate in @($env:OneDriveCommercial, $env:OneDriveConsumer, $env:OneDrive)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return $candidate }
    }
    return (Join-Path $env:USERPROFILE "OneDrive")
}

function Get-TreeFingerprint([string]$Path) {
    $root = Resolve-FullPath $Path
    return @(
        Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($root.Length).TrimStart('\')
                "$relative`t$($_.Length)`t$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            }
    )
}

function Test-TreesEqual([string]$Left, [string]$Right) {
    if (-not (Test-Path -LiteralPath $Left -PathType Container) -or
        -not (Test-Path -LiteralPath $Right -PathType Container)) { return $false }
    return ((Get-TreeFingerprint $Left) -join "`n") -eq ((Get-TreeFingerprint $Right) -join "`n")
}

if (($IncludeSessions -or $IncludeDesktopState -or $InstallSessionLinks) -and -not $AcceptPrivateDataRisk) {
    throw "Private-data features require -AcceptPrivateDataRisk. Review docs\PRIVACY.md first."
}
if ($InstallSessionLinks -and -not $IncludeSessions) {
    throw "-InstallSessionLinks requires -IncludeSessions."
}
if ($DryRun -and $Recommended) {
    throw "-DryRun cannot be combined with -Recommended."
}

$sourceSkill = Join-Path $PSScriptRoot "skill"
$sourceExporter = Join-Path $sourceSkill "scripts\Export-CodexKit.ps1"
if (-not (Test-Path -LiteralPath $sourceExporter -PathType Leaf)) {
    throw "The release is incomplete: missing skill\scripts\Export-CodexKit.ps1."
}

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$skillParent = Join-Path $codexHome "skills"
$targetSkill = Join-Path $skillParent "codexkit-sync"
$backup = $null

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $skillParent | Out-Null
    if (Test-Path -LiteralPath $targetSkill) {
        if (Test-TreesEqual -Left $sourceSkill -Right $targetSkill) {
            Write-Host "[OK] codexkit-sync skill is already current" -ForegroundColor Green
        } else {
            if (-not $Force) {
                throw "A different codexkit-sync skill already exists at $targetSkill. Review it, then rerun with -Force to create a backup and replace it."
            }
            $backup = "$targetSkill.backup.$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
            Move-Item -LiteralPath $targetSkill -Destination $backup
            Write-Host "Backed up existing skill: $backup" -ForegroundColor Yellow
        }
    }

    if (-not (Test-Path -LiteralPath $targetSkill)) {
        try {
            New-Item -ItemType Directory -Force -Path $targetSkill | Out-Null
            foreach ($child in @(Get-ChildItem -LiteralPath $sourceSkill -Force)) {
                Copy-Item -LiteralPath $child.FullName -Destination $targetSkill -Recurse -Force
            }
        } catch {
            if (Test-Path -LiteralPath $targetSkill) {
                Remove-Item -LiteralPath $targetSkill -Recurse -Force
            }
            if ($backup -and (Test-Path -LiteralPath $backup)) {
                Move-Item -LiteralPath $backup -Destination $targetSkill
            }
            throw
        }
        if (-not (Test-TreesEqual -Left $sourceSkill -Right $targetSkill)) {
            throw "Installed skill verification failed: $targetSkill"
        }
        Write-Host "[OK] installed codexkit-sync skill: $targetSkill" -ForegroundColor Green
    }
}

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path (Get-OneDriveRoot) "CodexKit"
}
$exporter = if ($DryRun) { $sourceExporter } else { Join-Path $targetSkill "scripts\Export-CodexKit.ps1" }
$exportArguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $exporter,
    "-DestinationRoot", $DestinationRoot, "-Force"
)
if ($IncludeSessions) { $exportArguments += "-IncludeSessions" }
if ($IncludeDesktopState) { $exportArguments += "-IncludeDesktopState" }
if ($DryRun) { $exportArguments += "-DryRun" }

& powershell.exe @exportArguments
if ($LASTEXITCODE -ne 0) { throw "CodexKit export failed with exit code $LASTEXITCODE." }

if ($DryRun) {
    Write-Host "Dry run complete. No skill or CodexKit files were changed." -ForegroundColor Cyan
    exit 0
}

if ($Recommended) {
    $generatedInstaller = Join-Path $DestinationRoot "Install-CodexKitForWindows.ps1"
    if (-not (Test-Path -LiteralPath $generatedInstaller -PathType Leaf)) {
        throw "Generated installer is missing: $generatedInstaller"
    }
    $installArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $generatedInstaller,
        "-KitRoot", $DestinationRoot, "-Recommended"
    )
    if ($InstallSessionLinks) { $installArguments += "-InstallSessionLinks" }
    & powershell.exe @installArguments
    if ($LASTEXITCODE -ne 0) { throw "Recommended installation failed with exit code $LASTEXITCODE." }
}

Write-Host "CodexKit Sync setup complete." -ForegroundColor Green
Write-Host "Private kit: $DestinationRoot"
