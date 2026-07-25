#requires -version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$')]
    [string]$Version = "0.1.0-alpha",
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root "dist"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')

& (Join-Path $PSScriptRoot "Test-PublicRelease.ps1") -Root $root

$stageParent = Join-Path ([IO.Path]::GetTempPath()) "codexkit-public-release"
$stageRoot = Join-Path $stageParent "codex-synckit-$Version"
if (Test-Path -LiteralPath $stageParent) { Remove-Item -LiteralPath $stageParent -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

$copyNames = @(
    ".github", ".gitignore", "CHANGELOG.md", "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md", "docs", "Install-CodexSyncKit.ps1", "LICENSE",
    "README.md", "README.zh-CN.md", "SECURITY.md", "skill", "THIRD_PARTY_NOTICES.md", "tools"
)
foreach ($name in $copyNames) {
    $source = Join-Path $root $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stageRoot -Recurse -Force
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$zipPath = Join-Path $OutputDirectory "codex-synckit-$Version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stageParent, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$zipPath.sha256"
[IO.File]::WriteAllText($hashPath, "$hash  $(Split-Path -Leaf $zipPath)`r`n", (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $stageParent -Recurse -Force

Write-Host "[OK] release ZIP: $zipPath" -ForegroundColor Green
Write-Host "[OK] SHA-256: $hashPath" -ForegroundColor Green
