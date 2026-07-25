#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$gitMetadataRoot = Join-Path $Root ".git"

function Test-IsGitMetadata([string]$Path) {
    return $Path.Equals($gitMetadataRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($gitMetadataRoot + "\", [StringComparison]::OrdinalIgnoreCase)
}

$required = @(
    ".github\workflows\test.yml",
    ".github\workflows\release.yml",
    ".github\ISSUE_TEMPLATE\bug_report.yml",
    ".github\ISSUE_TEMPLATE\feature_request.yml",
    ".github\ISSUE_TEMPLATE\config.yml",
    ".github\PULL_REQUEST_TEMPLATE.md",
    ".gitattributes",
    ".gitignore",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "Install-CodexSyncKit.cmd",
    "Install-CodexSyncKit.ps1",
    "LICENSE",
    "README.md",
    "README.zh-CN.md",
    "SECURITY.md",
    "THIRD_PARTY_NOTICES.md",
    "docs\PRIVACY.md",
    "docs\UNINSTALL.md",
    "skill\SKILL.md",
    "skill\scripts\Export-CodexKit.ps1",
    "skill\scripts\tests\Install-CodexSyncKit.test.ps1",
    "subsystems\memory-and-improvement\SKILL.md",
    "tools\Test-MarkdownLinks.ps1",
    "tools\Test-MemorySubsystem.sh"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relative))) {
        throw "Required public-release file is missing: $relative"
    }
}

$allowedTopLevel = @(
    ".git", ".github", ".gitattributes", ".gitignore", "CHANGELOG.md", "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md", "dist", "docs", "Install-CodexSyncKit.cmd",
    "Install-CodexSyncKit.ps1", "LICENSE",
    "README.md", "README.zh-CN.md", "SECURITY.md", "skill", "subsystems",
    "THIRD_PARTY_NOTICES.md", "tools"
)
foreach ($entry in @(Get-ChildItem -LiteralPath $Root -Force)) {
    if ($allowedTopLevel -notcontains $entry.Name) {
        throw "Unexpected top-level release entry: $($entry.Name)"
    }
}

$forbiddenDirectoryNames = @(
    "session-data", "global-memory", "automations", "CodexProjects",
    "desktop-state", "environment", "profiles", "projects", "logs",
    ".learnings", "memory-system", "plugins", "network"
)
foreach ($directory in @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force |
        Where-Object { -not (Test-IsGitMetadata $_.FullName) })) {
    if ($forbiddenDirectoryNames -contains $directory.Name) {
        throw "Private-data directory is forbidden in a public release: $($directory.FullName)"
    }
}

$forbiddenFilePatterns = @(
    "auth.json", "history.jsonl", "*.pem", "*.p12", "*.pfx",
    "id_rsa*", "id_ed25519*", "*.env", ".env.*", "manifest.json"
)
foreach ($pattern in $forbiddenFilePatterns) {
    $match = Get-ChildItem -LiteralPath $Root -File -Recurse -Force -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-IsGitMetadata $_.FullName) } |
        Select-Object -First 1
    if ($match) { throw "Forbidden public-release file: $($match.FullName)" }
}

$textExtensions = @(
    ".ps1", ".mjs", ".js", ".json", ".yaml", ".yml", ".md", ".txt",
    ".csv", ".toml", ".cmd", ".vbs", ".sh", ".awk"
)
$profilePattern = [regex]::Escape("C:" + "\Users\") + '[^\\\s"''<>]+'
$mntProfilePattern = [regex]::Escape("/mnt/c/" + "Users/") + '[^/\s"''<>]+'
$homeProfilePattern = '(?<![A-Za-z0-9_])/' + 'Users/' + '[^/\s"''<>]+'
$secretPatterns = @(
    'AKIA[0-9A-Z]{16}',
    'gh[pousr]_[A-Za-z0-9]{20,}',
    'sk-[A-Za-z0-9_-]{20,}',
    '(?i)(api[_-]?key|access[_-]?token|password|client[_-]?secret)\s*[:=]\s*["''][^"''<>]{8,}["'']',
    [regex]::Escape("-----BEGIN " + "PRIVATE KEY-----")
)

foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)) {
    if (Test-IsGitMetadata $file.FullName) { continue }
    if ($file.FullName -match '\\dist\\') { continue }
    if ($file.Length -gt 5MB) {
        throw "Unexpected file larger than 5 MB in public source: $($file.FullName)"
    }
    if ($textExtensions -notcontains $file.Extension.ToLowerInvariant() -and
        $file.Name -notin @("LICENSE", ".gitignore")) { continue }
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($pattern in @($profilePattern, $mntProfilePattern, $homeProfilePattern)) {
        if ($text -match $pattern) { throw "User-profile path detected in public source: $($file.FullName)" }
    }
    foreach ($pattern in $secretPatterns) {
        if ($text -match $pattern) { throw "Potential credential detected in public source: $($file.FullName)" }
    }
}

foreach ($script in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -Filter "*.ps1")) {
    if (Test-IsGitMetadata $script.FullName) { continue }
    if ($script.FullName -match '\\dist\\') { continue }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for $($script.FullName): $($errors[0].Message)"
    }
}

foreach ($shellFile in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".sh", ".awk") })) {
    if (Test-IsGitMetadata $shellFile.FullName) { continue }
    if ($shellFile.FullName -match '\\dist\\') { continue }
    if ([IO.File]::ReadAllBytes($shellFile.FullName) -contains 13) {
        throw "Shell-compatible file must use LF line endings: $($shellFile.FullName)"
    }
}

if (Test-Path -LiteralPath (Join-Path $Root ".git")) {
    $trackedDist = @(& git -C $Root ls-files -- dist 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify whether dist artifacts are tracked."
    }
    if ($trackedDist.Count -gt 0) {
        throw "Generated dist artifacts must not be tracked: $($trackedDist -join ', ')"
    }
}

& (Join-Path $Root "tools\Test-MarkdownLinks.ps1") -Root $Root

Write-Host "[OK] public release gate passed: $Root" -ForegroundColor Green
