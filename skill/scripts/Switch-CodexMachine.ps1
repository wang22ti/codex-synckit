param(
    [ValidateSet("Push", "Pull", "Sync", "Status")]
    [string]$Action,
    [switch]$SkipRepair,
    [int]$BackupRetention = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot
$KitRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptRoot "..\..\..\..")).Path
$DesktopStateScript = Join-Path $ScriptRoot "Sync-CodexDesktopState.ps1"
$ProjectWorkspaceScript = Join-Path $ScriptRoot "Sync-CodexProjectWorkspaces.ps1"
$InstallerScript = Join-Path $KitRoot "Install-CodexKitForWindows.ps1"
$InstallState = Join-Path $env:USERPROFILE ".local\state\codexkit\installation.json"

function Invoke-Step($Title, [scriptblock]$ScriptBlock) {
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw "$Title failed with exit code $LASTEXITCODE."
    }
}

function Resolve-Action {
    if ($Action) { return $Action }

    Write-Host "CodexKit machine switch helper" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Push  - publish this machine's organization after closing ChatGPT"
    Write-Host "2. Pull  - install the shared primary organization before opening ChatGPT"
    Write-Host "3. Sync  - explicitly three-way merge local and shared organization"
    Write-Host "4. Status - check links and desktop-state timestamps"
    Write-Host ""
    $choice = Read-Host "Choose 1, 2, 3, or 4"
    switch ($choice.Trim()) {
        "1" { return "Push" }
        "2" { return "Pull" }
        "3" { return "Sync" }
        "4" { return "Status" }
        default { throw "Unknown choice: $choice" }
    }
}

function Test-ProjectWorkspaceSyncEnabled {
    if (-not (Test-Path -LiteralPath $InstallState -PathType Leaf)) { return $false }
    try {
        $state = Get-Content -LiteralPath $InstallState -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.PSObject.Properties.Name -contains "codex_projects_sync_enabled") {
            return [bool]$state.codex_projects_sync_enabled
        }
        if ($state.PSObject.Properties.Name -contains "codex_projects_link_enabled") {
            return [bool]$state.codex_projects_link_enabled
        }
    } catch {
        throw "Could not read project workspace sync state: $InstallState"
    }
    return $false
}

function Invoke-ProjectWorkspaceSync([ValidateSet("Pull", "Push")][string]$Mode) {
    if (-not (Test-ProjectWorkspaceSyncEnabled)) { return }
    $legacyRoot = Join-Path $env:USERPROFILE "Documents\Codex"
    $legacyItem = Get-Item -LiteralPath $legacyRoot -Force -ErrorAction SilentlyContinue
    if ($Mode -eq "Push" -and $legacyItem -and
        -not [string]::IsNullOrWhiteSpace([string]$legacyItem.LinkType)) {
        Write-Host "Legacy project Junction is still active; converting it now that ChatGPT is closed." -ForegroundColor Yellow
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Repair -InstallSessionLinks
        if ($LASTEXITCODE -ne 0) {
            throw "Legacy project Junction migration failed with exit code $LASTEXITCODE."
        }
        return
    }
    if (-not (Test-Path -LiteralPath $ProjectWorkspaceScript -PathType Leaf)) {
        throw "Missing project workspace sync helper: $ProjectWorkspaceScript"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ProjectWorkspaceScript "-$Mode"
}

if (-not (Test-Path -LiteralPath $DesktopStateScript -PathType Leaf)) {
    throw "Missing helper script: $DesktopStateScript"
}
if (-not (Test-Path -LiteralPath $InstallerScript -PathType Leaf)) {
    throw "Missing installer script: $InstallerScript"
}

$selectedAction = Resolve-Action

switch ($selectedAction) {
    "Push" {
        Invoke-Step "Publish local projectless workspaces to OneDrive" {
            Invoke-ProjectWorkspaceSync -Mode Push
        }
        Invoke-Step "Publish local task/sidebar organization to OneDrive" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DesktopStateScript -Push -BackupRetention $BackupRetention
        }
        Invoke-Step "Show desktop-state sync status" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DesktopStateScript -Status
        }
        Write-Host ""
        Write-Host "Now wait for OneDrive to finish syncing. This machine's organization is the shared primary." -ForegroundColor Yellow
    }
    "Pull" {
        if (-not $SkipRepair) {
            Invoke-Step "Repair live session links" {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Repair -InstallSessionLinks
            }
        }
        Invoke-Step "Install shared projectless workspaces locally" {
            Invoke-ProjectWorkspaceSync -Mode Pull
        }
        Invoke-Step "Install shared primary task/sidebar organization locally" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DesktopStateScript -Pull -BackupRetention $BackupRetention
        }
        Invoke-Step "Show CodexKit link status" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Status
        }
        Write-Host ""
        Write-Host "You can open Codex after OneDrive shows this folder is up to date." -ForegroundColor Green
    }
    "Sync" {
        if (-not $SkipRepair) {
            Invoke-Step "Repair live session links" {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Repair -InstallSessionLinks
            }
        }
        Invoke-Step "Reconcile projectless workspaces with OneDrive" {
            Invoke-ProjectWorkspaceSync -Mode Pull
            Invoke-ProjectWorkspaceSync -Mode Push
        }
        Invoke-Step "Three-way merge task/sidebar changes with OneDrive" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DesktopStateScript -Merge -BackupRetention $BackupRetention
        }
        Invoke-Step "Show CodexKit link status" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Status
        }
        Write-Host "Task/sidebar organization is reconciled. Every Managed machine may publish changes." -ForegroundColor Green
    }
    "Status" {
        if (Test-ProjectWorkspaceSyncEnabled) {
            Invoke-Step "Show project workspace sync status" {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ProjectWorkspaceScript -Status
            }
        }
        Invoke-Step "Show desktop-state sync status" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DesktopStateScript -Status
        }
        Invoke-Step "Show CodexKit link status" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -Status
        }
    }
}
