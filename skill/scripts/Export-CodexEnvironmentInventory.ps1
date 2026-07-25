#requires -version 5.1
[CmdletBinding()]
param(
    [string]$KitRoot,
    [switch]$Status
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($KitRoot)) {
    $KitRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
}
$KitRoot = [IO.Path]::GetFullPath($KitRoot)
$InventoryRoot = Join-Path $KitRoot "environment\devices"
$InventoryPath = Join-Path $InventoryRoot ("{0}.json" -f $env:COMPUTERNAME)

function Get-CommandRecord($Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{ name = $Name; available = $false; path = $null; version = $null }
    }
    $path = if ($command.Path) { [string]$command.Path } else { [string]$command.Source }
    $version = $null
    if ($command.Version) { $version = [string]$command.Version }
    if ([string]::IsNullOrWhiteSpace($version) -and $path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        try { $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileVersion } catch {}
    }
    return [pscustomobject]@{
        name = $Name
        available = $true
        path = $path
        version = $version
    }
}

function Get-InstalledApps {
    $roots = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $apps = @()
    foreach ($root in $roots) {
        foreach ($item in @(Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
            $nameProperty = $item.PSObject.Properties["DisplayName"]
            if (-not $nameProperty -or [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) { continue }
            $versionProperty = $item.PSObject.Properties["DisplayVersion"]
            $publisherProperty = $item.PSObject.Properties["Publisher"]
            $apps += [pscustomobject]@{
                name = [string]$nameProperty.Value
                version = $(if ($versionProperty) { [string]$versionProperty.Value } else { $null })
                publisher = $(if ($publisherProperty) { [string]$publisherProperty.Value } else { $null })
                scope = $(if ($root.StartsWith("HKCU:", [StringComparison]::OrdinalIgnoreCase)) { "user" } else { "machine" })
            }
        }
    }
    return @($apps | Sort-Object name, version, scope -Unique)
}

function Get-WslDistributions {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { return @() }
    try {
        $raw = & $wsl.Path --list --quiet 2>$null
        return @($raw | ForEach-Object { ([string]$_).Replace([char]0, "").Trim() } | Where-Object { $_ })
    } catch {
        return @()
    }
}

if ($Status) {
    $files = @(Get-ChildItem -LiteralPath $InventoryRoot -File -Filter "*.json" -ErrorAction SilentlyContinue)
    $local = $files | Where-Object { $_.BaseName -eq $env:COMPUTERNAME } | Select-Object -First 1
    if ($local) {
        Write-Host "[OK] environment inventory: $($local.FullName), updated $($local.LastWriteTime)" -ForegroundColor Green
    } else {
        Write-Host "[OPTIONAL] environment inventory: no snapshot for $env:COMPUTERNAME; use -CaptureEnvironmentInventory" -ForegroundColor DarkGray
    }
    if ($files.Count -gt 0) {
        Write-Host "[INFO] environment inventories available for: $((@($files.BaseName | Sort-Object) -join ', '))" -ForegroundColor DarkCyan
    }
    return
}

if (-not (Test-Path -LiteralPath $InventoryRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $InventoryRoot -Force | Out-Null
}

$os = $null
$computer = $null
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}
try { $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}
$appx = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $appx) {
    $appx = Get-AppxPackage -Name "OpenAI.ChatGPT" -ErrorAction SilentlyContinue | Select-Object -First 1
}
$record = [pscustomobject]@{
    schema_version = 1
    device_name = $env:COMPUTERNAME
    captured_at = (Get-Date).ToString("o")
    user_profile = [IO.Path]::GetFullPath($env:USERPROFILE)
    os = [pscustomobject]@{
        caption = $(if ($os) { [string]$os.Caption } else { [Environment]::OSVersion.VersionString })
        version = $(if ($os) { [string]$os.Version } else { [string][Environment]::OSVersion.Version })
        build_number = $(if ($os) { [string]$os.BuildNumber } else { [string][Environment]::OSVersion.Version.Build })
        architecture = $(if ($os) { [string]$os.OSArchitecture } else { [string]$env:PROCESSOR_ARCHITECTURE })
    }
    hardware = [pscustomobject]@{
        manufacturer = $(if ($computer) { [string]$computer.Manufacturer } else { $null })
        model = $(if ($computer) { [string]$computer.Model } else { $null })
        total_memory_gb = $(if ($computer) { [math]::Round([double]$computer.TotalPhysicalMemory / 1GB, 2) } else { $null })
    }
    powershell = [pscustomobject]@{
        edition = [string]$PSVersionTable.PSEdition
        version = [string]$PSVersionTable.PSVersion
    }
    chatgpt_app = $(if ($appx) {
        [pscustomobject]@{
            package = [string]$appx.Name
            version = [string]$appx.Version
            install_location = [string]$appx.InstallLocation
        }
    } else { $null })
    commands = @(
        "codex.exe",
        "git.exe",
        "winget.exe",
        "pwsh.exe",
        "powershell.exe",
        "python.exe",
        "node.exe",
        "npm.cmd",
        "wsl.exe"
    ) | ForEach-Object { Get-CommandRecord $_ }
    wsl_distributions = @(Get-WslDistributions)
    installed_apps = @(Get-InstalledApps)
}

$temp = "$InventoryPath.tmp.$PID"
[IO.File]::WriteAllText($temp, (($record | ConvertTo-Json -Depth 8) + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temp -Destination $InventoryPath -Force
Write-Host "Captured environment inventory: $InventoryPath" -ForegroundColor Green
Write-Host "Installed applications recorded: $($record.installed_apps.Count)" -ForegroundColor DarkGreen
