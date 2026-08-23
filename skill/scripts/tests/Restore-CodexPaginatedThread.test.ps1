$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-thread-recovery-test-{0}" -f [guid]::NewGuid())
$kit = Join-Path $testRoot 'CodexKit'
$sessionRoot = Join-Path $kit 'session-data\sessions\2026\08\21'
$state = Join-Path $testRoot 'state'
$script = Join-Path $PSScriptRoot '..\Restore-CodexPaginatedThread.ps1'
$sourceId = '019f1000-0000-7000-8000-000000000001'

try {
    New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null
    $meta1 = '{"timestamp":"2026-08-21T01:00:00Z","type":"session_meta","payload":{"id":"' + $sourceId + '","session_id":"' + $sourceId + '","timestamp":"2026-08-21T01:00:00Z","cwd":"C:\\\\project","history_mode":"paginated"}}'
    $meta2 = '{"timestamp":"2026-08-21T02:00:00Z","type":"session_meta","payload":{"id":"' + $sourceId + '","session_id":"' + $sourceId + '","timestamp":"2026-08-21T02:00:00Z","cwd":"C:\\\\project","history_mode":"paginated"}}'
    $page1 = Join-Path $sessionRoot ("rollout-a-$sourceId.jsonl")
    $page2 = Join-Path $sessionRoot ("rollout-b-${sourceId}_019f1000-0000-7000-8000-000000000002.jsonl")
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    $turn1 = '019f1000-0000-7000-8000-000000000003'
    $turn2 = '019f1000-0000-7000-8000-000000000004'
    $page1Rows = @(
        $meta1,
        ('{"timestamp":"2026-08-21T01:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"' + $turn1 + '"}}'),
        ('{"timestamp":"2026-08-21T01:00:02Z","type":"response_item","payload":{"type":"message","id":"wrapper","role":"user","content":[{"type":"input_text","text":"wrapper"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn1 + '"}}}'),
        ('{"timestamp":"2026-08-21T01:00:03Z","type":"response_item","payload":{"type":"message","id":"actual-1","role":"user","content":[{"type":"input_text","text":"actual user one"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn1 + '"}}}'),
        ('{"timestamp":"2026-08-21T01:00:04Z","type":"response_item","payload":{"type":"reasoning","id":"reason-1","summary":[{"type":"summary_text","text":"reason one"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn1 + '"}}}'),
        ('{"timestamp":"2026-08-21T01:00:05Z","type":"response_item","payload":{"type":"message","id":"assistant-1","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"assistant one"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn1 + '"}}}'),
        ('{"timestamp":"2026-08-21T01:01:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"' + $turn1 + '"}}')
    )
    $page2Rows = @(
        $meta2,
        ('{"timestamp":"2026-08-21T02:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"' + $turn2 + '"}}'),
        ('{"timestamp":"2026-08-21T02:00:02Z","type":"response_item","payload":{"type":"message","id":"actual-2","role":"user","content":[{"type":"input_text","text":"actual user two"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn2 + '"}}}'),
        ('{"timestamp":"2026-08-21T02:00:03Z","type":"response_item","payload":{"type":"message","id":"assistant-2","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"assistant two"}],"internal_chat_message_metadata_passthrough":{"turn_id":"' + $turn2 + '"}}}'),
        ('{"timestamp":"2026-08-21T02:01:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"' + $turn2 + '"}}')
    )
    [IO.File]::WriteAllLines($page1, $page1Rows, $utf8NoBom)
    [IO.File]::WriteAllLines($page2, $page2Rows, $utf8NoBom)
    $index = Join-Path $kit 'session-data\session_index.jsonl'
    [IO.File]::WriteAllText($index, ('{"id":"' + $sourceId + '","thread_name":"Original","updated_at":"2026-08-21T01:00:00Z"}' + "`n"), $utf8NoBom)
    $before1 = (Get-FileHash $page1 -Algorithm SHA256).Hash
    $before2 = (Get-FileHash $page2 -Algorithm SHA256).Hash

    $env:CODEXKIT_THREAD_RECOVERY_TEST_MODE = '1'
    & $script -ThreadId $sourceId -KitRoot $kit -LocalStateRoot $state 6>&1 | Out-Null

    $copy = Get-ChildItem (Join-Path $kit 'session-data\sessions') -Recurse -Filter '*.jsonl' |
        Where-Object FullName -notin @($page1, $page2) |
        Select-Object -First 1
    Assert-True ($null -ne $copy) 'Recovery rollout was not created.'
    $rows = @(Get-Content $copy.FullName -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($rows.Count -eq 17) 'Recovery rollout did not contain every source row and compatibility event.'
    $metas = @($rows | Where-Object type -eq session_meta)
    Assert-True ($metas.Count -eq 2) 'Recovery rollout did not retain page metadata boundaries.'
    $newId = [string]$metas[0].payload.id
    Assert-True ($newId -ne $sourceId) 'Recovery rollout reused the source thread ID.'
    Assert-True (-not ($metas | Where-Object { $_.payload.history_mode -ne 'legacy' })) 'Recovery metadata was not converted to legacy mode.'
    Assert-True (-not ($metas | Where-Object { $_.payload.id -ne $newId -or $_.payload.session_id -ne $newId })) 'Recovery metadata IDs are inconsistent.'
    Assert-True (-not ($metas | Where-Object { $_.payload.recovered_from_thread_id -ne $sourceId })) 'Recovery provenance is missing.'
    Assert-True (-not ($metas | Where-Object { $_.payload.recovery_format_version -ne 2 })) 'Recovery format version is missing.'
    $userEvents = @($rows | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'user_message' })
    $agentEvents = @($rows | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'agent_message' })
    $reasoningEvents = @($rows | Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'agent_reasoning' })
    Assert-True ($userEvents.Count -eq 2) 'Recovery did not synthesize one user event per turn.'
    Assert-True (-not ($userEvents | Where-Object { $_.payload.message -eq 'wrapper' })) 'Injected wrapper was exposed as a user message.'
    Assert-True ($agentEvents.Count -eq 2) 'Recovery did not synthesize assistant events.'
    Assert-True ($reasoningEvents.Count -eq 1) 'Recovery did not synthesize reasoning summaries.'
    Assert-True ((Get-FileHash $page1 -Algorithm SHA256).Hash -eq $before1) 'First source page changed.'
    Assert-True ((Get-FileHash $page2 -Algorithm SHA256).Hash -eq $before2) 'Second source page changed.'
    $indexRows = @(Get-Content $index -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True (@($indexRows | Where-Object id -eq $newId).Count -eq 1) 'Recovery index row is missing or duplicated.'
    $suffix = -join ([char[]](0xFF08, 0x6062, 0x590D, 0x526F, 0x672C, 0xFF09))
    $actualTitle = [string](($indexRows | Where-Object id -eq $newId).thread_name)
    Assert-True ($actualTitle -eq "Original${suffix}") "Recovery title is incorrect: $actualTitle"

    & $script -ThreadId $sourceId -KitRoot $kit -LocalStateRoot $state 6>&1 | Out-Null
    $allCopies = @(Get-ChildItem (Join-Path $kit 'session-data\sessions') -Recurse -Filter '*.jsonl' | Where-Object FullName -notin @($page1, $page2))
    Assert-True ($allCopies.Count -eq 1) 'Repeated recovery created a duplicate copy.'
    Write-Host 'Restore-CodexPaginatedThread tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item Env:CODEXKIT_THREAD_RECOVERY_TEST_MODE -ErrorAction SilentlyContinue
    if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
