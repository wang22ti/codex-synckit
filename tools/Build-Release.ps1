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

$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-synckit-release-" + [guid]::NewGuid().ToString("N"))
$stageParent = Join-Path $buildRoot "stage"
$stageRoot = Join-Path $stageParent "codex-synckit-$Version"
$verifyParent = Join-Path $buildRoot "verify"
$verifiedRoot = Join-Path $verifyParent "codex-synckit-$Version"
$zipPath = Join-Path $OutputDirectory "codex-synckit-$Version.zip"
$hashPath = "$zipPath.sha256"

try {
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    $copyNames = @(
        ".github", ".gitattributes", ".gitignore", "CHANGELOG.md", "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md", "dashboard", "docs", "Install-CodexSyncKit.cmd",
        "Install-CodexSyncKit.ps1", "LICENSE",
        "README.md", "README.zh-CN.md", "SECURITY.md", "skill", "subsystems",
        "THIRD_PARTY_NOTICES.md", "tools"
    )
    foreach ($name in $copyNames) {
        $source = Join-Path $root $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $stageRoot -Recurse -Force
        }
    }

    & (Join-Path $PSScriptRoot "Test-PublicRelease.ps1") -Root $stageRoot

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stageParent,
        $zipPath,
        [IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    New-Item -ItemType Directory -Force -Path $verifyParent | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $verifyParent)
    & (Join-Path $PSScriptRoot "Test-PublicRelease.ps1") -Root $verifiedRoot

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        $hashPath,
        "$hash  $(Split-Path -Leaf $zipPath)`r`n",
        (New-Object Text.UTF8Encoding($false))
    )
} catch {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }
    throw
} finally {
    if (Test-Path -LiteralPath $buildRoot) {
        $resolvedBuildRoot = [IO.Path]::GetFullPath($buildRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedBuildRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove build path outside the temp directory: $resolvedBuildRoot"
        }
        Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
    }
}

Write-Host "[OK] release ZIP: $zipPath" -ForegroundColor Green
Write-Host "[OK] SHA-256: $hashPath" -ForegroundColor Green
