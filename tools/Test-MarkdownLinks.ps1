#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')

foreach ($markdown in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -Filter "*.md")) {
    if ($markdown.FullName -match '\\(?:\.git|dist)\\') { continue }
    $text = Get-Content -LiteralPath $markdown.FullName -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text, '!?\[[^\]]*\]\((?<target>[^)]+)\)')) {
        $target = $match.Groups["target"].Value.Trim()
        if ($target.StartsWith("<") -and $target.EndsWith(">")) {
            $target = $target.Substring(1, $target.Length - 2)
        }
        if ($target -match '^(?:https?://|mailto:|#)') { continue }
        $target = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $decodedTarget = [Uri]::UnescapeDataString($target).Replace('/', '\')
        $resolved = [IO.Path]::GetFullPath((Join-Path $markdown.DirectoryName $decodedTarget))
        if (-not $resolved.StartsWith($Root + "\", [StringComparison]::OrdinalIgnoreCase) -and
            -not $resolved.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Markdown link escapes the repository: $($markdown.FullName) -> $target"
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            throw "Broken local Markdown link: $($markdown.FullName) -> $target"
        }
    }
}

Write-Host "[OK] local Markdown links passed: $Root" -ForegroundColor Green
