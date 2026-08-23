[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ThreadId,
    [string]$Title,
    [string]$KitRoot,
    [string]$LocalStateRoot
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($KitRoot)) {
    $KitRoot = (Resolve-Path (Join-Path $scriptRoot '..\..\..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($LocalStateRoot)) {
    $LocalStateRoot = Join-Path $env:USERPROFILE '.local\state\codexkit'
}
$ThreadId = $ThreadId.ToLowerInvariant()
$sessionData = Join-Path $KitRoot 'session-data'
$sessionIndex = Join-Path $sessionData 'session_index.jsonl'
$recoveryFormatVersion = 2

function New-UuidV7 {
    $milliseconds = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $timestampHex = $milliseconds.ToString('x12')
    $randomBytes = New-Object byte[] 9
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $randomHex = -join ($randomBytes | ForEach-Object { $_.ToString('x2') })
    $variant = @('8', '9', 'a', 'b')[$randomBytes[0] -band 3]
    return '{0}-{1}-7{2}-{3}{4}-{5}' -f `
        $timestampHex.Substring(0, 8), $timestampHex.Substring(8, 4),
        $randomHex.Substring(0, 3), $variant, $randomHex.Substring(3, 3),
        $randomHex.Substring(6, 12)
}

function Get-Sha256([string]$Path) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Read-JsonLines([string]$Path) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
    try {
        $lineNumber = 0
        while (-not $reader.EndOfStream) {
            $lineNumber++
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                [pscustomobject]@{ Text = $line; Json = ($line | ConvertFrom-Json); Line = $lineNumber }
            }
            catch {
                throw "Malformed JSON at ${Path}:$lineNumber. No recovery copy was created."
            }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Read-FirstJsonLine([string]$Path) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
    try {
        $lineNumber = 0
        while (-not $reader.EndOfStream) {
            $lineNumber++
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                return [pscustomobject]@{ Text = $line; Json = ($line | ConvertFrom-Json); Line = $lineNumber }
            }
            catch {
                throw "Malformed JSON at ${Path}:$lineNumber. No recovery copy was created."
            }
        }
        return $null
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-ResponseMessageText($Payload) {
    return (@($Payload.content | ForEach-Object { [string]$_.text }) -join "`n")
}

function New-EventRow([string]$Timestamp, $Payload) {
    return [ordered]@{
        timestamp = $Timestamp
        type = 'event_msg'
        payload = $Payload
    }
}

if (-not (Test-Path -LiteralPath $sessionIndex -PathType Leaf)) {
    throw "Missing shared session index: $sessionIndex"
}
if (-not $WhatIfPreference -and $env:CODEXKIT_THREAD_RECOVERY_TEST_MODE -ne '1') {
    if (@(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'ChatGPT is running. Close it completely before creating a recovery copy.'
    }
}

$roots = @('sessions', 'archived_sessions') |
    ForEach-Object { Join-Path $sessionData $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$allRollouts = @(foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -File -Filter "*$ThreadId*.jsonl" -Recurse
})

$pages = foreach ($file in $allRollouts) {
    $first = Read-FirstJsonLine -Path $file.FullName
    if (-not $first -or $first.Json.type -ne 'session_meta') { continue }
    $metaId = [string]$(if ($first.Json.payload.id) { $first.Json.payload.id } else { $first.Json.payload.session_id })
    if ($metaId.ToLowerInvariant() -ne $ThreadId) { continue }
    [pscustomobject]@{
        Path = $file.FullName
        FirstTimestamp = [DateTimeOffset]::Parse([string]$first.Json.timestamp)
        HistoryMode = [string]$first.Json.payload.history_mode
    }
}
$pages = @($pages | Sort-Object FirstTimestamp, Path)
if ($pages.Count -eq 0) { throw "No rollout pages found for thread $ThreadId." }
if (-not ($pages | Where-Object HistoryMode -eq 'paginated')) {
    throw "Thread $ThreadId is not a paginated conversation."
}

$indexRows = New-Object Collections.Generic.List[object]
$sourceTitle = $null
foreach ($entry in Read-JsonLines -Path $sessionIndex) {
    $row = $entry.Json
    $indexRows.Add($row)
    if ([string]($row.id) -eq $ThreadId) {
        $sourceTitle = [string]$(if ($row.thread_name) { $row.thread_name } else { $row.title })
    }
}
if ([string]::IsNullOrWhiteSpace($Title)) {
    if ([string]::IsNullOrWhiteSpace($sourceTitle)) { $sourceTitle = $ThreadId }
    $suffix = -join ([char[]](0xFF08, 0x6062, 0x590D, 0x526F, 0x672C, 0xFF09))
    $Title = "${sourceTitle}${suffix}"
}

$existing = foreach ($file in $allRollouts) {
    $first = Read-FirstJsonLine -Path $file.FullName
    if ($first.Json.payload.recovered_from_thread_id -eq $ThreadId -and
        [int]$first.Json.payload.recovery_format_version -ge $recoveryFormatVersion) {
        [pscustomobject]@{ Id = [string]$first.Json.payload.id; Path = $file.FullName }
    }
}
if ($existing) {
    $match = $existing | Select-Object -First 1
    Write-Host "Recovery copy already exists: $($match.Id)" -ForegroundColor Green
    Write-Host $match.Path
    return
}

$newId = New-UuidV7
$destinationDir = Join-Path (Join-Path (Join-Path (Join-Path $sessionData 'sessions') (Get-Date -Format 'yyyy')) (Get-Date -Format 'MM')) (Get-Date -Format 'dd')
$destination = Join-Path $destinationDir ("rollout-{0}-{1}_{2}.jsonl" -f (Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'), $ThreadId, $newId)
$now = [DateTimeOffset]::UtcNow.ToString('o')
if (-not $PSCmdlet.ShouldProcess($destination, "Create legacy recovery copy of $ThreadId")) {
    Write-Host "Would combine $($pages.Count) page(s) into $destination"
    return
}

New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
$sourceHashes = @($pages | ForEach-Object {
    [pscustomobject]@{ Path = $_.Path; SHA256 = (Get-Sha256 -Path $_.Path) }
})
$lastUserMessageByTurn = @{}
foreach ($page in $pages) {
    foreach ($entry in Read-JsonLines -Path $page.Path) {
        if ($entry.Json.type -ne 'response_item' -or
            $entry.Json.payload.type -ne 'message' -or
            $entry.Json.payload.role -ne 'user') { continue }
        $turnId = [string]$entry.Json.payload.internal_chat_message_metadata_passthrough.turn_id
        if (-not [string]::IsNullOrWhiteSpace($turnId)) {
            $lastUserMessageByTurn[$turnId] = [string]$entry.Json.payload.id
        }
    }
}
$temporary = "$destination.tmp.$PID"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$writer = New-Object IO.StreamWriter($temporary, $false, $utf8NoBom)
try {
    foreach ($page in $pages) {
        foreach ($entry in Read-JsonLines -Path $page.Path) {
            if ($entry.Json.type -eq 'session_meta') {
                $entry.Json.payload.id = $newId
                $entry.Json.payload.session_id = $newId
                $entry.Json.payload.history_mode = 'legacy'
                if (-not $entry.Json.payload.PSObject.Properties['recovered_from_thread_id']) {
                    $entry.Json.payload | Add-Member -NotePropertyName recovered_from_thread_id -NotePropertyValue $ThreadId
                }
                if ($entry.Json.payload.PSObject.Properties['recovery_format_version']) {
                    $entry.Json.payload.recovery_format_version = $recoveryFormatVersion
                }
                else {
                    $entry.Json.payload | Add-Member -NotePropertyName recovery_format_version -NotePropertyValue $recoveryFormatVersion
                }
                $writer.WriteLine(($entry.Json | ConvertTo-Json -Depth 100 -Compress))
            }
            else {
                $isResponseItem = $entry.Json.type -eq 'response_item'
                $responseType = [string]$entry.Json.payload.type
                $role = [string]$entry.Json.payload.role
                if ($isResponseItem -and $responseType -eq 'reasoning') {
                    foreach ($summary in @($entry.Json.payload.summary)) {
                        $summaryText = [string]$(if ($summary -is [string]) { $summary } else { $summary.text })
                        if ([string]::IsNullOrWhiteSpace($summaryText)) { continue }
                        $event = New-EventRow -Timestamp ([string]$entry.Json.timestamp) -Payload ([ordered]@{
                            type = 'agent_reasoning'
                            text = $summaryText
                        })
                        $writer.WriteLine(($event | ConvertTo-Json -Depth 20 -Compress))
                    }
                }
                elseif ($isResponseItem -and $responseType -eq 'message' -and $role -eq 'assistant') {
                    $message = Get-ResponseMessageText -Payload $entry.Json.payload
                    if (-not [string]::IsNullOrWhiteSpace($message)) {
                        $event = New-EventRow -Timestamp ([string]$entry.Json.timestamp) -Payload ([ordered]@{
                            type = 'agent_message'
                            message = $message
                            phase = [string]$entry.Json.payload.phase
                            memory_citation = $null
                        })
                        $writer.WriteLine(($event | ConvertTo-Json -Depth 20 -Compress))
                    }
                }
                $writer.WriteLine($entry.Text)
                if ($isResponseItem -and $responseType -eq 'message' -and $role -eq 'user') {
                    $turnId = [string]$entry.Json.payload.internal_chat_message_metadata_passthrough.turn_id
                    $isActualUserMessage = -not [string]::IsNullOrWhiteSpace($turnId) -and
                        $lastUserMessageByTurn[$turnId] -eq [string]$entry.Json.payload.id
                    if ($isActualUserMessage) {
                        $message = Get-ResponseMessageText -Payload $entry.Json.payload
                        $event = New-EventRow -Timestamp ([string]$entry.Json.timestamp) -Payload ([ordered]@{
                            type = 'user_message'
                            client_id = [guid]::NewGuid().ToString()
                            message = $message
                            images = @()
                            local_images = @()
                            audio = @()
                            local_audio = @()
                            text_elements = @()
                        })
                        $writer.WriteLine(($event | ConvertTo-Json -Depth 20 -Compress))
                    }
                }
            }
        }
    }
}
finally {
    $writer.Dispose()
}
Move-Item -LiteralPath $temporary -Destination $destination

foreach ($sourceHash in $sourceHashes) {
    if ((Get-Sha256 -Path $sourceHash.Path) -ne $sourceHash.SHA256) {
        Remove-Item -LiteralPath $destination -Force
        throw "Source rollout changed during recovery: $($sourceHash.Path). The incomplete recovery copy was removed."
    }
}

$backupDir = Join-Path $LocalStateRoot 'thread-recovery-backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir ("session_index.jsonl.backup.{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
Copy-Item -LiteralPath $sessionIndex -Destination $backup
$indexRows.Add([pscustomobject]@{ id = $newId; thread_name = $Title; updated_at = $now })
$indexTemporary = "$sessionIndex.tmp.$PID"
$indexWriter = New-Object IO.StreamWriter($indexTemporary, $false, $utf8NoBom)
try {
    foreach ($row in $indexRows) {
        $indexWriter.WriteLine(($row | ConvertTo-Json -Depth 20 -Compress))
    }
}
finally {
    $indexWriter.Dispose()
}
Move-Item -LiteralPath $indexTemporary -Destination $sessionIndex -Force

[pscustomobject]@{
    SourceThreadId = $ThreadId
    RecoveryThreadId = $newId
    Title = $Title
    PageCount = $pages.Count
    Destination = $destination
    SessionIndexBackup = $backup
    SourceHashes = $sourceHashes
} | ConvertTo-Json -Depth 5
Write-Host 'Recovery copy created. Run Switch-CodexMachine.cmd -Action Pull before launching ChatGPT.' -ForegroundColor Green
