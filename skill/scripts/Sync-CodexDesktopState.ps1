param(
    [switch]$Push,
    [switch]$Pull,
    [switch]$Merge,
    [switch]$Status,
    [switch]$AllowStateRegression,
    [int]$BackupRetention = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..\..")).Path
$CodexHome = Join-Path $env:USERPROFILE ".codex"
$LocalState = Join-Path $CodexHome ".codex-global-state.json"
$SharedState = Join-Path $KitRoot "desktop-state\.codex-global-state.json"
$RunningMarker = Join-Path $KitRoot "desktop-state\codex-running.json"
$SessionIndex = Join-Path $KitRoot "session-data\session_index.jsonl"
$MergeHelper = Join-Path $PSScriptRoot "Merge-CodexSidebarState.mjs"
$SessionIndexRepairHelper = Join-Path $PSScriptRoot "Repair-CodexSessionIndex.mjs"
$ThreadCatalogRepairHelper = Join-Path $PSScriptRoot "Repair-CodexThreadCatalog.mjs"
$ThreadCatalogDatabase = Join-Path $CodexHome "state_5.sqlite"
$SessionsRoot = Join-Path $KitRoot "session-data\sessions"
$ArchivedSessionsRoot = Join-Path $KitRoot "session-data\archived_sessions"
$ProjectlessRoot = Join-Path $env:USERPROFILE "Documents\Codex"
$BaseState = Join-Path $env:USERPROFILE ".local\state\codexkit\desktop-sidebar-merge-base.json"
$safeDeviceName = ([string]$env:COMPUTERNAME -replace '[^A-Za-z0-9._-]', '_')
if ([string]::IsNullOrWhiteSpace($safeDeviceName)) { $safeDeviceName = "unknown-device" }
$LocalStateRoot = Join-Path $env:USERPROFILE ".local\state\codexkit"
$SyncReceipt = Join-Path $LocalStateRoot "last-desktop-sync.json"
$QuarantineDir = Join-Path $LocalStateRoot "desktop-state-quarantine"
$ConflictDir = Join-Path $LocalStateRoot "desktop-state-conflicts"
$ThreadCatalogConflictDir = Join-Path $LocalStateRoot "thread-catalog-conflicts"

function Ensure-Dir($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-ShortHash($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "missing" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Substring(0, 12)
}

function Get-FullHashOrMissing($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "missing" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-InputUnchanged($Path, [string]$ExpectedHash, [string]$Label) {
    $currentHash = Get-FullHashOrMissing $Path
    if ($currentHash -ne $ExpectedHash) {
        throw "$Label changed while synchronization was being prepared. No generated state was installed; wait for OneDrive and retry."
    }
}

function Get-StateProfile($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $item = Get-Item -LiteralPath $Path -Force
    $raw = [IO.File]::ReadAllText($Path)
    $markers = @(
        '"electron-saved-workspace-roots"',
        '"active-workspace-roots"',
        '"thread-workspace-root-hints"',
        '"project-order"',
        '"projectless-thread-ids"',
        '"pinned-thread-ids"'
    )
    $presentMarkers = @($markers | Where-Object { $raw.Contains($_) })

    [pscustomobject]@{
        Path = $Path
        Length = [long]$item.Length
        MarkerCount = $presentMarkers.Count
        ThreadIdReferences = [regex]::Matches($raw, '019[a-f0-9]{5}-[a-f0-9-]{27}', 'IgnoreCase').Count
    }
}

function Compare-StateProfiles($Candidate, $Reference) {
    $reasons = New-Object System.Collections.Generic.List[string]
    if (-not $Candidate -or -not $Reference) {
        return [pscustomobject]@{ IsRegression = $false; Reason = "" }
    }

    if ($Reference.Length -ge 8192 -and $Candidate.Length -lt 4096) {
        $reasons.Add("size fell from $($Reference.Length) bytes to $($Candidate.Length) bytes") | Out-Null
    }
    if ($Reference.MarkerCount -ge 3 -and $Candidate.MarkerCount -le 1) {
        $reasons.Add("workspace/task markers fell from $($Reference.MarkerCount) to $($Candidate.MarkerCount)") | Out-Null
    }
    if ($Reference.ThreadIdReferences -ge 10 -and $Candidate.ThreadIdReferences -eq 0) {
        $reasons.Add("thread references fell from $($Reference.ThreadIdReferences) to zero") | Out-Null
    }
    if ($Reference.Length -ge 8192 -and
        $Candidate.Length -lt [math]::Floor($Reference.Length * 0.25) -and
        $Candidate.MarkerCount -lt $Reference.MarkerCount) {
        $reasons.Add("state shrank below 25 percent while losing workspace/task markers") | Out-Null
    }

    [pscustomobject]@{
        IsRegression = $reasons.Count -gt 0
        Reason = ($reasons -join "; ")
    }
}

function Save-QuarantineCopy($CandidatePath, $Operation, $Reason) {
    Ensure-Dir $QuarantineDir
    $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $baseName = "$stamp-$safeDeviceName-$($Operation.ToLowerInvariant())"
    $copyPath = Join-Path $QuarantineDir "$baseName.json"
    $notePath = Join-Path $QuarantineDir "$baseName.txt"
    Copy-Item -LiteralPath $CandidatePath -Destination $copyPath -Force
    [IO.File]::WriteAllText($notePath, $Reason, (New-Object Text.UTF8Encoding($false)))
    return $copyPath
}

function Assert-StateSafe($CandidatePath, [string[]]$ReferencePaths, $Operation) {
    $candidate = Get-StateProfile $CandidatePath
    if (-not $candidate) { throw "Missing source state file: $CandidatePath" }
    if ($candidate.Length -le 0) { throw "Refusing to $Operation an empty desktop state file: $CandidatePath" }

    foreach ($referencePath in $ReferencePaths) {
        if (-not $referencePath -or $referencePath -ieq $CandidatePath) { continue }
        $reference = Get-StateProfile $referencePath
        if (-not $reference) { continue }
        $comparison = Compare-StateProfiles -Candidate $candidate -Reference $reference
        if (-not $comparison.IsRegression) { continue }

        $reason = "$Operation candidate is a catastrophic regression compared with $referencePath`: $($comparison.Reason)"
        if ($AllowStateRegression) {
            Write-Host "WARNING: $reason" -ForegroundColor Yellow
            Write-Host "Proceeding only because -AllowStateRegression was explicitly supplied." -ForegroundColor Yellow
            continue
        }

        $quarantine = Save-QuarantineCopy -CandidatePath $CandidatePath -Operation $Operation -Reason $reason
        throw "Blocked $Operation to protect task/project state. $reason. Candidate preserved at $quarantine. Use -AllowStateRegression only for an intentional reset."
    }
}

function Show-StateStatus {
    Write-Host "Codex desktop state sync status" -ForegroundColor Cyan
    $rows = foreach ($entry in @(
        [pscustomobject]@{ Name = "local"; Path = $LocalState },
        [pscustomobject]@{ Name = "shared"; Path = $SharedState },
        [pscustomobject]@{ Name = "merge baseline"; Path = $BaseState }
    )) {
        if (Test-Path -LiteralPath $entry.Path -PathType Leaf) {
            $item = Get-Item -LiteralPath $entry.Path -Force
            $profile = Get-StateProfile $entry.Path
            [pscustomobject]@{
                Name = $entry.Name
                Path = $entry.Path
                Length = $item.Length
                Markers = $profile.MarkerCount
                ThreadRefs = $profile.ThreadIdReferences
                LastWriteTime = $item.LastWriteTime
                Hash = Get-ShortHash $entry.Path
            }
        } else {
            [pscustomobject]@{
                Name = $entry.Name
                Path = $entry.Path
                Length = "missing"
                Markers = ""
                ThreadRefs = ""
                LastWriteTime = ""
                Hash = "missing"
            }
        }
    }
    $rows | Format-Table -AutoSize

    if (Test-Path -LiteralPath $SyncReceipt -PathType Leaf) {
        try {
            $receipt = Get-Content -LiteralPath $SyncReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Host ("Automation history: {0}/{1} cataloged; inserted {2}; stale paths repaired {3}; conflicts {4}; unresolved {5}; corrupt duplicate copies ignored {6}" -f
                [int]$receipt.automation_history_cataloged,
                [int]$receipt.automation_history_rollouts,
                [int]$receipt.automation_history_inserted_count,
                [int]$receipt.automation_history_path_repaired_count,
                [int]$receipt.automation_history_conflict_count,
                [int]$receipt.automation_history_unresolved_count,
                [int]$receipt.thread_catalog_corrupt_rollout_copy_count) -ForegroundColor DarkCyan
        } catch {
            Write-Host "Automation history receipt: unreadable ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Automation history receipt: missing (run a Managed Pull while ChatGPT is closed)" -ForegroundColor Yellow
    }

    if (-not (Test-Path -LiteralPath $RunningMarker -PathType Leaf)) {
        Write-Host "Running marker: missing (it will be created by the next managed launch)" -ForegroundColor Yellow
        return
    }
    try {
        $marker = Get-Content -LiteralPath $RunningMarker -Raw -Encoding UTF8 | ConvertFrom-Json
        $cutoff = [DateTimeOffset]::UtcNow.AddMinutes(-5)
        $freshDevices = @($marker.devices.PSObject.Properties | Where-Object {
            $heartbeat = [DateTimeOffset]::MinValue
            [DateTimeOffset]::TryParse([string]$_.Value.heartbeatAt, [ref]$heartbeat) -and $heartbeat -ge $cutoff
        } | ForEach-Object { $_.Name })
        $effectiveRunning = if ($freshDevices.Count -gt 0) { 1 } else { 0 }
        Write-Host "Running marker: $effectiveRunning; fresh devices: $(if ($freshDevices.Count) { $freshDevices -join ', ' } else { 'none' })" -ForegroundColor DarkCyan
    } catch {
        Write-Host "Running marker: unreadable ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

function Get-NodeExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:CODEXKIT_NODE_EXE) { $candidates.Add($env:CODEXKIT_NODE_EXE) | Out-Null }
    $command = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { $candidates.Add($command.Source) | Out-Null }
    $candidates.Add((Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe")) | Out-Null
    $runtimeRoot = Join-Path $env:USERPROFILE ".cache\codex-runtimes"
    if (Test-Path -LiteralPath $runtimeRoot -PathType Container) {
        foreach ($candidate in @(Get-ChildItem -LiteralPath $runtimeRoot -Filter node.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\dependencies\\node\\bin\\node\.exe$' })) {
            $candidates.Add($candidate.FullName) | Out-Null
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Could not find the bundled Node.js runtime required for conflict-aware sidebar merging. Install a primary-runtime Codex plugin or set CODEXKIT_NODE_EXE."
}

function Restore-File($Destination, $Backup, [bool]$Existed) {
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        Remove-Item -LiteralPath $Destination -Force
    }
    if ($Existed -and $Backup -and (Test-Path -LiteralPath $Backup -PathType Leaf)) {
        Copy-Item -LiteralPath $Backup -Destination $Destination -Force
    }
}

function Replace-FromGenerated($Generated, $Destination) {
    Ensure-Dir (Split-Path -Parent $Destination)
    if (Test-Path -LiteralPath $Destination -PathType Container) {
        throw "Expected a file destination but found a directory: $Destination"
    }
    $temporary = "$Destination.tmp.$PID.$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $Generated -Destination $temporary -Force
    try {
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Merge-SidebarState([ValidateSet("pull", "push", "merge")][string]$Mode) {
    if (-not (Test-Path -LiteralPath $MergeHelper -PathType Leaf)) {
        throw "Missing sidebar merge helper: $MergeHelper"
    }
    if ($Mode -eq "pull") {
        Assert-StateSafe -CandidatePath $LocalState -ReferencePaths @() -Operation "Read local device state"
        Assert-StateSafe -CandidatePath $SharedState -ReferencePaths @($LocalState, $BaseState) -Operation "Read authoritative shared state"
    } elseif ($Mode -eq "push") {
        Assert-StateSafe -CandidatePath $LocalState -ReferencePaths @($SharedState, $BaseState) -Operation "Read authoritative local state"
        Assert-StateSafe -CandidatePath $SharedState -ReferencePaths @() -Operation "Read shared device state"
    } else {
        Assert-StateSafe -CandidatePath $LocalState -ReferencePaths @($SharedState, $BaseState) -Operation "Merge local"
        Assert-StateSafe -CandidatePath $SharedState -ReferencePaths @($LocalState, $BaseState) -Operation "Merge shared"
    }

    $localInputHash = Get-FullHashOrMissing $LocalState
    $sharedInputHash = Get-FullHashOrMissing $SharedState
    $baseInputHash = Get-FullHashOrMissing $BaseState

    $node = Get-NodeExecutable
    $work = Join-Path ([IO.Path]::GetTempPath()) "codexkit-sidebar-merge-$PID-$([guid]::NewGuid().ToString('N'))"
    Ensure-Dir $work
    $generatedLocal = Join-Path $work "local.json"
    $generatedShared = Join-Path $work "shared.json"
    $generatedBase = Join-Path $work "base.json"
    $generatedReport = Join-Path $work "report.json"

    try {
        & $node $MergeHelper `
            --mode $Mode `
            --local $LocalState `
            --shared $SharedState `
            --base $BaseState `
            --local-output $generatedLocal `
            --shared-output $generatedShared `
            --base-output $generatedBase `
            --report-output $generatedReport `
            --projectless-root $ProjectlessRoot
        if ($LASTEXITCODE -ne 0) { throw "Sidebar merge helper returned exit code $LASTEXITCODE." }

        if ($Mode -ne "push") {
            Assert-StateSafe -CandidatePath $generatedLocal -ReferencePaths @($LocalState, $SharedState, $BaseState) -Operation "Install generated local"
        }
        if ($Mode -ne "pull") {
            Assert-StateSafe -CandidatePath $generatedShared -ReferencePaths @($SharedState, $LocalState, $BaseState) -Operation "Publish generated shared"
        }

        Assert-InputUnchanged -Path $LocalState -ExpectedHash $localInputHash -Label "Local desktop state"
        Assert-InputUnchanged -Path $SharedState -ExpectedHash $sharedInputHash -Label "Shared desktop state"
        Assert-InputUnchanged -Path $BaseState -ExpectedHash $baseInputHash -Label "Merge baseline"

        $localExisted = Test-Path -LiteralPath $LocalState -PathType Leaf
        $sharedExisted = Test-Path -LiteralPath $SharedState -PathType Leaf
        $baseExisted = Test-Path -LiteralPath $BaseState -PathType Leaf
        $writeLocal = $Mode -ne "push"
        $writeShared = $Mode -ne "pull"
        $localBackup = if ($writeLocal) { Backup-File $LocalState } else { $null }
        $sharedBackup = if ($writeShared) { Backup-File $SharedState } else { $null }
        $baseBackup = Backup-File $BaseState
        try {
            if ($writeShared) { Replace-FromGenerated -Generated $generatedShared -Destination $SharedState }
            if ($writeLocal) { Replace-FromGenerated -Generated $generatedLocal -Destination $LocalState }
            Replace-FromGenerated -Generated $generatedBase -Destination $BaseState
        } catch {
            if ($writeShared) { Restore-File -Destination $SharedState -Backup $sharedBackup -Existed $sharedExisted }
            if ($writeLocal) { Restore-File -Destination $LocalState -Backup $localBackup -Existed $localExisted }
            Restore-File -Destination $BaseState -Backup $baseBackup -Existed $baseExisted
            throw
        }

        if ($writeShared) { Complete-Backup $SharedState }
        if ($writeLocal) { Complete-Backup $LocalState }
        Complete-Backup $BaseState
        $report = Get-Content -LiteralPath $generatedReport -Raw | ConvertFrom-Json
        $conflictCount = @($report.conflicts).Count
        if ($conflictCount -gt 0) {
            Ensure-Dir $ConflictDir
            $conflictPath = Join-Path $ConflictDir "$(Get-Date -Format yyyyMMdd-HHmmssfff)-$safeDeviceName.json"
            Copy-Item -LiteralPath $generatedReport -Destination $conflictPath -Force
            Write-Host "Merged with $conflictCount same-field conflict(s); this machine's change won and backups were retained." -ForegroundColor Yellow
            Write-Host "Conflict report: $conflictPath" -ForegroundColor Yellow
        } else {
            $message = switch ($Mode) {
                "pull" { "Shared sidebar organization was installed locally as authoritative." }
                "push" { "Local sidebar organization was published to the shared primary as authoritative." }
                default { "Sidebar organization merged without conflicts." }
            }
            Write-Host $message -ForegroundColor Green
        }
    } finally {
        if (Test-Path -LiteralPath $work -PathType Container) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-FreshOtherRunningDevices {
    if (-not (Test-Path -LiteralPath $RunningMarker -PathType Leaf)) { return @() }
    try {
        $marker = Get-Content -LiteralPath $RunningMarker -Raw -Encoding UTF8 | ConvertFrom-Json
        $cutoff = [DateTimeOffset]::UtcNow.AddMinutes(-5)
        return @($marker.devices.PSObject.Properties | Where-Object {
            if ($_.Name -ieq $env:COMPUTERNAME) { return $false }
            $heartbeat = [DateTimeOffset]::MinValue
            [DateTimeOffset]::TryParse([string]$_.Value.heartbeatAt, [ref]$heartbeat) -and $heartbeat -ge $cutoff
        } | ForEach-Object { $_.Name })
    } catch {
        Write-Host "Session index repair skipped because the running marker is unreadable: $($_.Exception.Message)" -ForegroundColor Yellow
        return @("unknown-device")
    }
}

function Repair-SessionIndexIfSafe {
    if (-not (Test-Path -LiteralPath $SessionIndex -PathType Leaf)) { return }
    if (-not (Test-Path -LiteralPath $SessionIndexRepairHelper -PathType Leaf)) {
        throw "Missing session index repair helper: $SessionIndexRepairHelper"
    }
    $otherDevices = @(Get-FreshOtherRunningDevices)
    if ($otherDevices.Count -gt 0) {
        Write-Host "Session index deduplication deferred while another device is active: $($otherDevices -join ', ')" -ForegroundColor Yellow
        return
    }

    $inputHash = Get-FullHashOrMissing $SessionIndex
    $node = Get-NodeExecutable
    $work = Join-Path ([IO.Path]::GetTempPath()) "codexkit-session-index-$PID-$([guid]::NewGuid().ToString('N'))"
    Ensure-Dir $work
    $generated = Join-Path $work "session_index.jsonl"
    $reportPath = Join-Path $work "report.json"
    try {
        & $node $SessionIndexRepairHelper --input $SessionIndex --output $generated --report-output $reportPath
        if ($LASTEXITCODE -ne 0) { throw "Session index repair helper returned exit code $LASTEXITCODE." }
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$report.duplicate_rows -le 0) {
            Write-Host "Session index already contains one latest row per task." -ForegroundColor DarkGreen
            return
        }

        Assert-InputUnchanged -Path $SessionIndex -ExpectedHash $inputHash -Label "Session index"

        $backupRoot = Join-Path $LocalStateRoot "session-index-backups"
        Ensure-Dir $backupRoot
        $backup = Join-Path $backupRoot "session_index.jsonl.backup.$(Get-Date -Format yyyyMMdd-HHmmssfff)"
        Copy-Item -LiteralPath $SessionIndex -Destination $backup -Force
        try {
            Replace-FromGenerated -Generated $generated -Destination $SessionIndex
        } catch {
            Restore-File -Destination $SessionIndex -Backup $backup -Existed $true
            throw
        }
        $retained = @(Get-ChildItem -LiteralPath $backupRoot -File -Filter "session_index.jsonl.backup.*" |
            Sort-Object LastWriteTime -Descending)
        foreach ($expired in @($retained | Select-Object -Skip 1)) {
            try { Remove-Item -LiteralPath $expired.FullName -Force }
            catch { Write-Warning "Could not remove expired session-index backup $($expired.FullName): $($_.Exception.Message)" }
        }
        Write-Host "Session index deduplicated: $($report.input_rows) -> $($report.output_rows) rows; latest title retained for $($report.duplicate_ids) duplicated task IDs." -ForegroundColor Green
        Write-Host "One device-local rollback copy retained: $backup" -ForegroundColor DarkCyan
    } finally {
        if (Test-Path -LiteralPath $work -PathType Container) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Repair-ThreadCatalog {
    if (-not (Test-Path -LiteralPath $ThreadCatalogRepairHelper -PathType Leaf)) {
        throw "Missing thread catalog repair helper: $ThreadCatalogRepairHelper"
    }
    if (-not (Test-Path -LiteralPath $ThreadCatalogDatabase -PathType Leaf)) {
        Write-Host "Local thread catalog does not exist yet; Codex will create it on first launch." -ForegroundColor Yellow
        return [pscustomobject]@{
            status = "database-missing"
            inserted_count = 0
            unresolved_count = 0
            rollout_conflict_count = 0
            automation_history_rollouts = 0
            automation_history_cataloged = 0
            automation_history_inserted_count = 0
            automation_history_path_repaired_count = 0
            automation_history_unresolved_count = 0
            corrupt_rollout_copy_count = 0
        }
    }
    foreach ($requiredPath in @($SessionsRoot, $ArchivedSessionsRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
            throw "Missing shared session directory required for thread catalog repair: $requiredPath"
        }
    }
    if (-not (Test-Path -LiteralPath $SessionIndex -PathType Leaf)) {
        throw "Missing shared session title index required for thread catalog repair: $SessionIndex"
    }

    $node = Get-NodeExecutable
    $sessionIndexInputHash = Get-FullHashOrMissing $SessionIndex
    $work = Join-Path ([IO.Path]::GetTempPath()) "codexkit-thread-catalog-$PID-$([guid]::NewGuid().ToString('N'))"
    Ensure-Dir $work
    $reportPath = Join-Path $work "report.json"
    try {
        $nodeOutput = @(& $node --no-warnings $ThreadCatalogRepairHelper `
            --database $ThreadCatalogDatabase `
            --sessions-root $SessionsRoot `
            --archived-root $ArchivedSessionsRoot `
            --session-index $SessionIndex `
            --report-output $reportPath)
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
                Ensure-Dir $ThreadCatalogConflictDir
                $conflictReport = Join-Path $ThreadCatalogConflictDir "thread-catalog-conflict.$(Get-Date -Format yyyyMMdd-HHmmssfff).json"
                Copy-Item -LiteralPath $reportPath -Destination $conflictReport -Force
                throw "Thread catalog repair helper returned exit code $LASTEXITCODE. Conflict report: $conflictReport"
            }
            throw "Thread catalog repair helper returned exit code $LASTEXITCODE."
        }
        foreach ($line in $nodeOutput) { Write-Host $line -ForegroundColor DarkGreen }
        Assert-InputUnchanged -Path $SessionIndex -ExpectedHash $sessionIndexInputHash -Label "Session title index used for thread catalog repair"
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "Thread catalog repair helper did not produce its verification report."
        }
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$report.corrupt_rollout_copy_count -gt 0) {
            Ensure-Dir $ThreadCatalogConflictDir
            $warningReport = Join-Path $ThreadCatalogConflictDir "thread-catalog-warning.$(Get-Date -Format yyyyMMdd-HHmmssfff).json"
            Copy-Item -LiteralPath $reportPath -Destination $warningReport -Force
            $retainedWarnings = @(Get-ChildItem -LiteralPath $ThreadCatalogConflictDir -File -Filter "thread-catalog-warning.*.json" |
                Sort-Object LastWriteTime -Descending)
            foreach ($expired in @($retainedWarnings | Select-Object -Skip 2)) {
                try { Remove-Item -LiteralPath $expired.FullName -Force }
                catch { Write-Warning "Could not remove expired thread-catalog warning $($expired.FullName): $($_.Exception.Message)" }
            }
            Write-Warning "Ignored $($report.corrupt_rollout_copy_count) corrupt duplicate rollout copy/copies because a valid copy exists. Diagnostic: $warningReport"
        }
        if ([int]$report.unresolved_count -ne 0) {
            throw "Thread catalog verification found $($report.unresolved_count) unresolved task(s)."
        }
        if ([int]$report.rollout_conflict_count -ne 0) {
            throw "Thread catalog verification found $($report.rollout_conflict_count) divergent rollout copy/copies."
        }
        if ([int]$report.automation_history_unresolved_count -ne 0) {
            throw "Automation history verification found $($report.automation_history_unresolved_count) unresolved run(s)."
        }
        Add-Member -InputObject $report -NotePropertyName status -NotePropertyValue "reconciled" -Force
        return $report
    } finally {
        if (Test-Path -LiteralPath $work -PathType Container) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-SyncReceipt([ValidateSet("pull", "push", "merge")][string]$Mode, $ThreadCatalogReport) {
    Ensure-Dir $LocalStateRoot
    $payload = [ordered]@{
        schema_version = 2
        device = [string]$env:COMPUTERNAME
        mode = $Mode
        completed_at = [DateTimeOffset]::UtcNow.ToString("o")
        sync_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        merge_helper_sha256 = (Get-FileHash -LiteralPath $MergeHelper -Algorithm SHA256).Hash
        thread_catalog_helper_sha256 = (Get-FileHash -LiteralPath $ThreadCatalogRepairHelper -Algorithm SHA256).Hash
        thread_catalog_status = if ($ThreadCatalogReport) { [string]$ThreadCatalogReport.status } else { "not-requested" }
        thread_catalog_inserted_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.inserted_count } else { 0 }
        thread_catalog_unresolved_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.unresolved_count } else { 0 }
        automation_history_rollouts = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.automation_history_rollouts } else { 0 }
        automation_history_cataloged = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.automation_history_cataloged } else { 0 }
        automation_history_inserted_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.automation_history_inserted_count } else { 0 }
        automation_history_path_repaired_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.automation_history_path_repaired_count } else { 0 }
        automation_history_conflict_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.rollout_conflict_count } else { 0 }
        automation_history_unresolved_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.automation_history_unresolved_count } else { 0 }
        thread_catalog_corrupt_rollout_copy_count = if ($ThreadCatalogReport) { [int]$ThreadCatalogReport.corrupt_rollout_copy_count } else { 0 }
        thread_catalog_database_sha256 = Get-FullHashOrMissing $ThreadCatalogDatabase
        organization_sha256 = (Get-FileHash -LiteralPath $BaseState -Algorithm SHA256).Hash
        local_state_sha256 = (Get-FileHash -LiteralPath $LocalState -Algorithm SHA256).Hash
        shared_state_sha256 = (Get-FileHash -LiteralPath $SharedState -Algorithm SHA256).Hash
    }
    $temporary = "$SyncReceipt.tmp.$PID"
    [IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $SyncReceipt -Force
    Write-Host "Desktop sync receipt: $SyncReceipt" -ForegroundColor DarkCyan
}

function Backup-File($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $backup = "$Path.backup.$(Get-Date -Format yyyyMMdd-HHmmssfff)"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Complete-Backup($OriginalPath) {
    if ($BackupRetention -lt 0) { return }
    $parent = Split-Path -Parent $OriginalPath
    $name = Split-Path -Leaf $OriginalPath
    $backups = @(Get-ChildItem -LiteralPath $parent -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$name.backup.*" } |
        Sort-Object LastWriteTime -Descending)
    if ($backups.Count -le $BackupRetention) { return }
    $backups | Select-Object -Skip $BackupRetention | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host "Removed expired backup: $($_.FullName)" -ForegroundColor DarkGray
        } catch {
            Write-Warning "Could not remove expired backup $($_.FullName): $($_.Exception.Message)"
        }
    }
}

if (-not $Push -and -not $Pull -and -not $Merge -and -not $Status) {
    $Status = $true
}

$selectedCount = @(@($Push, $Pull, $Merge, $Status) | Where-Object { $_.IsPresent }).Count
if ($selectedCount -gt 1) {
    throw "Choose exactly one of -Push, -Pull, -Merge, or -Status."
}

if ($Push -or $Pull -or $Merge) {
    $mode = if ($Pull) { "pull" } elseif ($Push) { "push" } else { "merge" }
    Write-Host "Synchronize this machine's task/sidebar organization with OneDrive ($mode)." -ForegroundColor Cyan
    Write-Host "Run only while ChatGPT is closed on this machine." -ForegroundColor Yellow
    Merge-SidebarState -Mode $mode
    Repair-SessionIndexIfSafe
    $threadCatalogReport = if ($mode -eq "pull" -or $mode -eq "merge") { Repair-ThreadCatalog } else { $null }
    Write-SyncReceipt -Mode $mode -ThreadCatalogReport $threadCatalogReport
    return
}

Show-StateStatus
