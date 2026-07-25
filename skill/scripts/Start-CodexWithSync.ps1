param(
    [switch]$CheckOnly,
    [switch]$NoLaunch,
    [int]$WaitForExitPollSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot
$KitRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptRoot "..\..\..\..")).Path
$SwitchCommand = Join-Path $KitRoot "Switch-CodexMachine.cmd"
$DesktopStateScript = Join-Path $ScriptRoot "Sync-CodexDesktopState.ps1"
$MergeHelper = Join-Path $ScriptRoot "Merge-CodexSidebarState.mjs"
$ThreadCatalogRepairHelper = Join-Path $ScriptRoot "Repair-CodexThreadCatalog.mjs"
$ThreadCatalogDatabase = Join-Path $env:USERPROFILE ".codex\state_5.sqlite"
$LocalDesktopState = Join-Path $env:USERPROFILE ".codex\.codex-global-state.json"
$SharedDesktopState = Join-Path $KitRoot "desktop-state\.codex-global-state.json"
$OrganizationBaseline = Join-Path $env:USERPROFILE ".local\state\codexkit\desktop-sidebar-merge-base.json"
$RunningMarker = Join-Path $KitRoot "desktop-state\codex-running.json"
$RunningMarkerStaleSeconds = 300
$RunningMarkerHeartbeatSeconds = 60
$LauncherLogRoot = Join-Path $env:TEMP "CodexKit\logs"
$SyncReceipt = Join-Path $env:USERPROFILE ".local\state\codexkit\last-desktop-sync.json"
try {
    New-Item -ItemType Directory -Force -Path $LauncherLogRoot | Out-Null
    $launcherLogName = "Start-CodexManaged-{0:yyyyMMdd-HHmmss}-{1}.log" -f (Get-Date), $PID
    Start-Transcript -LiteralPath (Join-Path $LauncherLogRoot $launcherLogName) -Force | Out-Null
} catch {
    Write-Warning "Could not start the device-local launcher transcript: $($_.Exception.Message)"
}

trap {
    $diagnosticLauncher = "Start-CodexManaged.cmd"
    $failure = "CodexKit managed launch failed on $env:COMPUTERNAME.`r`n`r`n$($_.Exception.Message)`r`n`r`nChatGPT was not opened with stale desktop state. Run $diagnosticLauncher to view the full diagnostic log."
    if ($env:CODEXKIT_SUPPRESS_FAILURE_POPUP -ne "1") {
        try {
            $shell = New-Object -ComObject WScript.Shell
            [void]$shell.Popup($failure, 0, "CodexKit launch failed", 16)
        } catch {}
    }
    Write-Error $failure
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

function Invoke-Step($Title, [scriptblock]$ScriptBlock) {
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor Cyan
    & $ScriptBlock
}

function Assert-SyncReceipt([ValidateSet("pull", "push", "merge")][string]$ExpectedMode, [DateTimeOffset]$StartedAt) {
    if (-not (Test-Path -LiteralPath $SyncReceipt -PathType Leaf)) {
        throw "The desktop sync helper did not write a completion receipt. OneDrive may still have an older codexkit-sync skill version."
    }
    $receipt = Get-Content -LiteralPath $SyncReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    $completedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$receipt.completed_at, [ref]$completedAt)) {
        throw "The desktop sync receipt has an invalid completion time: $SyncReceipt"
    }
    if ([string]$receipt.device -ine [string]$env:COMPUTERNAME -or [string]$receipt.mode -ine $ExpectedMode -or $completedAt -lt $StartedAt) {
        throw "The desktop sync receipt does not match this $ExpectedMode operation on $env:COMPUTERNAME."
    }
    if ([string]$receipt.sync_script_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$receipt.merge_helper_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$receipt.thread_catalog_helper_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$receipt.local_state_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$receipt.shared_state_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$receipt.organization_sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "The desktop sync receipt is incomplete or came from an outdated helper: $SyncReceipt"
    }
    $hashChecks = @(
        [pscustomobject]@{ Label = "sync script"; Path = $DesktopStateScript; Expected = [string]$receipt.sync_script_sha256 },
        [pscustomobject]@{ Label = "merge helper"; Path = $MergeHelper; Expected = [string]$receipt.merge_helper_sha256 },
        [pscustomobject]@{ Label = "thread catalog helper"; Path = $ThreadCatalogRepairHelper; Expected = [string]$receipt.thread_catalog_helper_sha256 },
        [pscustomobject]@{ Label = "local desktop state"; Path = $LocalDesktopState; Expected = [string]$receipt.local_state_sha256 },
        [pscustomobject]@{ Label = "shared desktop state"; Path = $SharedDesktopState; Expected = [string]$receipt.shared_state_sha256 },
        [pscustomobject]@{ Label = "organization baseline"; Path = $OrganizationBaseline; Expected = [string]$receipt.organization_sha256 }
    )
    foreach ($check in $hashChecks) {
        if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) {
            throw "The $($check.Label) referenced by the sync receipt is missing: $($check.Path)"
        }
        $actual = (Get-FileHash -LiteralPath $check.Path -Algorithm SHA256).Hash
        if ($actual -ne $check.Expected) {
            throw "The $($check.Label) changed after $ExpectedMode completed. Wait for OneDrive and retry the managed launch."
        }
    }
    if ($ExpectedMode -eq "pull" -or $ExpectedMode -eq "merge") {
        $catalogStatus = [string]$receipt.thread_catalog_status
        if ($catalogStatus -notin @("reconciled", "database-missing")) {
            throw "The $ExpectedMode receipt does not prove that the local thread catalog was reconciled."
        }
        if ([int]$receipt.thread_catalog_unresolved_count -ne 0) {
            throw "The local thread catalog still has $($receipt.thread_catalog_unresolved_count) unresolved task(s)."
        }
    }
    $expectedCatalogHash = [string]$receipt.thread_catalog_database_sha256
    if ($expectedCatalogHash -eq "missing") {
        if (Test-Path -LiteralPath $ThreadCatalogDatabase -PathType Leaf) {
            throw "The local thread catalog appeared after synchronization; retry the managed launch so it can be reconciled."
        }
    } elseif ($expectedCatalogHash -match '^[A-Fa-f0-9]{64}$') {
        if (-not (Test-Path -LiteralPath $ThreadCatalogDatabase -PathType Leaf)) {
            throw "The local thread catalog referenced by the sync receipt is missing: $ThreadCatalogDatabase"
        }
        $actualCatalogHash = (Get-FileHash -LiteralPath $ThreadCatalogDatabase -Algorithm SHA256).Hash
        if ($actualCatalogHash -ne $expectedCatalogHash) {
            throw "The local thread catalog changed after $ExpectedMode completed. Retry the managed launch."
        }
    } else {
        throw "The desktop sync receipt has an invalid thread catalog hash."
    }
    Write-Host "Verified $ExpectedMode receipt from $($receipt.completed_at); sync script $($receipt.sync_script_sha256.Substring(0, 12))." -ForegroundColor Green
}

function Get-FreshRunningDeviceMap {
    $fresh = @{}
    if (-not (Test-Path -LiteralPath $RunningMarker -PathType Leaf)) {
        return $fresh
    }

    try {
        $marker = Get-Content -LiteralPath $RunningMarker -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $marker.devices) { return $fresh }
        $cutoff = [DateTimeOffset]::UtcNow.AddSeconds(-$RunningMarkerStaleSeconds)
        foreach ($property in @($marker.devices.PSObject.Properties)) {
            $entry = $property.Value
            $heartbeat = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([string]$entry.heartbeatAt, [ref]$heartbeat)) { continue }
            if ($heartbeat -lt $cutoff) { continue }
            $fresh[$property.Name] = [ordered]@{
                mode = [string]$entry.mode
                pid = [int]$entry.pid
                startedAt = [string]$entry.startedAt
                heartbeatAt = $heartbeat.ToUniversalTime().ToString("o")
            }
        }
    } catch {
        Write-Warning "Could not read the advisory Codex running marker: $($_.Exception.Message)"
    }
    return $fresh
}

function Write-RunningDeviceMap([hashtable]$Devices) {
    $parent = Split-Path -Parent $RunningMarker
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $payload = [ordered]@{
        running = if ($Devices.Count -gt 0) { 1 } else { 0 }
        updatedAt = [DateTimeOffset]::UtcNow.ToString("o")
        devices = $Devices
    }
    $json = $payload | ConvertTo-Json -Depth 8
    $temporary = "$RunningMarker.tmp.$env:COMPUTERNAME.$PID"
    try {
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $RunningMarker -Force
    } catch {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Write-Warning "Could not update the advisory Codex running marker: $($_.Exception.Message)"
    }
}

function Update-RunningDeviceMarker([ValidateSet("Start", "Heartbeat", "Stop")][string]$Action) {
    $devices = Get-FreshRunningDeviceMap
    $deviceName = [string]$env:COMPUTERNAME
    if ($Action -eq "Stop") {
        $devices.Remove($deviceName)
    } else {
        $startedAt = [DateTimeOffset]::UtcNow.ToString("o")
        if ($devices.ContainsKey($deviceName) -and $devices[$deviceName].startedAt) {
            $startedAt = [string]$devices[$deviceName].startedAt
        }
        $desktopProcess = Get-DesktopCodexProcesses | Select-Object -First 1
        $devices[$deviceName] = [ordered]@{
            mode = "Managed"
            pid = if ($desktopProcess) { [int]$desktopProcess.Id } else { 0 }
            startedAt = $startedAt
            heartbeatAt = [DateTimeOffset]::UtcNow.ToString("o")
        }
    }
    Write-RunningDeviceMap -Devices $devices
}

function Confirm-CrossDeviceLaunch {
    $devices = Get-FreshRunningDeviceMap
    $otherNames = @($devices.Keys | Where-Object { $_ -ine $env:COMPUTERNAME } | Sort-Object)
    if ($otherNames.Count -eq 0) { return }

    $details = @($otherNames | ForEach-Object {
        $entry = $devices[$_]
        "- $_ ($($entry.mode), heartbeat $($entry.heartbeatAt))"
    }) -join "`r`n"
    $message = "Codex appears to be running on another device:`r`n`r`n$details`r`n`r`nContinue opening Codex here? Avoid editing the same task on both devices."
    try {
        $shell = New-Object -ComObject WScript.Shell
        $choice = $shell.Popup($message, 0, "CodexKit cross-device warning", 52)
        if ($choice -ne 6) { throw "Codex launch cancelled after the cross-device warning." }
    } catch {
        if ($_.Exception.Message -like "Codex launch cancelled*") { throw }
        Write-Warning $message
    }
}

function Get-CodexDesktopAppxPackages {
    $packages = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($pattern in @("OpenAI.Codex", "OpenAI.ChatGPT")) {
        try {
            foreach ($package in @(Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue)) {
                if (-not $package.InstallLocation -or $seen.ContainsKey($package.PackageFullName)) { continue }

                $manifestPath = Join-Path $package.InstallLocation "AppxManifest.xml"
                if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
                try {
                    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
                    $protocol = $manifest.SelectSingleNode("//*[local-name()='Protocol' and translate(@Name,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='codex']")
                    if ($package.Name -eq "OpenAI.Codex" -or $protocol) {
                        $seen[$package.PackageFullName] = $true
                        $packages.Add([pscustomobject]@{ Package = $package; Manifest = $manifest }) | Out-Null
                    }
                } catch {}
            }
        } catch {}
    }
    return $packages.ToArray()
}

function Get-DesktopCodexProcesses([string]$DesktopExecutable) {
    $expectedPath = $null
    if ($DesktopExecutable -and (Test-Path -LiteralPath $DesktopExecutable -PathType Leaf)) {
        $expectedPath = (Resolve-Path -LiteralPath $DesktopExecutable).Path
    }

    @(Get-Process -Name "Codex", "ChatGPT" -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not $_.Path -or $_.Path -match '\\resources\\codex\.exe$') { return $false }
            if ($expectedPath) { return $_.Path -ieq $expectedPath }
            return $_.Path -match '\\(?:Codex|ChatGPT)\.exe$'
        })
}

function Get-CodexDesktopExecutable {
    if ($env:CODEX_DESKTOP_EXE -and (Test-Path -LiteralPath $env:CODEX_DESKTOP_EXE -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $env:CODEX_DESKTOP_EXE).Path
    }

    foreach ($appx in @(Get-CodexDesktopAppxPackages)) {
        $application = $appx.Manifest.SelectSingleNode("//*[local-name()='Application' and @Executable]")
        if ($application) {
            $relativeExecutable = ([string]$application.Executable).Replace('/', '\')
            $candidate = Join-Path $appx.Package.InstallLocation $relativeExecutable
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    $running = Get-DesktopCodexProcesses | Select-Object -First 1
    if ($running -and $running.Path -and (Test-Path -LiteralPath $running.Path -PathType Leaf)) {
        return $running.Path
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT\ChatGPT.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\OpenAI ChatGPT\ChatGPT.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Codex\Codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\codex\Codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\OpenAI Codex\Codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $shortcutRoots = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs")
    )
    foreach ($root in $shortcutRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $shortcuts = @(Get-ChildItem -LiteralPath $root -Recurse -Filter "*Codex*.lnk" -ErrorAction SilentlyContinue)
        $shortcuts += @(Get-ChildItem -LiteralPath $root -Recurse -Filter "*ChatGPT*.lnk" -ErrorAction SilentlyContinue)
        foreach ($shortcut in $shortcuts) {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $target = $shell.CreateShortcut($shortcut.FullName).TargetPath
                $targetName = if ($target) { [IO.Path]::GetFileName($target) } else { "" }
                if ($targetName -match '^(?:Codex|ChatGPT)\.exe$' -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                    return (Resolve-Path -LiteralPath $target).Path
                }
            } catch {}
        }
    }

    throw "Could not find the Codex desktop executable. Set CODEX_DESKTOP_EXE to its full path and rerun this launcher."
}

function Get-CodexDesktopAppUserModelId([string]$DesktopExecutable) {
    if (-not $DesktopExecutable -or -not (Test-Path -LiteralPath $DesktopExecutable -PathType Leaf)) {
        return $null
    }

    $expectedPath = (Resolve-Path -LiteralPath $DesktopExecutable).Path
    foreach ($appx in @(Get-CodexDesktopAppxPackages)) {
        foreach ($application in @($appx.Manifest.SelectNodes("//*[local-name()='Application' and @Executable]"))) {
            $relativeExecutable = ([string]$application.Executable).Replace('/', '\')
            $candidate = Join-Path $appx.Package.InstallLocation $relativeExecutable
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            if ((Resolve-Path -LiteralPath $candidate).Path -ine $expectedPath) { continue }

            $appId = [string]$application.Id
            $packageFamilyName = [string]$appx.Package.PackageFamilyName
            if ($appId -and $packageFamilyName) {
                return "$packageFamilyName!$appId"
            }
        }
    }

    return $null
}

function Start-CodexDesktop([string]$DesktopExecutable) {
    $wasRunning = @(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -gt 0
    $appUserModelId = Get-CodexDesktopAppUserModelId -DesktopExecutable $DesktopExecutable
    if ($appUserModelId) {
        $explorer = Join-Path $env:WINDIR "explorer.exe"
        Write-Host "Activating packaged ChatGPT: shell:AppsFolder\$appUserModelId" -ForegroundColor DarkCyan
        Start-Process -FilePath $explorer -ArgumentList "shell:AppsFolder\$appUserModelId" | Out-Null

        if (-not $wasRunning) {
            Write-Host "Waiting for the cold-start process before requesting foreground activation." -ForegroundColor DarkCyan
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                if (@(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -gt 0) { break }
                Start-Sleep -Milliseconds 500
            }

            if (@(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -eq 0) {
                Write-Host "AppX activation did not create a detectable process; trying the executable fallback once." -ForegroundColor Yellow
                Start-Process -FilePath $DesktopExecutable | Out-Null
                for ($attempt = 0; $attempt -lt 20; $attempt++) {
                    if (@(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -gt 0) { break }
                    Start-Sleep -Milliseconds 500
                }
            }

            if (@(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -eq 0) {
                throw "ChatGPT did not create a detectable desktop process after AppX and executable activation attempts."
            }

            Start-Sleep -Seconds 2
            Write-Host "Cold-start process is ready; activating ChatGPT again to present its window." -ForegroundColor DarkCyan
            Start-Process -FilePath $explorer -ArgumentList "shell:AppsFolder\$appUserModelId" | Out-Null
        }
        return
    }

    Start-Process -FilePath $DesktopExecutable | Out-Null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (@(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable).Count -gt 0) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "ChatGPT did not create a detectable desktop process after direct executable activation."
}

function Wait-CodexDesktopExit([string]$DesktopExecutable) {
    Write-Host "Waiting for ChatGPT to exit. When it closes, this launcher will publish task/sidebar changes to OneDrive." -ForegroundColor Yellow
    $lastHeartbeat = [DateTimeOffset]::MinValue
    $consecutiveAbsentSamples = 0
    while ($true) {
        $processes = @(Get-DesktopCodexProcesses -DesktopExecutable $DesktopExecutable)
        if ($processes.Count -eq 0) {
            $consecutiveAbsentSamples++
            if ($consecutiveAbsentSamples -ge 2) { return }
        } else {
            $consecutiveAbsentSamples = 0
        }
        if (([DateTimeOffset]::UtcNow - $lastHeartbeat).TotalSeconds -ge $RunningMarkerHeartbeatSeconds) {
            Update-RunningDeviceMarker -Action Heartbeat
            $lastHeartbeat = [DateTimeOffset]::UtcNow
        }
        Start-Sleep -Seconds $WaitForExitPollSeconds
    }
}

if (-not (Test-Path -LiteralPath $SwitchCommand -PathType Leaf)) {
    throw "Missing switch helper: $SwitchCommand"
}

$codexExe = Get-CodexDesktopExecutable
Write-Host "Codex executable: $codexExe" -ForegroundColor DarkCyan
if ($CheckOnly) {
    $runningCount = @(Get-DesktopCodexProcesses -DesktopExecutable $codexExe).Count
    $appUserModelId = Get-CodexDesktopAppUserModelId -DesktopExecutable $codexExe
    if ($appUserModelId) {
        Write-Host "Launch activation: shell:AppsFolder\$appUserModelId" -ForegroundColor DarkCyan
    } else {
        Write-Host "Launch activation: direct executable fallback" -ForegroundColor DarkCyan
    }
    Write-Host "Matching desktop process count: $runningCount" -ForegroundColor DarkCyan
    $runningDevices = Get-FreshRunningDeviceMap
    Write-Host "Fresh cross-device running markers: $($runningDevices.Count)" -ForegroundColor DarkCyan
    Write-Host "Launcher check complete. No sync or launch was performed." -ForegroundColor Green
    return
}

$alreadyRunning = @(Get-DesktopCodexProcesses -DesktopExecutable $codexExe)
if ($alreadyRunning.Count -gt 0) {
    Write-Host "ChatGPT is already running on this machine; no Pull or Push will run against live desktop state." -ForegroundColor Yellow
    Write-Host "Activating the existing ChatGPT window." -ForegroundColor Yellow
    Start-CodexDesktop -DesktopExecutable $codexExe
    return
}

if (-not $NoLaunch) { Confirm-CrossDeviceLaunch }

Invoke-Step "Pull desktop sidebar state before launch" {
    $pullStartedAt = [DateTimeOffset]::UtcNow
    & $SwitchCommand -Action Pull
    if ($LASTEXITCODE -ne 0) { throw "Managed startup Pull returned exit code $LASTEXITCODE." }
    Assert-SyncReceipt -ExpectedMode pull -StartedAt $pullStartedAt
}

if ($NoLaunch) { return }
Update-RunningDeviceMarker -Action Start
try {
    Invoke-Step "Start ChatGPT managed session" {
        Start-CodexDesktop -DesktopExecutable $codexExe
    }
    Start-Sleep -Seconds 3
    Wait-CodexDesktopExit -DesktopExecutable $codexExe
}
finally {
    try {
        Invoke-Step "Push desktop sidebar state after ChatGPT exits" {
            $pushStartedAt = [DateTimeOffset]::UtcNow
            & $SwitchCommand -Action Push
            if ($LASTEXITCODE -ne 0) { throw "Managed shutdown Push returned exit code $LASTEXITCODE." }
            Assert-SyncReceipt -ExpectedMode push -StartedAt $pushStartedAt
        }
    } finally {
        Update-RunningDeviceMarker -Action Stop
    }
}
