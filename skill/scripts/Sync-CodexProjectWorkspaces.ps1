#requires -version 5.1
[CmdletBinding()]
param(
    [switch]$Pull,
    [switch]$Push,
    [switch]$Status,
    [ValidateSet("", "Local", "Shared")]
    [string]$ConflictWinner = "",
    [string]$LocalRoot,
    [string]$SharedRoot,
    [string]$BaselinePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$KitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..\..")).Path
if ([string]::IsNullOrWhiteSpace($LocalRoot)) {
    $LocalRoot = Join-Path $env:USERPROFILE "Documents\Codex"
}
if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
    $SharedRoot = Join-Path $KitRoot "CodexProjects"
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $env:USERPROFILE ".local\state\codexkit\project-workspace-baseline.json"
}
$StateRoot = Split-Path -Parent $BaselinePath
$ConflictRoot = Join-Path $StateRoot "project-workspace-conflicts"
$QuarantineRoot = Join-Path $StateRoot "project-workspace-quarantine"

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-RealDirectory([string]$Path, [string]$Label) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSIsContainer) {
        throw "$Label must be a directory: $Path"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) {
        throw "$Label must be a real directory, not a junction or symbolic link: $Path"
    }
}

function Get-RelativePath([string]$Root, [string]$Path) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith("$rootPath\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped workspace root: $fullPath"
    }
    return $fullPath.Substring($rootPath.Length).TrimStart('\')
}

function Get-FileMap([string]$Root) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $map }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop | Sort-Object FullName)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$file.LinkType)) { continue }
        $relative = Get-RelativePath -Root $Root -Path $file.FullName
        $map[$relative] = [ordered]@{
            hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            length = [long]$file.Length
        }
    }
    return $map
}

function Read-Baseline {
    $map = @{}
    if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) { return $map }
    $document = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($document.files)) {
        if ($entry.path -and $entry.sha256) {
            $map[[string]$entry.path] = [string]$entry.sha256
        }
    }
    return $map
}

function Test-Same($EntryA, $EntryB) {
    if ($null -eq $EntryA -and $null -eq $EntryB) { return $true }
    return $null -ne $EntryA -and $null -ne $EntryB -and
        [string]$EntryA.hash -eq [string]$EntryB.hash
}

function Write-JsonAtomic([string]$Path, $Value) {
    Ensure-Directory (Split-Path -Parent $Path)
    $temporary = "$Path.tmp.$PID"
    try {
        $json = $Value | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporary, "$json`n", (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Write-ConflictReport([string]$Mode, [string[]]$Conflicts) {
    Ensure-Directory $ConflictRoot
    $path = Join-Path $ConflictRoot ("{0}-{1}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $Mode)
    $lines = @(
        "Codex project workspace synchronization stopped before changing files."
        "Mode: $Mode"
        "Local: $LocalRoot"
        "Shared: $SharedRoot"
        ""
    ) + $Conflicts
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
    return $path
}

function Copy-Verified([string]$Source, [string]$Destination, [string]$ExpectedHash, [string]$Side, [string]$Relative, [string]$Stamp) {
    Ensure-Directory (Split-Path -Parent $Destination)
    $temporary = "$Destination.codexkit-tmp-$PID"
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -Force
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $ExpectedHash) {
            throw "Copied file verification failed: $Source"
        }
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            Quarantine-File -Path $Destination -Side $Side -Relative $Relative -Stamp $Stamp
        }
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Quarantine-File([string]$Path, [string]$Side, [string]$Relative, [string]$Stamp) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $destination = Join-Path (Join-Path (Join-Path $QuarantineRoot $Stamp) $Side) $Relative
    Ensure-Directory (Split-Path -Parent $destination)
    Move-Item -LiteralPath $Path -Destination $destination -Force
}

function Write-Baseline {
    $local = Get-FileMap $LocalRoot
    $shared = Get-FileMap $SharedRoot
    $files = @()
    foreach ($relative in @($local.Keys | Sort-Object)) {
        if ($shared.ContainsKey($relative) -and (Test-Same $local[$relative] $shared[$relative])) {
            $files += [ordered]@{ path = $relative; sha256 = [string]$local[$relative].hash }
        }
    }
    Write-JsonAtomic -Path $BaselinePath -Value ([ordered]@{
        schema_version = 1
        updated_at = [DateTimeOffset]::UtcNow.ToString("o")
        device = [string]$env:COMPUTERNAME
        files = $files
    })
}

function Show-Status {
    $localItem = Get-Item -LiteralPath $LocalRoot -Force -ErrorAction SilentlyContinue
    $localReal = $localItem -and $localItem.PSIsContainer -and
        [string]::IsNullOrWhiteSpace([string]$localItem.LinkType)
    $localCount = (Get-FileMap $LocalRoot).Count
    $sharedCount = (Get-FileMap $SharedRoot).Count
    $baselineCount = (Read-Baseline).Count
    Write-Host "Codex project workspace sync status" -ForegroundColor Cyan
    Write-Host "Local real directory: $localReal ($LocalRoot)"
    Write-Host "Local/shared/baseline files: $localCount / $sharedCount / $baselineCount"
}

function Invoke-Sync([ValidateSet("pull", "push")][string]$Mode) {
    Ensure-Directory $SharedRoot
    if (-not (Test-Path -LiteralPath $LocalRoot)) { Ensure-Directory $LocalRoot }
    Assert-RealDirectory $LocalRoot "Local Codex workspace root"

    $local = Get-FileMap $LocalRoot
    $shared = Get-FileMap $SharedRoot
    $baseline = Read-Baseline
    $source = if ($Mode -eq "pull") { $shared } else { $local }
    $destination = if ($Mode -eq "pull") { $local } else { $shared }
    $sourceRoot = if ($Mode -eq "pull") { $SharedRoot } else { $LocalRoot }
    $destinationRoot = if ($Mode -eq "pull") { $LocalRoot } else { $SharedRoot }
    $destinationSide = if ($Mode -eq "pull") { "local" } else { "shared" }
    $copies = New-Object System.Collections.Generic.List[object]
    $deletions = New-Object System.Collections.Generic.List[object]
    $conflicts = New-Object System.Collections.Generic.List[string]
    $conflictPaths = New-Object System.Collections.Generic.List[string]
    $paths = @($local.Keys + $shared.Keys + $baseline.Keys | Sort-Object -Unique)

    foreach ($relative in $paths) {
        $sourceEntry = if ($source.ContainsKey($relative)) { $source[$relative] } else { $null }
        $destinationEntry = if ($destination.ContainsKey($relative)) { $destination[$relative] } else { $null }
        $baselineHash = if ($baseline.ContainsKey($relative)) { [string]$baseline[$relative] } else { $null }

        if (Test-Same $sourceEntry $destinationEntry) { continue }
        if ($baselineHash) {
            $sourceChanged = $null -eq $sourceEntry -or [string]$sourceEntry.hash -ne $baselineHash
            $destinationChanged = $null -eq $destinationEntry -or [string]$destinationEntry.hash -ne $baselineHash
            if ($sourceChanged -and $destinationChanged) {
                $conflicts.Add("$relative`tchanged on both sides") | Out-Null
                $conflictPaths.Add($relative) | Out-Null
            } elseif ($sourceChanged) {
                if ($null -eq $sourceEntry) {
                    $deletions.Add([pscustomobject]@{ Relative = $relative }) | Out-Null
                } else {
                    $copies.Add([pscustomobject]@{ Relative = $relative; Hash = [string]$sourceEntry.hash }) | Out-Null
                }
            }
            continue
        }

        if ($null -ne $sourceEntry -and $null -eq $destinationEntry) {
            $copies.Add([pscustomobject]@{ Relative = $relative; Hash = [string]$sourceEntry.hash }) | Out-Null
        } elseif ($null -ne $sourceEntry -and $null -ne $destinationEntry) {
            $conflicts.Add("$relative`tno common baseline and contents differ") | Out-Null
            $conflictPaths.Add($relative) | Out-Null
        }
    }

    foreach ($entry in $copies) {
        $destinationPath = Join-Path $destinationRoot $entry.Relative
        if (Test-Path -LiteralPath $destinationPath -PathType Container) {
            $conflicts.Add("$($entry.Relative)`tsource=file destination=directory") | Out-Null
            continue
        }
        $parentRelative = Split-Path -Parent $entry.Relative
        while (-not [string]::IsNullOrWhiteSpace($parentRelative)) {
            if ($destination.ContainsKey($parentRelative)) {
                $conflicts.Add("$($entry.Relative)`tdestination parent is a file: $parentRelative") | Out-Null
                break
            }
            $next = Split-Path -Parent $parentRelative
            if ($next -eq $parentRelative) { break }
            $parentRelative = $next
        }
    }

    if ($conflicts.Count -gt 0) {
        $report = Write-ConflictReport -Mode $Mode -Conflicts $conflicts.ToArray()
        $winner = $ConflictWinner
        if (-not $winner -and $env:CODEXKIT_INTERACTIVE_CONFLICTS -eq "1") {
            $shown = @($conflictPaths | Select-Object -First 8)
            $remaining = $conflictPaths.Count - $shown.Count
            $details = ($shown | ForEach-Object { "- $_" }) -join "`r`n"
            if ($remaining -gt 0) { $details += "`r`n- ... and $remaining more" }
            $message = @"
Project workspace conflicts need your decision:

$details

Yes = keep this computer's versions
No = keep OneDrive versions
Cancel = stop without changing files

Every replaced file will be saved in the CodexKit quarantine.
"@
            try {
                $shell = New-Object -ComObject WScript.Shell
                $choice = $shell.Popup($message, 0, "CodexKit project conflict", 35)
                if ($choice -eq 6) { $winner = "Local" }
                elseif ($choice -eq 7) { $winner = "Shared" }
            } catch {
                Write-Warning "Could not show the conflict resolver: $($_.Exception.Message)"
            }
        }
        if ($winner) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
            foreach ($relative in @($conflictPaths | Sort-Object -Unique)) {
                $winnerRoot = if ($winner -eq "Local") { $LocalRoot } else { $SharedRoot }
                $loserRoot = if ($winner -eq "Local") { $SharedRoot } else { $LocalRoot }
                $winnerEntry = if ($winner -eq "Local") { $local[$relative] } else { $shared[$relative] }
                $loserSide = if ($winner -eq "Local") { "shared" } else { "local" }
                $winnerPath = Join-Path $winnerRoot $relative
                $loserPath = Join-Path $loserRoot $relative
                if ($null -eq $winnerEntry) {
                    Quarantine-File -Path $loserPath -Side $loserSide -Relative $relative -Stamp $stamp
                } else {
                    Copy-Verified -Source $winnerPath -Destination $loserPath `
                        -ExpectedHash ([string]$winnerEntry.hash) -Side $loserSide `
                        -Relative $relative -Stamp $stamp
                }
            }
            Write-Host "Resolved $($conflictPaths.Count) project workspace conflict(s); winner: $winner." -ForegroundColor Yellow
            $script:ConflictWinner = ""
            Invoke-Sync -Mode $Mode
            return
        }
        throw "Project workspace $Mode found $($conflicts.Count) conflict(s). Nothing was changed. Review: $report"
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    foreach ($entry in $copies) {
        $sourcePath = Join-Path $sourceRoot $entry.Relative
        $destinationPath = Join-Path $destinationRoot $entry.Relative
        if (Test-Path -LiteralPath $destinationPath -PathType Container) {
            throw "A directory blocks the destination file: $destinationPath"
        }
        Copy-Verified -Source $sourcePath -Destination $destinationPath -ExpectedHash $entry.Hash `
            -Side $destinationSide -Relative $entry.Relative -Stamp $stamp
    }
    foreach ($entry in $deletions) {
        Quarantine-File -Path (Join-Path $destinationRoot $entry.Relative) -Side $destinationSide -Relative $entry.Relative -Stamp $stamp
    }

    Write-Baseline
    Write-Host "Project workspace $Mode complete: $($copies.Count) copied, $($deletions.Count) safely removed." -ForegroundColor Green
}

$modeCount = @($Pull, $Push, $Status | Where-Object { $_ }).Count
if ($modeCount -ne 1) { throw "Choose exactly one of -Pull, -Push, or -Status." }
if ($Status) { Show-Status; exit 0 }
if ($Pull) { Invoke-Sync -Mode pull; exit 0 }
Invoke-Sync -Mode push
