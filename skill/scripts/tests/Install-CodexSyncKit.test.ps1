#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Get-TreeFingerprint([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    return @(
        Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($root.Length).TrimStart('\')
                "$relative`t$($_.Length)`t$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            }
    ) -join "`n"
}

function Invoke-Bootstrap([string[]]$Arguments) {
    $commandArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:Installer
    ) + $Arguments
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @commandArguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Find-BootstrapInstaller([string]$StartPath) {
    $current = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($StartPath))
    while ($null -ne $current) {
        foreach ($candidate in @(
            (Join-Path $current.FullName "Install-CodexSyncKit.ps1"),
            (Join-Path $current.FullName "open-source\codex-synckit\Install-CodexSyncKit.ps1")
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
        $current = $current.Parent
    }
    throw "Could not locate Install-CodexSyncKit.ps1 from $StartPath."
}

$script:Installer = Find-BootstrapInstaller $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-synckit-bootstrap-" + [guid]::NewGuid().ToString("N"))
$profileRoot = Join-Path $testRoot "profile"
$existingKit = Join-Path $testRoot "OneDrive\CodexKit"
$legacyKit = Join-Path $testRoot "OneDrive\LegacyKit"
$tamperedKit = Join-Path $testRoot "OneDrive\TamperedKit"
$unknownDirectory = Join-Path $testRoot "OneDrive\UnknownKit"
$missingKit = Join-Path $testRoot "OneDrive\MissingKit"
$savedEnvironment = @{}

try {
    foreach ($name in @("USERPROFILE", "CODEX_HOME", "OneDrive", "OneDriveConsumer", "OneDriveCommercial")) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    $env:USERPROFILE = $profileRoot
    $env:CODEX_HOME = Join-Path $profileRoot ".codex"
    $env:OneDrive = Join-Path $testRoot "OneDrive"
    $env:OneDriveConsumer = $null
    $env:OneDriveCommercial = $null

    foreach ($directory in @(
        (Join-Path $existingKit "desktop-state"),
        (Join-Path $existingKit "session-data\sessions\2026\07\25"),
        (Join-Path $env:CODEX_HOME "sessions\2026\07\25"),
        $unknownDirectory
    )) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $generatedInstallerContent = @'
param(
    [string]$KitRoot,
    [switch]$Recommended,
    [switch]$InstallSessionLinks,
    [switch]$EnableMemorySubsystem,
    [switch]$DisableMemorySubsystem
)
if (-not $Recommended -or -not $DisableMemorySubsystem) {
    throw "Unexpected generated-installer arguments."
}
'@
    Set-Content -LiteralPath (Join-Path $existingKit "Install-CodexKitForWindows.ps1") `
        -Value $generatedInstallerContent -Encoding UTF8
    $installerHash = (Get-FileHash -LiteralPath (Join-Path $existingKit "Install-CodexKitForWindows.ps1") -Algorithm SHA256).Hash
    [pscustomobject]@{
        product = "codex-synckit"
        manifest_version = 1
        include_sessions = $true
        include_desktop_state = $true
        include_memory_subsystem = $false
        files = @(
            [pscustomobject]@{
                path = "Install-CodexKitForWindows.ps1"
                sha256 = $installerHash
            }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $existingKit "manifest.json") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingKit "desktop-state\.codex-global-state.json") `
        -Value '{"projects":{"shared":"newest"}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingKit "session-data\sessions\2026\07\25\same-id.jsonl") `
        -Value '{"source":"shared-newest"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $env:CODEX_HOME ".codex-global-state.json") `
        -Value '{"projects":{"local":"stale"}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $env:CODEX_HOME "sessions\2026\07\25\same-id.jsonl") `
        -Value '{"source":"local-stale"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $unknownDirectory "existing-user-file.txt") `
        -Value 'must remain untouched' -Encoding UTF8

    $beforeJoin = Get-TreeFingerprint $existingKit
    $join = Invoke-Bootstrap @(
        "-DestinationRoot", $existingKit,
        "-Recommended",
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($join.ExitCode -eq 0) "auto mode should safely join a valid existing Kit"
    Assert-True ($join.Output -match 'CodexKit setup mode: Join') "auto mode should report Join"
    Assert-True ($join.Output -match '\[JOIN\].*will not be exported') "join should report that local state is not exported"
    Assert-True ((Get-TreeFingerprint $existingKit) -eq $beforeJoin) "joining must not modify any shared Kit file during bootstrap"

    $appliedJoin = Invoke-Bootstrap @(
        "-DestinationRoot", $existingKit,
        "-Recommended",
        "-SkipMemorySubsystem"
    )
    Assert-True ($appliedJoin.ExitCode -eq 0) "a real join should complete with the existing generated installer"
    Assert-True ((Get-TreeFingerprint $existingKit) -eq $beforeJoin) "a real join must not export local state over the shared Kit"
    Assert-True (
        Test-Path -LiteralPath (Join-Path $env:CODEX_HOME "skills\codexkit-sync\SKILL.md") -PathType Leaf
    ) "a real join should still install the local codexkit-sync skill"

    Copy-Item -LiteralPath $existingKit -Destination $legacyKit -Recurse
    $legacyManifestPath = Join-Path $legacyKit "manifest.json"
    $legacyManifest = Get-Content -LiteralPath $legacyManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $legacyManifest.PSObject.Properties.Remove("product")
    $legacyManifest.PSObject.Properties.Remove("manifest_version")
    $legacyManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $legacyManifestPath -Encoding UTF8
    $legacyJoin = Invoke-Bootstrap @(
        "-DestinationRoot", $legacyKit,
        "-Recommended",
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($legacyJoin.ExitCode -eq 0) "a legacy Kit with a valid installer hash should remain joinable"
    Assert-True ($legacyJoin.Output -match 'legacy CodexKit manifest') "legacy join should report compatibility mode"

    Copy-Item -LiteralPath $existingKit -Destination $tamperedKit -Recurse
    Add-Content -LiteralPath (Join-Path $tamperedKit "Install-CodexKitForWindows.ps1") `
        -Value '# unexpected change' -Encoding UTF8
    $tamperedJoin = Invoke-Bootstrap @(
        "-DestinationRoot", $tamperedKit,
        "-Recommended",
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($tamperedJoin.ExitCode -ne 0) "join must reject a shared installer changed after manifest generation"
    Assert-True ($tamperedJoin.Output -match 'does not match manifest') "tampered installer rejection should identify the integrity failure"

    $initializeExisting = Invoke-Bootstrap @(
        "-DestinationRoot", $existingKit,
        "-KitMode", "Initialize",
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($initializeExisting.ExitCode -ne 0) "Initialize must reject an existing Kit"
    Assert-True ((Get-TreeFingerprint $existingKit) -eq $beforeJoin) "rejected initialization must not modify the existing Kit"

    $enableMissingMemory = Invoke-Bootstrap @(
        "-DestinationRoot", $existingKit,
        "-InstallMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($enableMissingMemory.ExitCode -ne 0) "join must not add memory to a shared Kit that excluded it"
    Assert-True ((Get-TreeFingerprint $existingKit) -eq $beforeJoin) "rejected memory enablement must not modify the existing Kit"

    $beforeUnknown = Get-TreeFingerprint $unknownDirectory
    $unknown = Invoke-Bootstrap @(
        "-DestinationRoot", $unknownDirectory,
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($unknown.ExitCode -ne 0) "auto mode must reject a nonempty directory without a manifest"
    Assert-True ((Get-TreeFingerprint $unknownDirectory) -eq $beforeUnknown) "an unrecognized directory must remain untouched"

    $missing = Invoke-Bootstrap @(
        "-DestinationRoot", $missingKit,
        "-KitMode", "Join",
        "-SkipMemorySubsystem",
        "-DryRun"
    )
    Assert-True ($missing.ExitCode -ne 0) "Join must require an existing manifest"
    Assert-True (-not (Test-Path -LiteralPath $missingKit)) "failed Join must not create the destination"

    Write-Host "[OK] bootstrap initialize/join safety tests passed" -ForegroundColor Green
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test path outside the temp directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
