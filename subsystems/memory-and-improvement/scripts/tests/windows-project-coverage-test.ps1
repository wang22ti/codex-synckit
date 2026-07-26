$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('memory-project-coverage-' + [Guid]::NewGuid().ToString('N'))
$fakeUser = Join-Path $testRoot 'user'
$codexHome = Join-Path $fakeUser '.codex'
$codexBin = Join-Path $codexHome 'bin'
$kitRoot = Join-Path $fakeUser 'OneDrive\CodexKit'
$oneDriveProject = Join-Path $fakeUser 'OneDrive\Research\PaperA'
$localProject = Join-Path $fakeUser 'Documents\PaperB'
$missingProject = Join-Path $fakeUser 'Documents\Missing'
$globalProject = Join-Path $fakeUser 'global-memory\namespaces\user-profile'
$helperSource = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..\hooks\scripts\codex-bin\memory-project-coverage.ps1')
$hookSource = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..\hooks\scripts\codex-bin\memory-session-start.ps1')

try {
    foreach ($dir in @(
        $codexBin,
        (Join-Path $kitRoot 'memory-system'),
        $oneDriveProject,
        $localProject,
        $globalProject,
        (Join-Path $globalProject '.learnings')
    )) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $helperSource -Destination (Join-Path $codexBin 'memory-project-coverage.ps1')
    Copy-Item -LiteralPath $hookSource -Destination (Join-Path $codexBin 'memory-session-start.ps1')

    $projects = [ordered]@{
        'project-a' = [ordered]@{ id = 'project-a'; name = 'Paper A'; rootPaths = @($oneDriveProject) }
        'project-b' = [ordered]@{ id = 'project-b'; name = 'Paper B'; rootPaths = @($localProject) }
        'project-missing' = [ordered]@{ id = 'project-missing'; name = 'Missing'; rootPaths = @($missingProject) }
        'project-global' = [ordered]@{ id = 'project-global'; name = 'user-profile'; rootPaths = @($globalProject) }
    }
    [IO.File]::WriteAllText(
        (Join-Path $codexHome '.codex-global-state.json'),
        ([ordered]@{ 'local-projects' = $projects } | ConvertTo-Json -Depth 8),
        (New-Object Text.UTF8Encoding($false))
    )

    $helper = Join-Path $codexBin 'memory-project-coverage.ps1'
    $report = & $helper `
        -CurrentCwd $oneDriveProject `
        -ReconcileSidebar `
        -IncludeCurrent `
        -PassThru `
        -CodexHomeOverride $codexHome `
        -KitRootOverride $kitRoot

    Assert-True (Test-Path -LiteralPath (Join-Path $oneDriveProject '.learnings\SUMMARY.md')) 'OneDrive project memory was initialized'
    Assert-True (Test-Path -LiteralPath (Join-Path $localProject '.learnings\LEARNINGS.md')) 'local project memory was initialized'
    Assert-True (-not (Test-Path -LiteralPath $missingProject)) 'missing sidebar root was not fabricated'
    Assert-True ((@($report.projects | Where-Object status -eq 'global-managed')).Count -eq 1) 'global namespace was treated as globally managed'
    Assert-True ($report.current_project_root -eq $oneDriveProject) 'current project resolved to sidebar root'

    $registry = Get-Content -LiteralPath (Join-Path $kitRoot 'memory-system\project-memory-registry.tsv') -Encoding UTF8
    Assert-True ((@($registry | Where-Object { $_ -match '^onedrive\t-\tResearch/PaperA/\.learnings$' })).Count -eq 1) 'OneDrive registry row was written'
    Assert-True ((@($registry | Where-Object { $_ -match '^local\t[^\t]+\t.*Documents\\PaperB\\\.learnings$' })).Count -eq 1) 'local registry row was written'
    Assert-True (-not ($registry -match 'user-profile')) 'global namespace was not duplicated in project registry'

    $null = & $helper `
        -CurrentCwd $oneDriveProject `
        -ReconcileSidebar `
        -IncludeCurrent `
        -PassThru `
        -CodexHomeOverride $codexHome `
        -KitRootOverride $kitRoot
    $registryAgain = Get-Content -LiteralPath (Join-Path $kitRoot 'memory-system\project-memory-registry.tsv') -Encoding UTF8
    Assert-True ((@($registryAgain | Where-Object { $_ -match 'PaperA/\.learnings$' })).Count -eq 1) 'reconciliation is idempotent'
    Assert-True ((@($registryAgain | Where-Object { $_ -match 'PaperB\\\.learnings$' })).Count -eq 1) 'local reconciliation is idempotent'

    Write-Output 'windows-project-coverage-test: PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing test cleanup outside temp: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
