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
    [ValidateSet("Auto", "Initialize", "Join")]
    [string]$KitMode = "Auto",
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

function Resolve-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-OneDriveRoot {
    foreach ($candidate in @($env:OneDriveCommercial, $env:OneDriveConsumer, $env:OneDrive)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return $candidate }
    }
    return (Join-Path $env:USERPROFILE "OneDrive")
}

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path (Get-OneDriveRoot) "CodexKit"
}
$DestinationRoot = Resolve-FullPath $DestinationRoot

if (Test-Path -LiteralPath $DestinationRoot -PathType Leaf) {
    throw "CodexKit destination is a file, not a directory: $DestinationRoot"
}

$manifestPath = Join-Path $DestinationRoot "manifest.json"
$generatedInstaller = Join-Path $DestinationRoot "Install-CodexKitForWindows.ps1"
$destinationExists = Test-Path -LiteralPath $DestinationRoot -PathType Container
$destinationHasEntries = $destinationExists -and
    (@(Get-ChildItem -LiteralPath $DestinationRoot -Force).Count -gt 0)
$hasManifest = Test-Path -LiteralPath $manifestPath -PathType Leaf
$existingManifest = $null

if ($hasManifest) {
    try {
        $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Existing CodexKit manifest is unreadable: $manifestPath. Refusing to modify the shared directory."
    }
}

function Assert-ExistingKitInstallerIntegrity {
    $manifestProperties = @($existingManifest.PSObject.Properties.Name)
    $hasProductIdentity = $manifestProperties -contains "product" -or
        $manifestProperties -contains "manifest_version"
    if ($hasProductIdentity) {
        if ($manifestProperties -notcontains "product" -or
            $manifestProperties -notcontains "manifest_version" -or
            [string]$existingManifest.product -ne "codex-synckit" -or
            [int]$existingManifest.manifest_version -ne 1) {
            throw "Existing manifest is not a supported Codex SyncKit manifest. Re-export it with the current release before joining."
        }
    } else {
        Write-Host "[INFO] legacy CodexKit manifest detected; installer hash verification is still required" -ForegroundColor DarkCyan
    }
    if ($manifestProperties -notcontains "files") {
        throw "Existing CodexKit manifest does not contain file integrity records. Re-export it before joining."
    }
    $installerEntry = @($existingManifest.files | Where-Object {
        ([string]$_.path).Replace('/', '\').TrimStart('\').Equals(
            "Install-CodexKitForWindows.ps1",
            [StringComparison]::OrdinalIgnoreCase
        )
    } | Select-Object -First 1)
    if ($installerEntry.Count -ne 1) {
        throw "Existing CodexKit manifest does not contain an installer integrity record. Re-export it before joining."
    }
    $expectedHash = [string]$installerEntry[0].sha256
    if ($expectedHash -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Existing CodexKit installer integrity record is invalid. Refusing to execute the shared installer."
    }
    $actualHash = (Get-FileHash -LiteralPath $generatedInstaller -Algorithm SHA256).Hash
    if (-not $actualHash.Equals($expectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Existing CodexKit installer does not match manifest.json. Refusing to execute a changed shared installer."
    }
}

$resolvedKitMode = switch ($KitMode) {
    "Join" {
        if (-not $hasManifest) {
            throw "-KitMode Join requires an existing CodexKit manifest: $manifestPath"
        }
        "Join"
    }
    "Initialize" {
        if ($destinationHasEntries) {
            throw "-KitMode Initialize requires a new or empty destination. Move or rename the existing directory first: $DestinationRoot"
        }
        "Initialize"
    }
    default {
        if ($hasManifest) {
            "Join"
        } elseif ($destinationHasEntries) {
            throw "The destination is not empty and has no CodexKit manifest. Refusing to guess or overwrite it: $DestinationRoot"
        } else {
            "Initialize"
        }
    }
}

if ($resolvedKitMode -eq "Join" -and
    -not (Test-Path -LiteralPath $generatedInstaller -PathType Leaf)) {
    throw "Existing CodexKit is incomplete: missing installer $generatedInstaller. Refusing to export local state over it."
}
if ($resolvedKitMode -eq "Join") {
    Assert-ExistingKitInstallerIntegrity
}

$memorySubsystemEnabled = if ($InstallMemorySubsystem) {
    $true
} elseif ($SkipMemorySubsystem) {
    $false
} else {
    Read-RequiredMemorySubsystemChoice
}

if ($resolvedKitMode -eq "Join") {
    $sharedMemoryEnabled = if ($existingManifest.PSObject.Properties.Name -contains "include_memory_subsystem") {
        [bool]$existingManifest.include_memory_subsystem
    } else {
        (Test-Path -LiteralPath (Join-Path $DestinationRoot "global-memory") -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\codex-skills\memory-and-improvement") -PathType Container)
    }
    if ($memorySubsystemEnabled -and -not $sharedMemoryEnabled) {
        throw "The existing CodexKit was created without the memory subsystem. Joining must not modify shared data. Choose N, or enable memory from the machine that owns the shared Kit."
    }
    if (-not $memorySubsystemEnabled -and $sharedMemoryEnabled) {
        Write-Host "[INFO] shared memory data exists; it will remain untouched and local memory integration will stay disabled" -ForegroundColor DarkCyan
    }
}

Write-Host "CodexKit setup mode: $resolvedKitMode" -ForegroundColor Cyan

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

if ($resolvedKitMode -eq "Initialize") {
    $exporter = if ($DryRun) { $sourceExporter } else { Join-Path $targetSkill "scripts\Export-CodexKit.ps1" }
    $exportArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $exporter,
        "-DestinationRoot", $DestinationRoot
    )
    if ($IncludeSessions) { $exportArguments += "-IncludeSessions" }
    if ($IncludeDesktopState) { $exportArguments += "-IncludeDesktopState" }
    if ($ExcludeSessions) { $exportArguments += "-ExcludeSessions" }
    if ($ExcludeDesktopState) { $exportArguments += "-ExcludeDesktopState" }
    if ($memorySubsystemEnabled) { $exportArguments += "-IncludeMemorySubsystem" }
    else { $exportArguments += "-ExcludeMemorySubsystem" }
    if ($DryRun) { $exportArguments += "-DryRun" }

    & powershell.exe @exportArguments
    if ($LASTEXITCODE -ne 0) { throw "CodexKit initialization failed with exit code $LASTEXITCODE." }
} else {
    Write-Host "[JOIN] existing shared CodexKit detected" -ForegroundColor Green
    Write-Host "[JOIN] local sessions, sidebar state, skills, and memory will not be exported over shared data" -ForegroundColor Green
}

if ($DryRun) {
    Write-Host "Dry run complete. No skill or CodexKit files were changed." -ForegroundColor Cyan
    exit 0
}

if ($Recommended) {
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
