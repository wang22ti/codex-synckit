#requires -version 5.1
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSScriptRoot
$sync = Join-Path $scriptDir 'Sync-CodexProjectWorkspaces.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-cache-test-' + [guid]::NewGuid().ToString('N'))
$local = Join-Path $root 'local'
$shared = Join-Path $root 'shared'
$baseline = Join-Path $root 'baseline.json'
$link = Join-Path $local 'linked-cache'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    New-Item -ItemType Directory -Path $local, $shared, (Join-Path $root 'external') -Force | Out-Null
    $names = @(Get-Content (Join-Path $scriptDir 'OneDriveExcludedFolders.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    foreach ($name in $names) {
        $dir = Join-Path $local (Join-Path 'project' $name.ToUpperInvariant())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content (Join-Path $dir 'local-cache.dat') 'cache'
    }
    foreach ($relative in @('tmp\material.txt', '.git\unpushed-history', 'source\main.py', 'output\final.pdf', 'package-lock.json', '.next')) {
        $path = Join-Path $local $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Set-Content -LiteralPath $path 'preserve'
    }
    New-Item -ItemType Junction -Path $link -Target (Join-Path $root 'external') | Out-Null
    Set-Content (Join-Path $root 'external\target.txt') 'external dependency'
    foreach ($relative in @('project\node_modules\old.dat', 'linked-cache\previous.dat')) {
        $path = Join-Path $shared $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Set-Content -LiteralPath $path 'old shared content'
    }
    @{ files = @(
        @{path='project\node_modules\old.dat';sha256='OLD'},
        @{path='linked-cache\previous.dat';sha256='OLD'}
    ) } | ConvertTo-Json -Depth 4 | Set-Content $baseline
    foreach ($mode in @('-Push', '-Pull')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync $mode -LocalRoot $local -SharedRoot $shared -BaselinePath $baseline
        Assert ($LASTEXITCODE -eq 0) "$mode failed"
    }
    foreach ($name in $names) {
        Assert (-not (Test-Path (Join-Path $shared "project\$name\local-cache.dat"))) "Cache copied: $name"
    }
    foreach ($relative in @('tmp\material.txt', '.git\unpushed-history', 'source\main.py', 'output\final.pdf', 'package-lock.json', '.next')) {
        Assert (Test-Path -LiteralPath (Join-Path $shared $relative)) "Required file missing: $relative"
    }
    Assert (Test-Path (Join-Path $shared 'project\node_modules\old.dat')) 'Old excluded cloud copy deleted'
    Assert (Test-Path (Join-Path $shared 'linked-cache\previous.dat')) 'Old linked cloud copy deleted'
    Assert (-not (Test-Path (Join-Path $shared 'linked-cache\target.txt'))) 'Followed local junction'
    Assert (-not (Test-Path (Join-Path $root 'external\previous.dat'))) 'Wrote into external junction target'
    Assert (-not (Test-Path (Join-Path $local 'project\node_modules\old.dat'))) 'Pulled excluded old cache'
    $state = Get-Content $baseline -Raw | ConvertFrom-Json
    Assert (@($state.files | Where-Object { $_.path -match 'node_modules|linked-cache' }).Count -eq 0) 'Ignored old baseline entries retained'
    Write-Host '[OK] Cache exclusions, old baseline safety, link boundaries, and source preservation passed.'
} finally {
    if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
