#requires -version 5.1
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'Export-CodexKit.ps1') -Raw
$start = $source.IndexOf('function Get-ManagedShortcutIcon(')
$end = $source.IndexOf('function Read-Shortcut(', $start)
. ([scriptblock]::Create($source.Substring($start, $end - $start)))
function Ensure-Dir($Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('codexkit-icon-test-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $testRoot 'local'
    $package = Join-Path $testRoot 'package'
    Ensure-Dir (Join-Path $package 'assets')
    $desktop = [pscustomobject]@{ Executable = 'C:\fake\ChatGPT.exe'; Package = [pscustomobject]@{ InstallLocation = $package } }
    if ((Get-ManagedShortcutIcon $desktop) -ne 'C:\fake\ChatGPT.exe,0') { throw 'Missing artwork must use executable fallback' }
    $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4nEAAAAASUVORK5CYII=')
    [IO.File]::WriteAllBytes((Join-Path $package 'assets\Square44x44Logo.targetsize-16_altform-unplated.png'), $png)
    $icon = Get-ManagedShortcutIcon $desktop
    $iconPath = $icon.Substring(0, $icon.Length - 2)
    $bytes = [IO.File]::ReadAllBytes($iconPath)
    if ($bytes.Length -ne (22 + $png.Length) -or [BitConverter]::ToUInt16($bytes,2) -ne 1 -or [BitConverter]::ToUInt16($bytes,4) -ne 1) { throw 'Invalid ICO container' }
    if ([Convert]::ToBase64String($bytes[22..($bytes.Length-1)]) -ne [Convert]::ToBase64String($png)) { throw 'Artwork pixels must be unchanged' }
    if ((Get-ManagedShortcutIcon $desktop) -ne $icon) { throw 'Icon path must be stable' }
    if ($source -notmatch 'Path = Join-Path \$programs "ChatGPT - CodexKit.lnk"') { throw 'Managed entry must have a distinct name' }
    if ($source -notmatch '\$shortcut.IconLocation = Get-ManagedShortcutIcon \$desktop') { throw 'Installer must assign official icon' }
    'Managed shortcut tests passed'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    if ([IO.Path]::GetFullPath($testRoot).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
