#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DestinationRoot,
    [switch]$Recommended,
    [switch]$IncludeSessions,
    [switch]$IncludeDesktopState,
    [switch]$ExcludeSessions,
    [switch]$ExcludeDesktopState,
    [switch]$InstallSessionLinks,
    [switch]$InstallMemorySubsystem,
    [switch]$SkipMemorySubsystem,
    # Retained for compatibility with earlier alpha commands. The private-data
    # boundary is now documented rather than gated because continuity is on by default.
    [switch]$AcceptPrivateDataRisk,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($InstallMemorySubsystem -and $SkipMemorySubsystem) {
    throw "Choose either -InstallMemorySubsystem or -SkipMemorySubsystem, not both."
}
if ($IncludeSessions -and $ExcludeSessions) {
    throw "Choose either -IncludeSessions or -ExcludeSessions, not both."
}
if ($IncludeDesktopState -and $ExcludeDesktopState) {
    throw "Choose either -IncludeDesktopState or -ExcludeDesktopState, not both."
}

# Conversation continuity and sidebar organization are core SyncKit features.
# Keep the older Include switches for compatibility, while making both data
# categories part of the normal setup unless the user explicitly opts out.
if (-not $PSBoundParameters.ContainsKey("IncludeSessions")) {
    $IncludeSessions = -not $ExcludeSessions
}
if (-not $PSBoundParameters.ContainsKey("IncludeDesktopState")) {
    $IncludeDesktopState = -not $ExcludeDesktopState
}
if ($Recommended -and $IncludeSessions) {
    $InstallSessionLinks = $true
}

function Read-RequiredMemorySubsystemChoice {
    while ($true) {
        $answer = (Read-Host "Install the optional long-term memory subsystem? Enter Y or N; there is no default").Trim()
        switch -Regex ($answer) {
            '^(?i:y|yes)$' { return $true }
            '^(?i:n|no)$' { return $false }
            default { Write-Host "Please enter Y or N. Pressing Enter alone does not select an option." -ForegroundColor Yellow }
        }
    }
}

$memorySubsystemEnabled = if ($InstallMemorySubsystem) {
    $true
} elseif ($SkipMemorySubsystem) {
    $false
} else {
    Read-RequiredMemorySubsystemChoice
}

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

if ($InstallSessionLinks -and -not $IncludeSessions) {
    throw "-InstallSessionLinks requires -IncludeSessions."
}
$sourceSkill = Join-Path $PSScriptRoot "skill"
$sourceExporter = Join-Path $sourceSkill "scripts\Export-CodexKit.ps1"
$sourceMemorySubsystem = Join-Path $PSScriptRoot "subsystems\memory-and-improvement"
if (-not (Test-Path -LiteralPath $sourceExporter -PathType Leaf)) {
    throw "The release is incomplete: missing skill\scripts\Export-CodexKit.ps1."
}
if ($memorySubsystemEnabled -and -not (Test-Path -LiteralPath (Join-Path $sourceMemorySubsystem "SKILL.md") -PathType Leaf)) {
    throw "The release is incomplete: missing subsystems\memory-and-improvement\SKILL.md."
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

    if ($memorySubsystemEnabled) {
        $targetMemorySkill = Join-Path $skillParent "memory-and-improvement"
        $memoryBackup = $null
        if (Test-Path -LiteralPath $targetMemorySkill) {
            if (Test-TreesEqual -Left $sourceMemorySubsystem -Right $targetMemorySkill) {
                Write-Host "[OK] memory-and-improvement subsystem is already current" -ForegroundColor Green
            } else {
                if (-not $Force) {
                    throw "A different memory-and-improvement skill already exists at $targetMemorySkill. Review it, then rerun with -Force to create a backup and replace it."
                }
                $memoryBackup = "$targetMemorySkill.backup.$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
                Move-Item -LiteralPath $targetMemorySkill -Destination $memoryBackup
                Write-Host "Backed up existing memory subsystem: $memoryBackup" -ForegroundColor Yellow
            }
        }

        if (-not (Test-Path -LiteralPath $targetMemorySkill)) {
            try {
                New-Item -ItemType Directory -Force -Path $targetMemorySkill | Out-Null
                foreach ($child in @(Get-ChildItem -LiteralPath $sourceMemorySubsystem -Force)) {
                    Copy-Item -LiteralPath $child.FullName -Destination $targetMemorySkill -Recurse -Force
                }
            } catch {
                if (Test-Path -LiteralPath $targetMemorySkill) {
                    Remove-Item -LiteralPath $targetMemorySkill -Recurse -Force
                }
                if ($memoryBackup -and (Test-Path -LiteralPath $memoryBackup)) {
                    Move-Item -LiteralPath $memoryBackup -Destination $targetMemorySkill
                }
                throw
            }
            if (-not (Test-TreesEqual -Left $sourceMemorySubsystem -Right $targetMemorySkill)) {
                throw "Installed memory subsystem verification failed: $targetMemorySkill"
            }
            Write-Host "[OK] installed long-term memory subsystem: $targetMemorySkill" -ForegroundColor Green
        }
    } else {
        Write-Host "[SKIP] long-term memory subsystem was not added" -ForegroundColor DarkGray
    }
} elseif ($memorySubsystemEnabled) {
    Write-Host "[DRY] would install the bundled memory-and-improvement subsystem" -ForegroundColor DarkCyan
} else {
    Write-Host "[DRY] long-term memory subsystem was explicitly skipped" -ForegroundColor DarkCyan
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
if ($ExcludeSessions) { $exportArguments += "-ExcludeSessions" }
if ($ExcludeDesktopState) { $exportArguments += "-ExcludeDesktopState" }
if ($memorySubsystemEnabled) { $exportArguments += "-IncludeMemorySubsystem" }
else { $exportArguments += "-ExcludeMemorySubsystem" }
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
    if ($memorySubsystemEnabled) { $installArguments += "-EnableMemorySubsystem" }
    else { $installArguments += "-DisableMemorySubsystem" }
    & powershell.exe @installArguments
    if ($LASTEXITCODE -ne 0) { throw "Recommended installation failed with exit code $LASTEXITCODE." }
}

Write-Host "Codex SyncKit setup complete." -ForegroundColor Green
Write-Host "Private kit: $DestinationRoot"
Write-Host "Long-term memory subsystem: $(if ($memorySubsystemEnabled) { 'installed' } else { 'not added' })"
