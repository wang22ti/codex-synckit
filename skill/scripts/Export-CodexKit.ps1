#requires -version 5.1
<#
.SYNOPSIS
  Extract your current Codex user setup into a portable CodexKit folder, usually under OneDrive.

.DESCRIPTION
  This script is designed for a Windows machine that already has your Codex skills, hooks,
  profiles, and global guidance configured locally. It copies the reusable parts into a
  CodexKit folder while deliberately excluding credentials, logs, caches, SSH keys, tokens,
  and other machine-local state. Conversation history and desktop organization are included
  by default because cross-machine task continuity is a core SyncKit feature.

  Default behavior is non-destructive: it only copies/extracts files into CodexKit and writes
  a manifest. It will not modify your existing Codex setup unless you pass -InstallLinks.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1 -DryRun

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1 -CreateZip

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1 -ExcludeSessions

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1 -InstallLinks

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Export-CodexKit.ps1 -DestinationRoot "D:\OneDrive\CodexKit" -ProjectRoots "D:\Code\repo1","D:\Code\repo2"
#>

[CmdletBinding()]
param(
    [string]$DestinationRoot,
    [string]$SourceCodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [string]$SourceAgentsRoot = $(Join-Path $env:USERPROFILE ".agents"),
    [string]$SourceGlobalMemory = $(Join-Path $env:USERPROFILE "global-memory"),
    [string]$MemoryTaskName = "Codex Memory Maintenance",
    [string[]]$SkillRoots = @(),
    [string[]]$ProjectRoots = @(),
    [switch]$ScanProjects,
    [int]$MaxProjectDepth = 4,
    [switch]$IncludeRawConfig,
    [switch]$IncludeSessions,
    [switch]$IncludeDesktopState,
    [switch]$ExcludeSessions,
    [switch]$ExcludeDesktopState,
    [switch]$IncludeMemorySubsystem,
    [switch]$ExcludeMemorySubsystem,
    [switch]$CreateZip,
    [switch]$InstallLinks,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($IncludeSessions -and $ExcludeSessions) {
    throw "Choose either -IncludeSessions or -ExcludeSessions, not both."
}
if ($IncludeDesktopState -and $ExcludeDesktopState) {
    throw "Choose either -IncludeDesktopState or -ExcludeDesktopState, not both."
}
if ($IncludeMemorySubsystem -and $ExcludeMemorySubsystem) {
    throw "Choose either -IncludeMemorySubsystem or -ExcludeMemorySubsystem, not both."
}
if (-not $PSBoundParameters.ContainsKey("IncludeSessions")) {
    $IncludeSessions = -not $ExcludeSessions
}
if (-not $PSBoundParameters.ContainsKey("IncludeDesktopState")) {
    $IncludeDesktopState = -not $ExcludeDesktopState
}
if (-not $PSBoundParameters.ContainsKey("IncludeMemorySubsystem")) {
    $IncludeMemorySubsystem = -not $ExcludeMemorySubsystem
}

$script:StartedAt = Get-Date
$script:Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:Actions = New-Object System.Collections.Generic.List[object]
$script:ManifestFiles = New-Object System.Collections.Generic.List[object]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:PreviousManagedPaths = @()
$script:ProtectedManagedPaths = @{}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    $script:Warnings.Add($Message) | Out-Null
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[SKIP] $Message" -ForegroundColor DarkGray
}

function Add-Action {
    param(
        [string]$Type,
        [string]$Source,
        [string]$Destination,
        [string]$Status,
        [string]$Note = ""
    )
    $script:Actions.Add([pscustomobject]@{
        time = (Get-Date).ToString("s")
        type = $Type
        source = $Source
        destination = $Destination
        status = $Status
        note = $Note
    }) | Out-Null
}

function Get-OneDriveRoot {
    $candidates = @(
        $env:OneDriveCommercial,
        $env:OneDriveConsumer,
        $env:OneDrive,
        (Join-Path $env:USERPROFILE "OneDrive")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return (Join-Path $env:USERPROFILE "OneDrive")
}

function Resolve-PathLoose {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    try {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expanded)
    } catch {
        return [System.IO.Path]::GetFullPath($expanded)
    }
}

function Join-PathMany {
    param([Parameter(Mandatory=$true)][string[]]$Parts)
    $Parts = @($Parts)
    if ($Parts.Count -eq 0) { return "" }
    $result = $Parts[0]
    for ($i = 1; $i -lt $Parts.Count; $i++) {
        $result = Join-Path $result $Parts[$i]
    }
    return $result
}

function ConvertTo-ArraySafe {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (Test-Path -LiteralPath $Path) { return }

    if ($DryRun) {
        Add-Action -Type "mkdir" -Source "" -Destination $Path -Status "dry-run"
        Write-Host "[DRY]  mkdir $Path" -ForegroundColor DarkCyan
    } else {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        Add-Action -Type "mkdir" -Source "" -Destination $Path -Status "created"
    }
}

function Is-SameFileHash {
    param([string]$A, [string]$B)
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    try {
        $ha = (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
        return $ha -eq $hb
    } catch {
        return $false
    }
}

function Add-ManifestFile {
    param([string]$Path, [string]$Category, [string]$Source)
    if ($DryRun -or -not (Test-Path -LiteralPath $Path)) { return }
    $relative = $null
    try {
        $relative = $Path.Substring($script:DestinationRoot.Length).TrimStart('\','/')
        $item = Get-Item -LiteralPath $Path -Force
        $hash = if (-not $item.PSIsContainer) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { $null }
        $script:ManifestFiles.Add([pscustomobject]@{
            category = $Category
            path = $relative
            source = $Source
            size_bytes = if ($item.PSIsContainer) { $null } else { $item.Length }
            sha256 = $hash
            modified = $item.LastWriteTime.ToString("s")
        }) | Out-Null
    } catch {
        if (-not [string]::IsNullOrWhiteSpace([string]$relative)) {
            $script:ProtectedManagedPaths[[string]$relative] = $true
        }
        Write-Warn2 "Could not add manifest entry for $Path : $($_.Exception.Message)"
    }
}

function Backup-ExistingFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $backup = "$Path.bak.$script:Timestamp"
    if ($DryRun) {
        Add-Action -Type "backup" -Source $Path -Destination $backup -Status "dry-run"
        Write-Host "[DRY]  backup $Path -> $backup" -ForegroundColor DarkCyan
    } else {
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Add-Action -Type "backup" -Source $Path -Destination $backup -Status "created"
    }
    return $backup
}

function Get-PreviousManagedPaths {
    $manifestPath = Join-Path $script:DestinationRoot "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return @() }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($manifest.files | ForEach-Object { [string]$_.path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        Write-Warn2 "Existing manifest is unreadable; stale-file cleanup is skipped."
        return @()
    }
}

function Remove-StaleManagedFiles {
    if (@($script:PreviousManagedPaths).Count -eq 0) { return }

    $current = @{}
    foreach ($entry in $script:ManifestFiles) {
        $current[[string]$entry.path] = $true
    }

    foreach ($relative in $script:PreviousManagedPaths) {
        if ($current.ContainsKey($relative)) { continue }
        if ($relative -match '^(session-data|desktop-state|global-memory|memory-system)[\\/]' -or
            $relative -match '^skills[\\/][^\\/]+[\\/]memory-and-improvement([\\/]|$)') {
            Write-Host "[KEEP] stale cleanup never removes conversation, desktop-state, or memory data: $relative" -ForegroundColor Yellow
            continue
        }
        if ($script:ProtectedManagedPaths.ContainsKey([string]$relative)) {
            Write-Host "[KEEP] manifest hashing failed; stale cleanup will not remove: $relative" -ForegroundColor Yellow
            continue
        }
        $candidate = Join-Path $script:DestinationRoot ($relative -replace '/', '\')
        $resolvedRoot = [IO.Path]::GetFullPath($script:DestinationRoot).TrimEnd('\')
        $resolvedCandidate = [IO.Path]::GetFullPath($candidate)
        if (-not $resolvedCandidate.StartsWith("$resolvedRoot\", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove stale path outside CodexKit: $resolvedCandidate"
        }
        if (-not (Test-Path -LiteralPath $resolvedCandidate -PathType Leaf)) { continue }
        if ($DryRun) {
            Write-Host "[DRY]  remove stale managed file $resolvedCandidate" -ForegroundColor DarkCyan
            continue
        }
        Remove-Item -LiteralPath $resolvedCandidate -Force
        Write-Host "[CLEAN] removed stale managed file: $resolvedCandidate" -ForegroundColor DarkGray

        $parent = Split-Path -Parent $resolvedCandidate
        while ($parent.StartsWith("$resolvedRoot\", [StringComparison]::OrdinalIgnoreCase) -and
               $parent -ne $resolvedRoot -and
               (Test-Path -LiteralPath $parent -PathType Container) -and
               @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $parent -Force
            $parent = Split-Path -Parent $parent
        }
    }
}

function Copy-FileSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string]$Category = "misc"
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-Skip "missing file: $Source"
        Add-Action -Type "copy-file" -Source $Source -Destination $Destination -Status "missing"
        return
    }

    Ensure-Directory (Split-Path -Parent $Destination)

    if (Test-Path -LiteralPath $Destination) {
        if (Is-SameFileHash -A $Source -B $Destination) {
            Write-Skip "unchanged: $Destination"
            Add-Action -Type "copy-file" -Source $Source -Destination $Destination -Status "unchanged"
            Add-ManifestFile -Path $Destination -Category $Category -Source $Source
            return
        }
        if (-not $Force) {
            Backup-ExistingFile -Path $Destination | Out-Null
        }
    }

    if ($DryRun) {
        Write-Host "[DRY]  copy $Source -> $Destination" -ForegroundColor DarkCyan
        Add-Action -Type "copy-file" -Source $Source -Destination $Destination -Status "dry-run"
    } else {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        Add-Action -Type "copy-file" -Source $Source -Destination $Destination -Status "copied"
        Add-ManifestFile -Path $Destination -Category $Category -Source $Source
    }
}

function Write-TextFileSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$Content,
        [string]$Category = "generated"
    )
    Ensure-Directory (Split-Path -Parent $Destination)
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $existing = Get-Content -LiteralPath $Destination -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $Content) {
            Add-Action -Type "write-file" -Source "generated" -Destination $Destination -Status "unchanged"
            Add-ManifestFile -Path $Destination -Category $Category -Source "generated"
            return
        }
        if (-not $Force) { Backup-ExistingFile -Path $Destination | Out-Null }
    }
    if ($DryRun) {
        Write-Host "[DRY]  write $Destination" -ForegroundColor DarkCyan
        Add-Action -Type "write-file" -Source "generated" -Destination $Destination -Status "dry-run"
    } else {
        Set-Content -LiteralPath $Destination -Value $Content -Encoding UTF8
        Add-Action -Type "write-file" -Source "generated" -Destination $Destination -Status "written"
        Add-ManifestFile -Path $Destination -Category $Category -Source "generated"
    }
}

function Test-ExcludedPath {
    param([System.IO.FileInfo]$File, [string]$Root)

    $relative = $File.FullName.Substring($Root.Length).TrimStart('\','/')
    $parts = $relative -split '[\\/]'
    $excludedDirs = @(
        ".git", ".svn", ".hg", "node_modules", ".venv", "venv", "env",
        "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".cache",
        "cache", "logs", "log", "sessions", "session", "tmp", "temp", ".sandbox"
    )

    foreach ($part in $parts) {
        if ($excludedDirs -contains $part) { return $true }
    }

    $name = $File.Name.ToLowerInvariant()
    $ext = $File.Extension.ToLowerInvariant()
    $excludedExact = @(
        "auth.json", "history.jsonl", "credentials.json", "credential.json",
        "id_rsa", "id_rsa.pub", "id_ed25519", "id_ed25519.pub",
        ".env", ".env.local", ".env.production", ".env.development",
        "known_hosts", "wandb.key", "hf_token", "openai_api_key"
    )
    if ($excludedExact -contains $name) { return $true }

    if ($ext -in @(".pem", ".key", ".p12", ".pfx", ".crt", ".cer")) { return $true }
    if ($ext -eq ".lock" -or $name.EndsWith(".lock")) { return $true }
    if ($name -match '(?i)\.(bak|backup)([-.].*)?$' -or $name -match '(?i)\.tmp([-.].*)?$') { return $true }
    if ($name -match '(?i)(secret|token|credential|password).*(\.json|\.txt|\.toml|\.yaml|\.yml)$') { return $true }

    return $false
}

function Copy-DirectorySafe {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string]$Category = "directory"
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Skip "missing directory: $Source"
        Add-Action -Type "copy-dir" -Source $Source -Destination $Destination -Status "missing"
        return
    }

    Ensure-Directory $Destination
    $root = (Resolve-Path -LiteralPath $Source).Path
    $files = Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        if (Test-ExcludedPath -File $file -Root $root) {
            Add-Action -Type "exclude" -Source $file.FullName -Destination "" -Status "excluded" -Note "sensitive/cache/log rule"
            continue
        }
        $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
        $destFile = Join-Path $Destination $relative
        Copy-FileSafe -Source $file.FullName -Destination $destFile -Category $Category
    }
}

function Sanitize-TextContent {
    param([string]$Content)
    if ($null -eq $Content) { return "" }

    $result = $Content
    $patterns = @(
        '(?im)^\s*([A-Za-z0-9_.-]*(api[_-]?key|token|secret|password|credential|authorization|bearer|hf[_-]?token|wandb[_-]?api[_-]?key)[A-Za-z0-9_.-]*)\s*=\s*(.+)$',
        '(?im)^\s*([A-Za-z0-9_.-]*(api[_-]?key|token|secret|password|credential|authorization|bearer|hf[_-]?token|wandb[_-]?api[_-]?key)[A-Za-z0-9_.-]*)\s*:\s*(.+)$'
    )

    foreach ($pattern in $patterns) {
        $result = [regex]::Replace($result, $pattern, { param($m)
            if ($m.Groups[0].Value -match '=') {
                return "$($m.Groups[1].Value) = `"<REDACTED>`""
            } else {
                return "$($m.Groups[1].Value): <REDACTED>"
            }
        })
    }

    # Redact inline bearer-like values while leaving command structure readable.
    $result = $result -replace '(?i)(Bearer\s+)[A-Za-z0-9._~+\-/]+=*', '$1<REDACTED>'
    $result = $result -replace '(?i)(sk-[A-Za-z0-9]{12,})', '<REDACTED_OPENAI_KEY>'
    $result = $result -replace '(?i)(hf_[A-Za-z0-9]{12,})', '<REDACTED_HF_TOKEN>'
    return $result
}

function Sanitize-FileToDestination {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string]$Category = "sanitized-config"
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
    $raw = Get-Content -LiteralPath $Source -Raw -ErrorAction Stop
    $sanitized = Sanitize-TextContent -Content $raw
    Write-TextFileSafe -Destination $Destination -Content $sanitized -Category $Category
}

function Convert-HooksTemplateText {
    param([string]$RawText)
    if ([string]::IsNullOrWhiteSpace($RawText)) { return $RawText }

    $text = $RawText
    $sourceHooks = Join-Path $script:SourceCodexHome "hooks"
    $sourceScripts = Join-Path $script:SourceCodexHome "scripts"
    $sourceBin = Join-Path $script:SourceCodexHome "bin"

    # Replace the most likely machine-local hook script folders with a portable placeholder.
    foreach ($pair in @(
        @{ From = $sourceHooks; To = "__CODEXKIT__\hooks\scripts" },
        @{ From = $sourceScripts; To = "__CODEXKIT__\hooks\scripts\codex-scripts" },
        @{ From = $sourceBin; To = "__CODEXKIT__\hooks\scripts\codex-bin" }
    )) {
        $jsonFrom = $pair.From.Replace('\', '\\')
        $jsonTo = $pair.To.Replace('\', '\\')
        $text = $text.Replace($jsonFrom, $jsonTo)
        $from1 = [regex]::Escape($pair.From)
        $from2 = [regex]::Escape(($pair.From -replace '\\','/'))
        $text = [regex]::Replace($text, $from1, $pair.To, 'IgnoreCase')
        $text = [regex]::Replace($text, $from2, ($pair.To -replace '\\','/'), 'IgnoreCase')
    }

    return $text
}

function Find-HookScriptReferences {
    param([string]$HooksJsonPath)
    $refs = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $HooksJsonPath -PathType Leaf)) { return $refs }

    $raw = Get-Content -LiteralPath $HooksJsonPath -Raw
    $commandPattern = '"command"\s*:\s*"((?:\\.|[^"])*)"'
    foreach ($commandMatch in [regex]::Matches($raw, $commandPattern)) {
        try {
            $command = ('"' + $commandMatch.Groups[1].Value + '"') | ConvertFrom-Json
        } catch {
            continue
        }

        $candidates = New-Object System.Collections.Generic.List[string]
        $fileMatch = [regex]::Match($command, '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))')
        if ($fileMatch.Success) {
            $value = if ($fileMatch.Groups[1].Success) { $fileMatch.Groups[1].Value } else { $fileMatch.Groups[2].Value }
            $candidates.Add($value) | Out-Null
        }

        foreach ($quotedMatch in [regex]::Matches($command, '(?i)"([^"]+\.(ps1|py|sh|cmd|bat|js|mjs|cjs|ts))"')) {
            $candidates.Add($quotedMatch.Groups[1].Value) | Out-Null
        }

        foreach ($value in $candidates) {
            if ($value -notmatch '(?i)\.(ps1|py|sh|cmd|bat|js|mjs|cjs|ts)$') { continue }
            $expanded = $value
            if ($expanded -match '^(?i)%USERPROFILE%[\\/]?(.*)$') {
                $expanded = Join-Path $env:USERPROFILE $Matches[1]
            } elseif ($expanded -match '^(?i)\$env:USERPROFILE[\\/]?(.*)$') {
                $expanded = Join-Path $env:USERPROFILE $Matches[1]
            }
            $expanded = $expanded -replace '/', '\'
            if (Test-Path -LiteralPath $expanded -PathType Leaf) {
                if (-not $refs.Contains($expanded)) { $refs.Add($expanded) | Out-Null }
            }
        }
    }

    return $refs
}

function Get-SkillRootSpecs {
    $specs = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    $builtin = @(
        @{ Path = (Join-Path $script:SourceAgentsRoot "skills"); Bucket = "agents-skills" },
        @{ Path = (Join-Path $script:SourceCodexHome "skills"); Bucket = "codex-skills" },
        @{ Path = (Join-Path $script:SourceCodexHome "minimax-skills"); Bucket = "minimax-skills" }
    )

    foreach ($entry in $builtin) {
        $candidate = Resolve-PathLoose $entry.Path
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $key = $resolved.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $specs.Add([pscustomobject]@{ root = $resolved; bucket = $entry.Bucket }) | Out-Null
        }
    }

    foreach ($customRoot in $SkillRoots) {
        if ([string]::IsNullOrWhiteSpace($customRoot)) { continue }
        $candidate = Resolve-PathLoose $customRoot
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $key = $resolved.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $bucket = Join-Path "custom" (Get-SafeSourceSuffix -Path $resolved)
        $specs.Add([pscustomobject]@{ root = $resolved; bucket = $bucket }) | Out-Null
    }

    return $specs
}

function Find-SkillFolders {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [int]$MaxDepth = 4
    )

    $result = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $result }

    $rootResolved = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\','/')

    # If the root itself is a skill folder, export it as one skill.
    if (Test-Path -LiteralPath (Join-Path $rootResolved "SKILL.md") -PathType Leaf) {
        $result.Add($rootResolved) | Out-Null
        return $result
    }

    $skillFiles = Get-ChildItem -LiteralPath $rootResolved -Filter "SKILL.md" -File -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($file in $skillFiles) {
        $dir = $file.DirectoryName.TrimEnd('\','/')
        $relative = $dir.Substring($rootResolved.Length).TrimStart('\','/')
        $relativeParts = $relative -split '[\\/]'
        if ($relativeParts -contains ".system") { continue }
        $depth = if ([string]::IsNullOrWhiteSpace($relative)) { 0 } else { ($relative -split '[\\/]').Count }
        if ($depth -gt $MaxDepth) { continue }

        # Avoid adding a nested skill if one of its ancestors was already added.
        $covered = $false
        foreach ($existing in $result) {
            if ($dir.StartsWith($existing.TrimEnd('\','/') + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
                $dir.StartsWith($existing.TrimEnd('\','/') + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $covered = $true
                break
            }
        }
        if (-not $covered) { $result.Add($dir) | Out-Null }
    }

    return $result
}

function Get-SafeSourceSuffix {
    param([string]$Path)
    $leaf = Split-Path -Leaf ($Path.TrimEnd('\','/'))
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "source" }
    return ($leaf -replace '[^A-Za-z0-9._-]', '-')
}

function Resolve-SkillDestination {
    param(
        [Parameter(Mandatory=$true)][string]$SkillFolder,
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][hashtable]$UsedNames
    )

    $name = Split-Path -Leaf ($SkillFolder.TrimEnd('\','/'))
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "skill" }

    $key = $name.ToLowerInvariant()
    if (-not $UsedNames.ContainsKey($key)) {
        $UsedNames[$key] = $SkillFolder
        return Join-Path $DestinationRoot $name
    }

    # Same skill name from another root. Keep both instead of merging or overwriting.
    $sourceSuffix = Get-SafeSourceSuffix -Path $Root
    $candidate = "{0}__from-{1}" -f $name, $sourceSuffix
    $i = 2
    while ($UsedNames.ContainsKey($candidate.ToLowerInvariant())) {
        $candidate = "{0}__from-{1}-{2}" -f $name, $sourceSuffix, $i
        $i++
    }
    $UsedNames[$candidate.ToLowerInvariant()] = $SkillFolder
    Write-Warn2 "Duplicate skill name '$name' found. Exporting this copy as '$candidate' from $Root"
    return Join-Path $DestinationRoot $candidate
}

function Export-Skills {
    Write-Info "Extracting user skills"
    $skillsDest = Join-Path $script:DestinationRoot "skills"
    Ensure-Directory $skillsDest

    $rootSpecs = @(Get-SkillRootSpecs)
    if ($rootSpecs.Count -eq 0) {
        Write-Warn2 "No skill roots found. Checked: $script:SourceAgentsRoot\skills, $script:SourceCodexHome\skills, $script:SourceCodexHome\minimax-skills"
        return
    }

    $summary = New-Object System.Collections.Generic.List[object]
    $usedNamesByBucket = @{}
    $exportedCount = 0

    foreach ($spec in $rootSpecs) {
        $root = $spec.root
        $bucket = $spec.bucket
        $bucketDest = Join-Path $skillsDest $bucket
        Ensure-Directory $bucketDest
        if (-not $usedNamesByBucket.ContainsKey($bucket)) { $usedNamesByBucket[$bucket] = @{} }
        $usedNames = $usedNamesByBucket[$bucket]

        Write-Info "Scanning skill root: $root -> skills\$bucket"
        $skillFolders = @(Find-SkillFolders -Root $root -MaxDepth 4)
        if ($skillFolders.Count -eq 0) {
            Write-Skip "no SKILL.md folders found under: $root"
            continue
        }

        foreach ($skillFolder in $skillFolders) {
            $skillName = Split-Path -Leaf ($skillFolder.TrimEnd('\','/'))
            if (-not $IncludeMemorySubsystem -and
                $skillName.Equals("memory-and-improvement", [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Skip "memory-and-improvement skill was explicitly excluded with the long-term memory subsystem"
                continue
            }
            $dest = Resolve-SkillDestination -SkillFolder $skillFolder -Root $root -DestinationRoot $bucketDest -UsedNames $usedNames
            Copy-DirectorySafe -Source $skillFolder -Destination $dest -Category "skills"
            $exportedCount++
            $summary.Add([pscustomobject]@{
                source_root = $root
                source_bucket = $bucket
                source_skill = $skillFolder
                exported_as = $dest.Substring($script:DestinationRoot.Length).TrimStart('\','/')
            }) | Out-Null
        }
    }

    if ($exportedCount -eq 0) {
        Write-Warn2 "Skill roots existed, but no valid skill folders containing SKILL.md were found."
    } else {
        Write-Ok "exported $exportedCount skill folder(s) from $($rootSpecs.Count) skill root(s)."
    }

    if (-not $DryRun -and $summary.Count -gt 0) {
        $csv = Join-Path $skillsDest "_skill-sources.csv"
        $summary | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
        Add-ManifestFile -Path $csv -Category "skills" -Source "generated"
    }
}

function Export-Hooks {
    Write-Info "Extracting hooks and hook scripts"
    $hooksDest = Join-Path $script:DestinationRoot "hooks"
    $scriptsDest = Join-PathMany @($script:DestinationRoot, "hooks", "scripts")
    Ensure-Directory $hooksDest
    Ensure-Directory $scriptsDest

    $hooksJson = Join-Path $script:SourceCodexHome "hooks.json"
    if (Test-Path -LiteralPath $hooksJson -PathType Leaf) {
        Copy-FileSafe -Source $hooksJson -Destination (Join-Path $hooksDest "hooks.source.json") -Category "hooks"
        $raw = Get-Content -LiteralPath $hooksJson -Raw
        $template = Convert-HooksTemplateText -RawText $raw
        $template = Sanitize-TextContent -Content $template
        Write-TextFileSafe -Destination (Join-Path $hooksDest "hooks.template.json") -Content $template -Category "hooks"

        $refs = @(Find-HookScriptReferences -HooksJsonPath $hooksJson)
        if ($refs.Count -gt 0) {
            $rows = New-Object System.Collections.Generic.List[object]
            $sourceBinRoot = (Join-Path $script:SourceCodexHome "bin").TrimEnd('\','/')
            foreach ($ref in $refs) {
                if ($ref.StartsWith($sourceBinRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $ref.Substring($sourceBinRoot.Length).TrimStart('\','/')
                    $dest = Join-PathMany @($scriptsDest, "codex-bin", $relative)
                } else {
                    $hash8 = (Get-FileHash -LiteralPath $ref -Algorithm SHA256).Hash.Substring(0,8).ToLowerInvariant()
                    $name = [System.IO.Path]::GetFileName($ref)
                    $dest = Join-PathMany @($scriptsDest, "external", "$hash8-$name")
                }
                Copy-FileSafe -Source $ref -Destination $dest -Category "hook-scripts"
                $rows.Add([pscustomobject]@{ source = $ref; extracted_as = $dest }) | Out-Null
            }
            if (-not $DryRun) {
                $csv = Join-Path $hooksDest "external-hook-paths.csv"
                $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
                Add-ManifestFile -Path $csv -Category "hooks" -Source "generated"
            }
        }
    } else {
        Write-Skip "no user hooks.json found at $hooksJson"
    }

    foreach ($dirName in @("hooks", "scripts")) {
        $srcDir = Join-Path $script:SourceCodexHome $dirName
        if (Test-Path -LiteralPath $srcDir -PathType Container) {
            $destSub = switch ($dirName) {
                "hooks" { $scriptsDest }
                "scripts" { Join-Path $scriptsDest "codex-scripts" }
            }
            Copy-DirectorySafe -Source $srcDir -Destination $destSub -Category "hook-scripts"
        }
    }
}

function Export-GlobalMemory {
    if (-not $IncludeMemorySubsystem) {
        Write-Skip "long-term memory subsystem was explicitly excluded"
        return
    }
    Write-Info "Extracting global memory"
    $destination = Join-Path $script:DestinationRoot "global-memory"
    if (-not (Test-Path -LiteralPath $script:SourceGlobalMemory -PathType Container)) {
        Write-Skip "no global memory found at $script:SourceGlobalMemory"
        Add-Action -Type "copy-dir" -Source $script:SourceGlobalMemory -Destination $destination -Status "missing"
        return
    }

    Copy-DirectorySafe -Source $script:SourceGlobalMemory -Destination $destination -Category "global-memory"
}

function Export-Sessions {
    if (-not $IncludeSessions) {
        Write-Skip "session export is disabled; use -IncludeSessions to include conversation history"
        return
    }

    Write-Info "Extracting Codex sessions (sensitive conversation history)"
    $sessionData = Join-Path $script:DestinationRoot "session-data"
    $activeSource = Join-Path $script:SourceCodexHome "sessions"
    $archivedSource = Join-Path $script:SourceCodexHome "archived_sessions"
    $indexSource = Join-Path $script:SourceCodexHome "session_index.jsonl"
    $activeDestination = Join-Path $sessionData "sessions"
    $archivedDestination = Join-Path $sessionData "archived_sessions"
    $indexDestination = Join-Path $sessionData "session_index.jsonl"

    Ensure-Directory $activeDestination
    Ensure-Directory $archivedDestination
    Copy-DirectorySafe -Source $activeSource -Destination $activeDestination -Category "sessions"
    Copy-DirectorySafe -Source $archivedSource -Destination $archivedDestination -Category "archived-sessions"
    Copy-FileSafe -Source $indexSource -Destination $indexDestination -Category "session-index"
}

function Export-DesktopState {
    if (-not $IncludeDesktopState) {
        Write-Skip "desktop state export is disabled; use -IncludeDesktopState to include sidebar/project UI state"
        return
    }

    Write-Info "Extracting Codex desktop state (sidebar/project UI state)"
    $desktopState = Join-Path $script:DestinationRoot "desktop-state"
    Ensure-Directory $desktopState
    Copy-FileSafe -Source (Join-Path $script:SourceCodexHome ".codex-global-state.json") -Destination (Join-Path $desktopState ".codex-global-state.json") -Category "desktop-state"
}

function Export-PluginInventory {
    Write-Info "Recording plugin inventory"
    $pluginRoot = Join-Path $script:SourceCodexHome "plugins\cache"
    if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
        Write-Skip "no plugin cache inventory found at $pluginRoot"
        return
    }

    $inventory = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $pluginRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $marketplace = $_
        Get-ChildItem -LiteralPath $marketplace.FullName -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $plugin = $_
            $versions = @(Get-ChildItem -LiteralPath $plugin.FullName -Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $inventory.Add([pscustomobject]@{
                marketplace = $marketplace.Name
                plugin = $plugin.Name
                versions = $versions
            }) | Out-Null
        }
    }

    $inventoryRows = $inventory.ToArray()
    $canonicalInventory = @(
        foreach ($entry in $inventoryRows) {
            $remoteMarketplace = ([string]$entry.marketplace) + "-remote"
            $hasRemoteReplacement = @($inventoryRows | Where-Object {
                $_.marketplace -eq $remoteMarketplace -and $_.plugin -eq $entry.plugin
            }).Count -gt 0
            if ($hasRemoteReplacement) {
                Write-Skip ("obsolete plugin cache alias {0}/{1}; using {2}/{1}" -f $entry.marketplace, $entry.plugin, $remoteMarketplace)
                continue
            }
            $entry
        }
    )

    $destination = Join-PathMany @($script:DestinationRoot, "plugins", "inventory.json")
    $content = $canonicalInventory | Sort-Object marketplace, plugin | ConvertTo-Json -Depth 5
    Write-TextFileSafe -Destination $destination -Content $content -Category "plugin-inventory"
}

function Export-MemoryScheduledTask {
    if (-not $IncludeMemorySubsystem) {
        Write-Skip "memory maintenance settings were explicitly excluded with the long-term memory subsystem"
        return
    }
    Write-Info "Extracting memory maintenance scheduled task"
    $taskDestination = Join-Path $script:DestinationRoot "scheduled-tasks"
    Ensure-Directory $taskDestination

    $portableWritten = $false
    try {
        $task = Get-ScheduledTask -TaskName $MemoryTaskName -ErrorAction Stop
        $taskInfo = Get-ScheduledTaskInfo -TaskName $MemoryTaskName -ErrorAction Stop
        $xml = Export-ScheduledTask -TaskName $MemoryTaskName -ErrorAction Stop
        $xml = $xml -replace 'encoding="UTF-16"', 'encoding="utf-8"'
        Write-TextFileSafe -Destination (Join-Path $taskDestination "memory-maintenance.source.xml") -Content $xml -Category "scheduled-task"

        $trigger = @($task.Triggers)[0]
        $mode = "fixed"
        $intervalMinutes = $null
        if ($trigger.Repetition -and -not [string]::IsNullOrWhiteSpace([string]$trigger.Repetition.Interval)) {
            $mode = "interval"
            $intervalMinutes = [int][Math]::Round([System.Xml.XmlConvert]::ToTimeSpan([string]$trigger.Repetition.Interval).TotalMinutes)
        }

        $start = if ($trigger.StartBoundary) { [datetime]$trigger.StartBoundary } else { Get-Date }
        $portable = [ordered]@{
            task_name = $MemoryTaskName
            mode = $mode
            scope = "both"
            interval_minutes = $intervalMinutes
            hour = $start.Hour
            minute = $start.Minute
            git_commit = "true"
            writeback = "true"
            skill_policy_writeback = "false"
            min_recurrence = 2
            source_action = [ordered]@{
                execute = @($task.Actions)[0].Execute
                arguments = @($task.Actions)[0].Arguments
            }
            source_status = [ordered]@{
                last_run_time = $taskInfo.LastRunTime
                last_task_result = $taskInfo.LastTaskResult
                next_run_time = $taskInfo.NextRunTime
            }
        }
        Write-TextFileSafe -Destination (Join-Path $taskDestination "memory-maintenance.portable.json") -Content ($portable | ConvertTo-Json -Depth 6) -Category "scheduled-task"
        $portableWritten = $true
    } catch {
        Write-Warn2 "Could not export scheduled task '$MemoryTaskName': $($_.Exception.Message)"
        Add-Action -Type "scheduled-task" -Source $MemoryTaskName -Destination $taskDestination -Status "missing-or-denied"
    }

    if (-not $portableWritten) {
        $installer = Join-Path $script:SourceCodexHome "skills\memory-and-improvement\scripts\maintenance\install-windows-maintenance.ps1"
        if (Test-Path -LiteralPath $installer -PathType Leaf) {
            try {
                $previewLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -TaskName $MemoryTaskName -ProjectRoot $env:USERPROFILE
                if ($LASTEXITCODE -ne 0) { throw "maintenance installer preview returned $LASTEXITCODE" }
                $preview = ($previewLines -join [Environment]::NewLine) | ConvertFrom-Json
                $start = Get-Date
                $portable = [ordered]@{
                    task_name = [string]$preview.task_name
                    mode = [string]$preview.mode
                    scope = [string]$preview.scope
                    interval_minutes = [int]$preview.interval_minutes
                    hour = $start.Hour
                    minute = $start.Minute
                    git_commit = "true"
                    writeback = "true"
                    skill_policy_writeback = "false"
                    min_recurrence = 2
                    source_action = $null
                    source_status = [ordered]@{
                        note = "Generated from memory-and-improvement installer defaults because Task Scheduler metadata was unavailable."
                    }
                }
                Write-TextFileSafe -Destination (Join-Path $taskDestination "memory-maintenance.portable.json") -Content ($portable | ConvertTo-Json -Depth 6) -Category "scheduled-task"
                Write-Warn2 "Scheduled-task XML was unavailable; exported portable task settings from the installed memory skill."
            } catch {
                Write-Warn2 "Could not generate fallback portable task settings: $($_.Exception.Message)"
            }
        }
    }
}

function Export-ConfigsAndRules {
    Write-Info "Extracting profiles, sanitized config, and global guidance"
    $profilesDest = Join-Path $script:DestinationRoot "profiles"
    $extractedDest = Join-Path $profilesDest "_extracted"
    $rulesDest = Join-Path $script:DestinationRoot "rules"
    Ensure-Directory $profilesDest
    Ensure-Directory $extractedDest
    Ensure-Directory $rulesDest

    $config = Join-Path $script:SourceCodexHome "config.toml"
    if (Test-Path -LiteralPath $config -PathType Leaf) {
        Sanitize-FileToDestination -Source $config -Destination (Join-Path $extractedDest "config.sanitized.toml") -Category "sanitized-config"
        if ($IncludeRawConfig) {
            $rawDest = Join-PathMany @($script:DestinationRoot, "local-only", "config.raw.toml")
            Write-Warn2 "-IncludeRawConfig is enabled. Raw config may contain machine-local or sensitive values: $rawDest"
            Copy-FileSafe -Source $config -Destination $rawDest -Category "local-only"
        }
    } else {
        Write-Skip "no config.toml found at $config"
    }

    if (Test-Path -LiteralPath $script:SourceCodexHome -PathType Container) {
        $profileFiles = Get-ChildItem -LiteralPath $script:SourceCodexHome -File -Force -Filter "*.config.toml" -ErrorAction SilentlyContinue
        foreach ($pf in $profileFiles) {
            Sanitize-FileToDestination -Source $pf.FullName -Destination (Join-Path $profilesDest $pf.Name) -Category "profiles"
        }

        foreach ($name in @("AGENTS.md", "AGENTS.override.md")) {
            $file = Join-Path $script:SourceCodexHome $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                Copy-FileSafe -Source $file -Destination (Join-PathMany @($rulesDest, "global", $name)) -Category "rules"
            }
        }

        foreach ($dirName in @("prompts", "templates", "commands", "snippets")) {
            $srcDir = Join-Path $script:SourceCodexHome $dirName
            if (Test-Path -LiteralPath $srcDir -PathType Container) {
                Copy-DirectorySafe -Source $srcDir -Destination (Join-Path $script:DestinationRoot $dirName) -Category $dirName
            }
        }
        if (Test-Path -LiteralPath (Join-Path $script:SourceCodexHome "rules") -PathType Container) {
            Write-Skip "machine-specific command approval rules are deliberately excluded: $script:SourceCodexHome\rules"
        }
    }
}

function Get-DefaultProjectSearchRoots {
    $roots = @(
        "D:\Code", "D:\Projects", "C:\Code", "C:\Projects",
        (Join-Path $env:USERPROFILE "source"),
        (Join-Path $env:USERPROFILE "projects"),
        (Join-Path $env:USERPROFILE "Documents\Code")
    )
    return $roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
}

function Get-DepthRelativeToRoot {
    param([string]$Root, [string]$Path)
    $rel = $Path.Substring($Root.Length).TrimStart('\','/')
    if ([string]::IsNullOrWhiteSpace($rel)) { return 0 }
    return (($rel -split '[\\/]').Count)
}

function Sanitize-NameForPath {
    param([string]$Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = -join ($Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    return ($safe -replace '\s+', '-')
}

function Export-ProjectCodexFiles {
    param([string[]]$Roots)
    $Roots = @($Roots)
    if ($Roots.Count -eq 0) { return }
    Write-Info "Extracting selected project-level Codex files"

    foreach ($rootInput in $Roots) {
        $root = Resolve-PathLoose $rootInput
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Write-Skip "project root missing: $rootInput"
            continue
        }

        $projectName = Sanitize-NameForPath (Split-Path -Leaf $root)
        if ([string]::IsNullOrWhiteSpace($projectName)) { $projectName = Sanitize-NameForPath (($root -replace '[:\\/]', '_')) }
        $destBase = Join-PathMany @($script:DestinationRoot, "projects", $projectName)

        foreach ($name in @("AGENTS.md", "AGENTS.override.md")) {
            $file = Join-Path $root $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                Copy-FileSafe -Source $file -Destination (Join-Path $destBase $name) -Category "project-rules"
            }
        }

        $projectCodex = Join-Path $root ".codex"
        if (Test-Path -LiteralPath $projectCodex -PathType Container) {
            Copy-DirectorySafe -Source $projectCodex -Destination (Join-Path $destBase ".codex") -Category "project-codex"
        }

        $projectSkills = Join-PathMany @($root, ".agents", "skills")
        if (Test-Path -LiteralPath $projectSkills -PathType Container) {
            Copy-DirectorySafe -Source $projectSkills -Destination (Join-PathMany @($destBase, ".agents", "skills")) -Category "project-skills"
        }
    }
}

function Find-ProjectRootsForScan {
    param([string[]]$BaseRoots)
    $found = New-Object System.Collections.Generic.List[string]

    foreach ($base in $BaseRoots) {
        $baseResolved = Resolve-PathLoose $base
        if (-not (Test-Path -LiteralPath $baseResolved -PathType Container)) { continue }
        $candidates = Get-ChildItem -LiteralPath $baseResolved -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
            (Get-DepthRelativeToRoot -Root $baseResolved -Path $_.FullName) -le $MaxProjectDepth
        }
        foreach ($dir in $candidates) {
            $hasCodex = Test-Path -LiteralPath (Join-Path $dir.FullName ".codex") -PathType Container
            $hasAgents = Test-Path -LiteralPath (Join-PathMany @($dir.FullName, ".agents", "skills")) -PathType Container
            $hasGuide = (Test-Path -LiteralPath (Join-Path $dir.FullName "AGENTS.md") -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir.FullName "AGENTS.override.md") -PathType Leaf)
            if ($hasCodex -or $hasAgents -or $hasGuide) {
                if (-not $found.Contains($dir.FullName)) { $found.Add($dir.FullName) | Out-Null }
            }
        }
    }

    return $found.ToArray()
}

function Write-GitIgnore {
    $content = @'
# CodexKit portable assets are syncable, but never commit/copy these local secrets or state files.
local-only/
*.zip
*.bak.*
logs/
cache/
sessions/
.sandbox/

# Codex local state
**/auth.json
**/history.jsonl

# Secrets and credentials
**/.env
**/.env.*
!**/.env.example
**/credentials.json
**/*credential*.json
**/*secret*.json
**/*token*.json
**/*password*.json
**/*.pem
**/*.key
**/*.p12
**/*.pfx
**/id_rsa*
**/id_ed25519*
'@
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot ".gitignore") -Content $content -Category "generated"
}

function Write-InstallHelper {
    $helper = @'
#requires -version 5.1
[CmdletBinding()]
param(
    [string]$KitRoot,
    [switch]$InstallSkillsLink,
    [switch]$InstallCodexSkillsLink,
    [switch]$InstallMinimaxSkillsLink,
    [switch]$InstallSessionLinks,
    [switch]$InstallDesktopStateLink,
    [switch]$InstallHooks,
    [switch]$InstallProfiles,
    [switch]$CaptureEnvironmentInventory,
    [switch]$InstallGlobalGuidanceLinks,
    [switch]$InstallGlobalMemory,
    [switch]$InstallGlobalMemoryLink,
    [switch]$InstallCodexProjectsLink,
    [switch]$MigrateExistingCodexProjects,
    [switch]$InstallAutomationsLink,
    [switch]$MigrateExistingAutomations,
    [switch]$InstallStartMenuShortcut,
    [switch]$InstallResidentStartMenuShortcut,
    [switch]$InstallMemoryTask,
    [switch]$RemoveMemoryTask,
    [switch]$EnableMemorySubsystem,
    [switch]$DisableMemorySubsystem,
    [switch]$OpenHooksTrust,
    [switch]$Recommended,
    [switch]$Status,
    [switch]$Repair,
    [string]$DocumentsRoot,
    [ValidateRange(0, 20)][int]$BackupRetention = 2,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($EnableMemorySubsystem -and $DisableMemorySubsystem) {
    throw "Choose either -EnableMemorySubsystem or -DisableMemorySubsystem, not both."
}

function Read-RequiredMemorySubsystemChoice {
    while ($true) {
        $answer = (Read-Host "Enable the optional long-term memory subsystem? Enter Y or N; there is no default").Trim()
        switch -Regex ($answer) {
            '^(?i:y|yes)$' { return $true }
            '^(?i:n|no)$' { return $false }
            default { Write-Host "Please enter Y or N. Pressing Enter alone does not select an option." -ForegroundColor Yellow }
        }
    }
}

$MemorySubsystemChoiceExplicit = [bool]($EnableMemorySubsystem -or $DisableMemorySubsystem)
if ($Recommended -and -not $MemorySubsystemChoiceExplicit) {
    $EnableMemorySubsystem = Read-RequiredMemorySubsystemChoice
    $DisableMemorySubsystem = -not $EnableMemorySubsystem
    $MemorySubsystemChoiceExplicit = $true
}
$MemorySubsystemEnabled = [bool]$EnableMemorySubsystem

function Remove-ExpiredBackups($Path) {
    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return }
    $backups = @(
        Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$leaf.backup.*" } |
            Sort-Object LastWriteTime -Descending
    )
    foreach ($backup in @($backups | Select-Object -Skip $BackupRetention)) {
        $resolvedParent = Resolve-FullPath $parent
        $resolvedBackup = Resolve-FullPath $backup.FullName
        if (-not $resolvedBackup.StartsWith("$resolvedParent\", [StringComparison]::OrdinalIgnoreCase) -or
            $backup.Name -notlike "$leaf.backup.*") {
            throw "Refusing to remove unexpected backup path: $($backup.FullName)"
        }
        if ($backup.PSIsContainer -and ($backup.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            [IO.Directory]::Delete($backup.FullName, $false)
        } elseif ($backup.PSIsContainer) {
            Remove-Item -LiteralPath $backup.FullName -Recurse -Force
        } else {
            Remove-Item -LiteralPath $backup.FullName -Force
        }
        Write-Host "Removed expired backup: $($backup.FullName)" -ForegroundColor DarkGray
    }
}

function Backup-Path($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $backup = "$Path.backup.$stamp"
    Move-Item -LiteralPath $Path -Destination $backup -Force
    Write-Host "Backed up: $Path -> $backup" -ForegroundColor Yellow
    return $backup
}

function Complete-Backup($Path) {
    Remove-ExpiredBackups $Path
}

function Remove-PathNode($Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $isDirectoryLink = $item.PSIsContainer -and
        -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)
    if ($isDirectoryLink) {
        [IO.Directory]::Delete($item.FullName, $false)
    } elseif ($item.PSIsContainer) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    } else {
        Remove-Item -LiteralPath $item.FullName -Force
    }
}

function Copy-DirectoryContents($Source, $Destination) {
    Ensure-Dir $Destination
    foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        $destinationPath = Join-Path $Destination $child.Name
        Copy-Item -LiteralPath $child.FullName -Destination $destinationPath -Recurse -Force
    }
}

function Clear-DirectoryContents($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)) {
        Remove-PathNode $child.FullName
    }
}

function Restore-Backup($Path, $Backup) {
    if ([string]::IsNullOrWhiteSpace([string]$Backup) -or -not (Test-Path -LiteralPath $Backup)) { return }
    Remove-PathNode $Path
    Move-Item -LiteralPath $Backup -Destination $Path -Force
    Write-Host "Restored original target after installation failure: $Path" -ForegroundColor Yellow
}

function Ensure-Dir($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function Test-DirectoryEmpty($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $true }
    return $null -eq (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1)
}

function Get-DirectoryFingerprint($Path) {
    $root = Resolve-FullPath $Path
    return @(
        Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($root.Length).TrimStart('\')
                $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                "$relative`t$($_.Length)`t$hash"
            }
    )
}

function Resolve-FullPath($Path) {
    if ([string]::IsNullOrWhiteSpace([string]$Path)) { return $null }
    try { return [IO.Path]::GetFullPath([string]$Path).TrimEnd('\') } catch { return ([string]$Path).TrimEnd('\') }
}

function Get-InstallStatePath {
    return (Join-Path $env:USERPROFILE ".local\state\codexkit\installation.json")
}

function Read-InstallState {
    $statePath = Get-InstallStatePath
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Write-InstallState {
    $statePath = Get-InstallStatePath
    Ensure-Dir (Split-Path -Parent $statePath)
    $startMenuMode = Get-ExistingStartMenuMode
    $state = [pscustomobject]@{
        schema_version = 1
        device_name = $env:COMPUTERNAME
        user_profile = Resolve-FullPath $env:USERPROFILE
        codex_home = Resolve-FullPath $CodexHome
        agents_root = Resolve-FullPath $AgentsRoot
        kit_root = Resolve-FullPath $KitRoot
        documents_root = Resolve-FullPath $DocumentsRoot
        codex_projects_link_enabled = [bool](Test-PathTargetsSource -Target $CodexProjectsTarget -Source $CodexProjectsSource)
        codex_projects_sync_enabled = [bool]$ProjectWorkspaceSyncEnabled
        automations_link_enabled = [bool](Test-PathTargetsSource -Target $AutomationsTarget -Source $AutomationsSource)
        memory_subsystem_enabled = [bool]$MemorySubsystemEnabled
        backup_retention = $BackupRetention
        start_menu_mode = $startMenuMode
        updated_at = (Get-Date).ToString("o")
    }
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}

function Test-PathTargetsSource($Target, $Source) {
    if (-not (Test-Path -LiteralPath $Target)) { return $false }
    $resolvedSource = Resolve-FullPath $Source
    $targetItem = Get-Item -LiteralPath $Target -Force
    foreach ($linkedTarget in @($targetItem.Target)) {
        if ((Resolve-FullPath $linkedTarget) -eq $resolvedSource) { return $true }
    }

    if (-not $targetItem.PSIsContainer -and (Test-Path -LiteralPath $Source -PathType Leaf)) {
        try {
            $resolvedTarget = Resolve-FullPath $Target
            $drivePrefix = ([IO.Path]::GetPathRoot($resolvedTarget)).TrimEnd('\')
            $hardLinks = @(& fsutil hardlink list $resolvedTarget 2>$null)
            foreach ($hardLink in $hardLinks) {
                $hardLinkPath = $hardLink.Trim()
                if (-not $hardLinkPath) { continue }
                if ($hardLinkPath.StartsWith('\')) {
                    $hardLinkPath = "$drivePrefix$hardLinkPath"
                }
                if ((Resolve-FullPath $hardLinkPath) -eq $resolvedSource) { return $true }
            }
        } catch {}
    }
    return $false
}

function Test-HooksFeatureEnabled {
    $configPath = Join-Path $CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $false }
    $inFeatures = $false
    foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
        if ($line -match '^\s*\[features\]\s*(?:#.*)?$') {
            $inFeatures = $true
            continue
        }
        if ($inFeatures -and $line -match '^\s*\[') { break }
        if ($inFeatures -and $line -match '^\s*hooks\s*=\s*true\s*(?:#.*)?$') { return $true }
    }
    return $false
}

function Get-ExpectedHooksContent {
    $template = Join-Path $KitRoot "hooks\hooks.template.json"
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $template -Raw
    $raw = $raw.Replace("__CODEXKIT__", $KitRoot.Replace('\', '\\'))
    $portableBin = Join-Path $KitRoot "hooks\scripts\codex-bin"
    $codexBinTarget = Join-Path $CodexHome "bin"
    return $raw.Replace($portableBin.Replace('\', '\\'), $codexBinTarget.Replace('\', '\\'))
}

function Test-HooksCurrent {
    $target = Join-Path $CodexHome "hooks.json"
    $expected = Get-ExpectedHooksContent
    if ($null -eq $expected -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { return $false }
    try {
        $bytes = [IO.File]::ReadAllBytes($target)
        if ($bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return $false
        }
        $installed = Get-Content -LiteralPath $target -Raw -Encoding UTF8
        $null = $installed | ConvertFrom-Json
        if ($installed.Trim() -ne $expected.Trim()) { return $false }
        foreach ($name in @("memory-session-start.ps1", "memory-user-prompt.ps1")) {
            $source = Join-Path $KitRoot "hooks\scripts\codex-bin\$name"
            $destination = Join-Path $CodexHome "bin\$name"
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
                -not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
                return $false
            }
        }
        return (Test-HooksFeatureEnabled)
    } catch {
        return $false
    }
}

function Get-MemoryTaskState {
    try {
        $task = Get-ScheduledTask -TaskName "Codex Memory Maintenance" -ErrorAction Stop
        return [pscustomobject]@{
            Available = $true
            Exists = $true
            State = [string]$task.State
            Arguments = [string]$task.Actions.Arguments
        }
    } catch {
        $message = $_.Exception.Message
        return [pscustomobject]@{
            Available = -not ($message -match 'Access is denied|鎷掔粷璁块棶')
            Exists = $false
            State = if ($message -match 'Access is denied|鎷掔粷璁块棶') { "unavailable" } else { "missing" }
            Arguments = ""
        }
    }
}

function Write-StatusRow($Name, $Healthy, $Detail) {
    $label = if ($Healthy) { "OK" } else { "NEEDS REPAIR" }
    $color = if ($Healthy) { "Green" } else { "Yellow" }
    Write-Host ("[{0}] {1}: {2}" -f $label, $Name, $Detail) -ForegroundColor $color
}

function Get-PackageManifestStatus {
    $manifestPath = Join-Path $KitRoot "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{
            Healthy = $false
            State = "missing"
            Detail = "manifest.json is missing; rerun Export-CodexKit.ps1"
        }
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            Healthy = $false
            State = "unreadable"
            Detail = "manifest.json is unreadable; rerun Export-CodexKit.ps1"
        }
    }

    $root = Resolve-FullPath $KitRoot
    $requiredPaths = @(
        "Install-CodexKitForWindows.ps1",
        "README.md",
        "Start-CodexManaged.cmd",
        "Start-CodexManaged.vbs",
        "Switch-CodexMachine.cmd",
        "skills\_skill-sources.csv",
        "skills\codex-skills\codexkit-sync\SKILL.md"
    )
    $syncPrefix = "skills\codex-skills\codexkit-sync\"
    $currentCorePaths = @(
        $requiredPaths
        $syncRoot = Join-Path $KitRoot "skills\codex-skills\codexkit-sync"
        if (Test-Path -LiteralPath $syncRoot -PathType Container) {
            Get-ChildItem -LiteralPath $syncRoot -File -Recurse -Force -ErrorAction Stop |
                ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\') }
        }
    )

    $entriesByPath = @{}
    $manifestCorePaths = @()
    foreach ($entry in @($manifest.files)) {
        $relative = ([string]$entry.path).Replace('/', '\').TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $key = $relative.ToLowerInvariant()
        $entriesByPath[$key] = $entry
        if ($requiredPaths -contains $relative -or $relative.StartsWith($syncPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $manifestCorePaths += $relative
        }
    }

    $corePaths = @($currentCorePaths + $manifestCorePaths | Sort-Object -Unique)
    $changed = @()
    $untracked = @()
    $missing = @()
    foreach ($relative in $corePaths) {
        $normalized = ([string]$relative).Replace('/', '\').TrimStart('\')
        $fullPath = Join-Path $KitRoot $normalized
        $key = $normalized.ToLowerInvariant()
        if (-not $entriesByPath.ContainsKey($key)) {
            $untracked += $normalized
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missing += $normalized
            continue
        }
        $expectedHash = [string]$entriesByPath[$key].sha256
        $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        if ([string]::IsNullOrWhiteSpace($expectedHash) -or $actualHash -ne $expectedHash) {
            $changed += $normalized
        }
    }

    $generatedAt = if ($manifest.PSObject.Properties.Name -contains "generated_at" -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.generated_at)) {
        [string]$manifest.generated_at
    } else {
        "unknown"
    }
    $healthy = $changed.Count -eq 0 -and $untracked.Count -eq 0 -and $missing.Count -eq 0
    if ($healthy) {
        return [pscustomobject]@{
            Healthy = $true
            State = "current"
            Detail = "generated $generatedAt; $($corePaths.Count) core file(s) match SHA256"
        }
    }

    $samples = @(
        @($changed | Select-Object -First 3 | ForEach-Object { "changed: $_" })
        @($untracked | Select-Object -First 3 | ForEach-Object { "untracked: $_" })
        @($missing | Select-Object -First 3 | ForEach-Object { "missing: $_" })
    )
    return [pscustomobject]@{
        Healthy = $false
        State = "stale"
        Detail = "generated $generatedAt; changed=$($changed.Count), untracked=$($untracked.Count), missing=$($missing.Count); $($samples -join '; '); rerun Export-CodexKit.ps1"
    }
}

function Write-PackageManifestStatus {
    try {
        $status = Get-PackageManifestStatus
        if ($status.Healthy) {
            Write-Host "[OK] package manifest: $($status.Detail)" -ForegroundColor Green
        } else {
            Write-Host "[STALE] package manifest: $($status.Detail)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[UNKNOWN] package manifest: check failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Test-SessionDataReady {
    foreach ($name in @("sessions", "archived_sessions")) {
        $source = Join-Path $KitRoot "session-data\$name"
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $KitRoot "session-data\session_index.jsonl") -PathType Leaf)) { return $false }
    return $true
}

function Test-DesktopStateReady {
    return (Test-Path -LiteralPath (Join-Path $KitRoot "desktop-state\.codex-global-state.json") -PathType Leaf)
}

function Write-SessionSyncGuidance {
    Write-Host "Session sync rule: managed launchers warn when another device is active; avoid editing the same conversation concurrently." -ForegroundColor Yellow
    Write-Host "Do not actively edit the same conversation on both machines; wait for OneDrive before reopening a conversation updated elsewhere." -ForegroundColor Yellow
    Write-Host "If OneDrive creates conflict copies under session-data, close ChatGPT everywhere before keeping or merging one side." -ForegroundColor Yellow
}

function Write-PluginStatus {
    $inventoryPath = Join-Path $KitRoot "plugins\inventory.json"
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        Write-Host "[INFO] plugins: no shared inventory available" -ForegroundColor DarkCyan
        return
    }

    try {
        $parsedInventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedPlugins = @($parsedInventory | ForEach-Object { $_ })
    } catch {
        Write-Host "[UNKNOWN] plugins: shared inventory is unreadable" -ForegroundColor Yellow
        return
    }

    if ($expectedPlugins.Count -eq 0) {
        Write-Host "[INFO] plugins: shared inventory is empty" -ForegroundColor DarkCyan
        return
    }

    $localCache = Join-Path $CodexHome "plugins\cache"
    $missing = 0
    Write-Host "Plugin inventory:" -ForegroundColor Cyan
    foreach ($plugin in $expectedPlugins | Sort-Object marketplace, plugin) {
        $marketplace = [string]$plugin.marketplace
        $pluginName = [string]$plugin.plugin
        if ([string]::IsNullOrWhiteSpace($marketplace) -or [string]::IsNullOrWhiteSpace($pluginName)) { continue }

        $localPlugin = Join-Path (Join-Path $localCache $marketplace) $pluginName
        $localVersions = @(
            if (Test-Path -LiteralPath $localPlugin -PathType Container) {
                Get-ChildItem -LiteralPath $localPlugin -Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            }
        )
        $expectedVersions = @($plugin.versions | ForEach-Object { [string]$_ })
        if ($localVersions.Count -gt 0) {
            Write-Host ("[OK] plugin {0}/{1}: local version(s) {2}; shared inventory {3}" -f
                $marketplace, $pluginName, ($localVersions -join ", "), ($expectedVersions -join ", ")) -ForegroundColor Green
        } else {
            $missing++
            Write-Host ("[MISSING] plugin {0}/{1}: expected from shared inventory" -f $marketplace, $pluginName) -ForegroundColor Yellow
        }
    }

    if ($missing -eq 0) {
        Write-Host "[OK] plugins: all shared inventory entries are present locally" -ForegroundColor Green
    } else {
        Write-Host ("[ACTION] plugins: {0} plugin(s) are missing on this machine; install or connect them locally" -f $missing) -ForegroundColor Yellow
    }
}

function Find-CodexCli {
    $candidates = New-Object System.Collections.Generic.List[object]
    $localBin = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (Test-Path -LiteralPath $localBin -PathType Container) {
        $localCli = Get-ChildItem -LiteralPath $localBin -Recurse -File -Filter "codex.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($localCli) { return $localCli.FullName }
    }

    $command = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and $command.Source -notmatch '\\Program Files\\WindowsApps\\') {
        return $command.Source
    }

    $windowsAppsAlias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\codex.exe"
    if (Test-Path -LiteralPath $windowsAppsAlias -PathType Leaf) {
        $candidates.Add((Get-Item -LiteralPath $windowsAppsAlias)) | Out-Null
    }

    foreach ($pattern in @("OpenAI.Codex", "OpenAI.ChatGPT")) {
        try {
            foreach ($package in @(Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue)) {
                if (-not $package.InstallLocation) { continue }
                $candidate = Join-Path $package.InstallLocation "app\resources\codex.exe"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $candidates.Add((Get-Item -LiteralPath $candidate)) | Out-Null
                }
            }
        } catch {}
    }

    $programWindowsApps = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $programWindowsApps -PathType Container) {
        foreach ($filter in @("OpenAI.Codex_*", "OpenAI.ChatGPT_*")) {
            Get-ChildItem -LiteralPath $programWindowsApps -Directory -Filter $filter -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName "app\resources\codex.exe"
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $candidates.Add((Get-Item -LiteralPath $candidate)) | Out-Null
                    }
                }
        }
    }

    $best = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    return $null
}

function Get-ChatGPTDesktopEntry {
    foreach ($packageName in @("OpenAI.Codex", "OpenAI.ChatGPT")) {
        try {
            $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $package -or -not $package.InstallLocation) { continue }
            $manifestPath = Join-Path $package.InstallLocation "AppxManifest.xml"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
            [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
            $application = $manifest.SelectSingleNode("//*[local-name()='Application' and @Executable]")
            $protocol = $manifest.SelectSingleNode("//*[local-name()='Protocol' and translate(@Name,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='codex']")
            if (-not $application -or -not $protocol) { continue }
            $executable = Join-Path $package.InstallLocation (([string]$application.Executable).Replace('/', '\'))
            if (Test-Path -LiteralPath $executable -PathType Leaf) {
                return [pscustomobject]@{ Executable = $executable; Package = $package }
            }
        } catch {}
    }
    return $null
}

function Read-Shortcut($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $shell = New-Object -ComObject WScript.Shell
        return $shell.CreateShortcut($Path)
    } catch { return $null }
}

function Get-StartMenuShortcutSpec {
    $programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    return [pscustomobject]@{
        Mode = "Managed"
        Path = Join-Path $programs "ChatGPT.lnk"
        Launcher = Join-Path $KitRoot "Start-CodexManaged.vbs"
        Description = "ChatGPT managed launcher via CodexKit"
    }
}

function Get-ExistingStartMenuMode {
    $programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $current = Read-Shortcut (Join-Path $programs "ChatGPT.lnk")
    $spec = Get-StartMenuShortcutSpec
    if ($current -and $current.Arguments -match [regex]::Escape($spec.Launcher)) { return "Managed" }
    return $null
}

function Test-StartMenuShortcut {
    $desktop = Get-ChatGPTDesktopEntry
    if (-not $desktop) { return $false }
    $spec = Get-StartMenuShortcutSpec
    $shortcut = Read-Shortcut $spec.Path
    if (-not $shortcut) { return $false }
    return $shortcut.TargetPath -ieq (Join-Path $env:WINDIR "System32\wscript.exe") -and
        $shortcut.Arguments -match [regex]::Escape($spec.Launcher) -and
        $shortcut.IconLocation -match ('^' + [regex]::Escape($desktop.Executable) + ',')
}

function Install-StartMenuShortcut {
    $desktop = Get-ChatGPTDesktopEntry
    if (-not $desktop) { throw "Could not locate the installed ChatGPT desktop entry from the Codex Appx manifest." }
    $spec = Get-StartMenuShortcutSpec
    if (-not (Test-Path -LiteralPath $spec.Launcher -PathType Leaf)) { throw "Missing Managed launcher: $($spec.Launcher)" }

    Ensure-Dir (Split-Path -Parent $spec.Path)
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($spec.Path)
    $shortcut.TargetPath = Join-Path $env:WINDIR "System32\wscript.exe"
    $shortcut.Arguments = "//B //Nologo `"$($spec.Launcher)`""
    $shortcut.WorkingDirectory = $KitRoot
    $shortcut.IconLocation = "$($desktop.Executable),0"
    $shortcut.Description = $spec.Description
    $shortcut.WindowStyle = 1
    $shortcut.Save()
    if (-not (Test-StartMenuShortcut)) { throw "Created Start menu shortcut but verification failed: $($spec.Path)" }

    $managedPaths = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex.lnk"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ChatGPT (CodexKit Resident).lnk"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ChatGPT (CodexKit Synced).lnk"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ChatGPT (CodexKit Managed).lnk")
    )
    foreach ($managedPath in $managedPaths) {
        $managed = Read-Shortcut $managedPath
        if (-not $managed) { continue }
        $isOurs = $false
        foreach ($candidateLauncher in @("Start-CodexResident.vbs", "Start-CodexSynced.vbs", "Start-CodexManaged.vbs")) {
            if ($managed.Arguments -match [regex]::Escape((Join-Path $KitRoot $candidateLauncher))) { $isOurs = $true }
        }
        if ($isOurs) {
            Remove-Item -LiteralPath $managedPath -Force
            Write-Host "Removed superseded CodexKit shortcut: $managedPath" -ForegroundColor DarkGray
        }
    }
    Write-Host "Installed ChatGPT Managed Start menu shortcut: $($spec.Path)" -ForegroundColor Green
}

function Enable-CodexHooksFeature {
    $configPath = Join-Path $CodexHome "config.toml"
    $lines = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        @(Get-Content -LiteralPath $configPath -Encoding UTF8)
    } else {
        @()
    }

    $featuresIndex = -1
    $nextSectionIndex = @($lines).Count
    for ($i = 0; $i -lt @($lines).Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*(?:#.*)?$') {
            $featuresIndex = $i
            for ($j = $i + 1; $j -lt @($lines).Count; $j++) {
                if ($lines[$j] -match '^\s*\[') {
                    $nextSectionIndex = $j
                    break
                }
            }
            break
        }
    }

    $changed = $false
    if ($featuresIndex -ge 0) {
        $hooksIndex = -1
        for ($i = $featuresIndex + 1; $i -lt $nextSectionIndex; $i++) {
            if ($lines[$i] -match '^\s*hooks\s*=') {
                $hooksIndex = $i
                break
            }
        }
        if ($hooksIndex -ge 0) {
            if ($lines[$hooksIndex] -notmatch '^\s*hooks\s*=\s*true\s*(?:#.*)?$') {
                $lines[$hooksIndex] = "hooks = true"
                $changed = $true
            }
        } else {
            $before = if ($featuresIndex -ge 0) { @($lines[0..$featuresIndex]) } else { @() }
            $after = if ($featuresIndex + 1 -lt @($lines).Count) { @($lines[($featuresIndex + 1)..(@($lines).Count - 1)]) } else { @() }
            $lines = @($before) + @("hooks = true") + @($after)
            $changed = $true
        }
    } else {
        if (@($lines).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) {
            $lines += ""
        }
        $lines += @("[features]", "hooks = true")
        $changed = $true
    }

    if ($changed -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
            Copy-Item -LiteralPath $configPath -Destination "$configPath.backup.$stamp" -Force
            Remove-ExpiredBackups $configPath
        }
        [IO.File]::WriteAllLines($configPath, $lines, (New-Object Text.UTF8Encoding($false)))
        Write-Host "Enabled Codex hooks feature: $configPath" -ForegroundColor Green
    } else {
        Write-Host "Codex hooks feature already enabled: $configPath" -ForegroundColor DarkGray
    }
}

function Convert-ToRegistryPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $value = [string]$Path
    if ($value -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive/$rest".TrimEnd('/')
    }
    return ($value -replace '\\', '/').TrimEnd('/')
}

function Merge-ProjectMemoryRegistry {
    $registryDir = Join-Path $KitRoot "memory-system"
    $registryPath = Join-Path $registryDir "project-memory-registry.tsv"
    $legacyPath = Join-Path $env:USERPROFILE ".local\state\memory-and-improvement\project-memory-registry.txt"
    Ensure-Dir $registryDir

    $records = New-Object System.Collections.Generic.List[string]
    $registrySources = @(
        Get-ChildItem -LiteralPath $registryDir -File -Filter "project-memory-registry*.tsv" -ErrorAction SilentlyContinue
    )
    foreach ($registrySource in $registrySources) {
        foreach ($line in Get-Content -LiteralPath $registrySource.FullName -Encoding UTF8) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line -eq "storage`tdevice`tpath") { continue }
            $parts = $line -split "`t", 3
            if (@($parts).Count -eq 3 -and $parts[0] -in @("local", "onedrive")) {
                $records.Add(($parts -join "`t")) | Out-Null
            }
        }
    }

    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        $oneDriveRoot = Convert-ToRegistryPath (Split-Path -Parent $KitRoot)
        $device = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { "unknown-device" } else { $env:COMPUTERNAME }
        foreach ($line in Get-Content -LiteralPath $legacyPath -Encoding UTF8) {
            $path = Convert-ToRegistryPath $line
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if ($path -eq $oneDriveRoot) {
                $records.Add("onedrive`t-`t.") | Out-Null
            } elseif ($path.StartsWith("$oneDriveRoot/", [StringComparison]::OrdinalIgnoreCase)) {
                $records.Add("onedrive`t-`t$($path.Substring($oneDriveRoot.Length + 1))") | Out-Null
            } else {
                $records.Add("local`t$device`t$path") | Out-Null
            }
        }
    }

    $previousState = Read-InstallState
    if ($previousState) {
        $previousDevice = [string]$previousState.device_name
        $previousProfile = Convert-ToRegistryPath ([string]$previousState.user_profile)
        $currentDevice = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { "unknown-device" } else { $env:COMPUTERNAME }
        $currentProfile = Convert-ToRegistryPath $env:USERPROFILE
        if ((-not [string]::IsNullOrWhiteSpace($previousDevice)) -and
            (-not [string]::IsNullOrWhiteSpace($previousProfile)) -and
            ($previousDevice -ne $currentDevice -or $previousProfile -ne $currentProfile)) {
            $migrated = New-Object System.Collections.Generic.List[string]
            foreach ($record in $records) {
                $parts = $record -split "`t", 3
                if (@($parts).Count -eq 3 -and $parts[0] -eq "local" -and
                    $parts[1] -eq $previousDevice -and
                    ($parts[2] -eq $previousProfile -or $parts[2].StartsWith("$previousProfile/", [StringComparison]::OrdinalIgnoreCase))) {
                    $suffix = $parts[2].Substring($previousProfile.Length)
                    $migrated.Add("local`t$currentDevice`t$currentProfile$suffix") | Out-Null
                } else {
                    $migrated.Add($record) | Out-Null
                }
            }
            $records = $migrated
            Write-Host "Migrated local registry paths: $previousDevice $previousProfile -> $currentDevice $currentProfile" -ForegroundColor Green
        }
    }

    $unique = @($records | Select-Object -Unique)
    $lines = @("storage`tdevice`tpath") + $unique
    $existingLines = if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
        @(Get-Content -LiteralPath $registryPath -Encoding UTF8)
    } else { @() }
    if (($existingLines -join "`n") -ne ($lines -join "`n")) {
        $tempPath = "$registryPath.tmp.$([Guid]::NewGuid().ToString('N'))"
        [IO.File]::WriteAllLines($tempPath, $lines, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tempPath -Destination $registryPath -Force
    }

    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        Remove-Item -LiteralPath $legacyPath -Force
        Write-Host "Merged legacy project-memory registry into CodexKit: $registryPath" -ForegroundColor Green
    } else {
        Write-Host "Project-memory registry ready: $registryPath" -ForegroundColor Green
    }
}

$KitRoot = if ([string]::IsNullOrWhiteSpace($KitRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KitRoot)
}
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$AgentsRoot = Join-Path $env:USERPROFILE ".agents"
$DocumentsRoot = if ([string]::IsNullOrWhiteSpace($DocumentsRoot)) {
    $detectedDocumentsRoot = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($detectedDocumentsRoot)) {
        if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            throw "Could not determine the Documents directory because both MyDocuments and USERPROFILE are empty."
        }
        Join-Path $env:USERPROFILE "Documents"
    } else {
        $detectedDocumentsRoot
    }
} else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DocumentsRoot)
}
$CodexProjectsSource = Join-Path $KitRoot "CodexProjects"
$CodexProjectsTarget = Join-Path $DocumentsRoot "Codex"
$ProjectWorkspaceSyncScript = Join-Path $KitRoot "skills\codex-skills\codexkit-sync\scripts\Sync-CodexProjectWorkspaces.ps1"
$AutomationsSource = Join-Path $KitRoot "automations"
$AutomationsTarget = Join-Path $CodexHome "automations"
$EnvironmentInventoryScript = Join-Path $KitRoot "skills\codex-skills\codexkit-sync\scripts\Export-CodexEnvironmentInventory.ps1"
$HooksInstalled = $false
$GlobalMemoryLinked = $false
$PreviousInstallState = Read-InstallState
$MemoryTaskRequested = [bool]$InstallMemoryTask

if (-not $MemorySubsystemChoiceExplicit) {
    if ($PreviousInstallState -and
        $PreviousInstallState.PSObject.Properties.Name -contains "memory_subsystem_enabled") {
        $MemorySubsystemEnabled = [bool]$PreviousInstallState.memory_subsystem_enabled
    } else {
        $MemorySubsystemEnabled =
            (Test-Path -LiteralPath (Join-Path $KitRoot "global-memory") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $CodexHome "skills\memory-and-improvement") -PathType Container)
    }
}

if ($DisableMemorySubsystem -and ($InstallGlobalMemory -or $InstallGlobalMemoryLink -or $InstallMemoryTask)) {
    throw "Memory installation options cannot be combined with -DisableMemorySubsystem."
}
if ($InstallGlobalMemory -or $InstallGlobalMemoryLink -or $InstallMemoryTask) {
    $MemorySubsystemEnabled = $true
}

# -InstallResidentStartMenuShortcut remains accepted for command-line compatibility,
# but all machines now install the same Managed launcher.
if ($InstallResidentStartMenuShortcut) { $InstallStartMenuShortcut = $true }

if ($InstallGlobalMemory -and $InstallGlobalMemoryLink) {
    throw "Choose either -InstallGlobalMemory (snapshot) or -InstallGlobalMemoryLink (automatic OneDrive sync), not both."
}

if ($Recommended) {
    $InstallSkillsLink = $true
    $InstallCodexSkillsLink = $true
    $InstallMinimaxSkillsLink = $true
    $InstallGlobalGuidanceLinks = $true
    $InstallHooks = $true
    $CaptureEnvironmentInventory = $true
    $InstallGlobalMemoryLink = $MemorySubsystemEnabled
    $InstallStartMenuShortcut = $true
    $InstallCodexProjectsLink = $true
    $InstallSessionLinks =
        (Test-Path -LiteralPath (Join-Path $KitRoot "session-data\sessions") -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $KitRoot "session-data\archived_sessions") -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $KitRoot "session-data\session_index.jsonl") -PathType Leaf)
    $InstallResidentStartMenuShortcut = $false
}

$expectedLinks = @(
    [pscustomobject]@{ Name = ".agents skills"; Source = (Join-Path $KitRoot "skills\agents-skills"); Target = (Join-Path $AgentsRoot "skills") },
    [pscustomobject]@{ Name = ".codex skills"; Source = (Join-Path $KitRoot "skills\codex-skills"); Target = (Join-Path $CodexHome "skills") },
    [pscustomobject]@{ Name = ".codex minimax-skills"; Source = (Join-Path $KitRoot "skills\minimax-skills"); Target = (Join-Path $CodexHome "minimax-skills") }
)
if ($MemorySubsystemEnabled) {
    $expectedLinks += [pscustomobject]@{ Name = "global memory"; Source = (Join-Path $KitRoot "global-memory"); Target = (Join-Path $env:USERPROFILE "global-memory") }
}
$expectedGuidance = @(
    [pscustomobject]@{ Name = "global AGENTS.md"; Source = (Join-Path $KitRoot "rules\global\AGENTS.md"); Target = (Join-Path $CodexHome "AGENTS.md") },
    [pscustomobject]@{ Name = "global AGENTS.override.md"; Source = (Join-Path $KitRoot "rules\global\AGENTS.override.md"); Target = (Join-Path $CodexHome "AGENTS.override.md") }
)
$expectedSessionLinks = @(
    [pscustomobject]@{ Name = ".codex sessions"; Source = (Join-Path $KitRoot "session-data\sessions"); Target = (Join-Path $CodexHome "sessions") },
    [pscustomobject]@{ Name = ".codex archived_sessions"; Source = (Join-Path $KitRoot "session-data\archived_sessions"); Target = (Join-Path $CodexHome "archived_sessions") }
)
$expectedSessionFiles = @(
    [pscustomobject]@{ Name = ".codex session_index.jsonl"; Source = (Join-Path $KitRoot "session-data\session_index.jsonl"); Target = (Join-Path $CodexHome "session_index.jsonl") }
)
$expectedDesktopStateFiles = @(
    [pscustomobject]@{ Name = ".codex global desktop state"; Source = (Join-Path $KitRoot "desktop-state\.codex-global-state.json"); Target = (Join-Path $CodexHome ".codex-global-state.json") }
)
$SessionLinksRequested = [bool]$InstallSessionLinks
$DesktopStateLinkRequested = [bool]$InstallDesktopStateLink
$CodexProjectsLinkRequested = [bool]$InstallCodexProjectsLink
$ProjectWorkspaceSyncEnabled = [bool]($InstallCodexProjectsLink -or
    ($PreviousInstallState -and
        (($PreviousInstallState.PSObject.Properties.Name -contains "codex_projects_sync_enabled" -and
            [bool]$PreviousInstallState.codex_projects_sync_enabled) -or
         ($PreviousInstallState.PSObject.Properties.Name -contains "codex_projects_link_enabled" -and
            [bool]$PreviousInstallState.codex_projects_link_enabled))))
$AutomationsLinkRequested = [bool]$InstallAutomationsLink

if ($MigrateExistingCodexProjects) {
    $InstallCodexProjectsLink = $true
    $CodexProjectsLinkRequested = $true
}

if ($MigrateExistingAutomations) {
    $InstallAutomationsLink = $true
    $AutomationsLinkRequested = $true
}

if ($Status) {
    Write-Host "CodexKit status for $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "Kit root: $KitRoot"
    if ($PreviousInstallState) {
        $pathChanges = @()
        if ((Resolve-FullPath ([string]$PreviousInstallState.kit_root)) -ne (Resolve-FullPath $KitRoot)) { $pathChanges += "KitRoot" }
        if ((Resolve-FullPath ([string]$PreviousInstallState.user_profile)) -ne (Resolve-FullPath $env:USERPROFILE)) { $pathChanges += "UserProfile" }
        if ((Resolve-FullPath ([string]$PreviousInstallState.codex_home)) -ne (Resolve-FullPath $CodexHome)) { $pathChanges += "CodexHome" }
        if ((Resolve-FullPath ([string]$PreviousInstallState.agents_root)) -ne (Resolve-FullPath $AgentsRoot)) { $pathChanges += "AgentsRoot" }
        if ($PreviousInstallState.PSObject.Properties.Name -contains "documents_root" -and
            (Resolve-FullPath ([string]$PreviousInstallState.documents_root)) -ne (Resolve-FullPath $DocumentsRoot)) { $pathChanges += "DocumentsRoot" }
        if ([string]$PreviousInstallState.device_name -ne [string]$env:COMPUTERNAME) { $pathChanges += "DeviceName" }
        if ($pathChanges.Count -gt 0) {
            Write-Host "[MIGRATION] changed since last install: $($pathChanges -join ', '); run -Repair" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] device/path identity matches the last installation state" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] no prior installation state; -Recommended or -Repair will create it" -ForegroundColor DarkCyan
    }
    Write-PackageManifestStatus
    foreach ($entry in $expectedLinks) {
        $sourceExists = Test-Path -LiteralPath $entry.Source -PathType Container
        $healthy = $sourceExists -and (Test-PathTargetsSource -Target $entry.Target -Source $entry.Source)
        Write-StatusRow $entry.Name $healthy $(if (-not $sourceExists) { "source missing" } elseif ($healthy) { "linked to $($entry.Source)" } else { "missing or wrong target" })
    }
    foreach ($entry in $expectedGuidance) {
        if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
            Write-Host "[OPTIONAL] $($entry.Name): source not present" -ForegroundColor DarkGray
            continue
        }
        $healthy = Test-PathTargetsSource -Target $entry.Target -Source $entry.Source
        Write-StatusRow $entry.Name $healthy $(if ($healthy) { "linked to $($entry.Source)" } else { "missing or wrong target" })
    }
    $codexProjectsItem = Get-Item -LiteralPath $CodexProjectsTarget -Force -ErrorAction SilentlyContinue
    $codexProjectsHealthy = $ProjectWorkspaceSyncEnabled -and
        (Test-Path -LiteralPath $CodexProjectsSource -PathType Container) -and
        $codexProjectsItem -and $codexProjectsItem.PSIsContainer -and
        [string]::IsNullOrWhiteSpace([string]$codexProjectsItem.LinkType)
    if ($codexProjectsHealthy) {
        Write-StatusRow "default Codex projects" $true "controlled Pull/Push between $CodexProjectsTarget and $CodexProjectsSource"
    } else {
        Write-StatusRow "default Codex projects" $false "run -Repair to restore a real local directory and controlled Pull/Push"
    }
    $automationsHealthy = (Test-Path -LiteralPath $AutomationsSource -PathType Container) -and
        (Test-PathTargetsSource -Target $AutomationsTarget -Source $AutomationsSource)
    if ($automationsHealthy) {
        Write-StatusRow "Codex automations" $true "$AutomationsTarget -> $AutomationsSource"
    } else {
        Write-Host "[OPTIONAL] Codex automations: not redirected; use -InstallAutomationsLink (and, only when needed, -MigrateExistingAutomations)" -ForegroundColor DarkGray
    }
    if (Test-SessionDataReady) {
        foreach ($entry in $expectedSessionLinks) {
            $healthy = Test-PathTargetsSource -Target $entry.Target -Source $entry.Source
            Write-StatusRow $entry.Name $healthy $(if ($healthy) { "linked to $($entry.Source)" } else { "not linked; add -InstallSessionLinks to enable or repair session sync" })
        }
        foreach ($entry in $expectedSessionFiles) {
            $healthy = Test-PathTargetsSource -Target $entry.Target -Source $entry.Source
            Write-StatusRow $entry.Name $healthy $(if ($healthy) { "linked to $($entry.Source)" } else { "not linked; add -InstallSessionLinks to sync thread title index" })
        }
    } else {
        Write-Host "[INFO] session sync: session-data is incomplete; run Export-CodexKit.ps1 -IncludeSessions -Force before installing session links" -ForegroundColor DarkCyan
    }
    if (Test-DesktopStateReady) {
        foreach ($entry in $expectedDesktopStateFiles) {
            $healthy = Test-PathTargetsSource -Target $entry.Target -Source $entry.Source
            if ($healthy) {
                Write-StatusRow $entry.Name $true "linked to $($entry.Source)"
            } else {
                Write-Host "[INFO] $($entry.Name): live link is not installed; use Switch-CodexMachine.cmd -Action Push/Pull for controlled sidebar sync, or add -InstallDesktopStateLink to retry live linking" -ForegroundColor DarkCyan
            }
        }
    } else {
        Write-Host "[INFO] desktop state sync: desktop-state is not exported; run Export-CodexKit.ps1 -IncludeDesktopState -Force before installing desktop state link" -ForegroundColor DarkCyan
    }
    $hooksHealthy = Test-HooksCurrent
    Write-StatusRow "hooks" $hooksHealthy $(if ($hooksHealthy) { "installed files match CodexKit" } else { "missing, outdated, or disabled" })
    $startMenuMode = Get-ExistingStartMenuMode
    $startMenuHealthy = $startMenuMode -eq "Managed" -and (Test-StartMenuShortcut)
    Write-StatusRow "ChatGPT Start menu shortcut" $startMenuHealthy $(if ($startMenuHealthy) { "Managed mode; current name, target, and Appx icon" } else { "missing or stale; run -Repair" })
    if ($MemorySubsystemEnabled) {
        $promptMarker = Join-Path $env:USERPROFILE ".local\state\memory-and-improvement\user-prompt-hook.last-run.json"
        if (Test-Path -LiteralPath $promptMarker -PathType Leaf) {
            try {
                $marker = Get-Content -LiteralPath $promptMarker -Raw -Encoding UTF8 | ConvertFrom-Json
                Write-Host "[INFO] hook last run: $($marker.timestamp), source=$($marker.source)" -ForegroundColor DarkCyan
            } catch {
                Write-Host "[INFO] hook last-run marker is unreadable" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[INFO] hook has no real-run marker yet" -ForegroundColor Yellow
        }
        $taskState = Get-MemoryTaskState
        if (-not $taskState.Available) {
            Write-Host "[UNKNOWN] memory task: permission denied while reading Task Scheduler" -ForegroundColor Yellow
        } else {
            $expectedGlobalMemory = Resolve-FullPath (Join-Path $KitRoot "global-memory")
            $expectedInstaller = Resolve-FullPath (Join-Path $CodexHome "skills\memory-and-improvement\scripts\maintenance\run-windows-maintenance.ps1")
            $expectedProjectRoot = Resolve-FullPath $env:USERPROFILE
            $taskHealthy = $taskState.Exists -and $taskState.State -eq "Ready" -and
                $taskState.Arguments -match [regex]::Escape($expectedGlobalMemory) -and
                $taskState.Arguments -match [regex]::Escape($expectedInstaller) -and
                $taskState.Arguments -match ('(?i)-ProjectRoot\s+"' + [regex]::Escape($expectedProjectRoot) + '"') -and
                $taskState.Arguments -match '(?i)-GitCommit\s+false'
            if (-not $taskState.Exists) {
                Write-Host "[OPTIONAL] memory task: missing; install only on the single automation host with -InstallMemoryTask" -ForegroundColor DarkGray
            } elseif ($taskHealthy) {
                Write-StatusRow "memory task" $true "ready with current paths"
            } else {
                Write-Host "[INFO] memory task: state=$($taskState.State), but arguments contain stale paths or settings; repair only on the automation host with -Repair -InstallMemoryTask, or remove with -RemoveMemoryTask" -ForegroundColor Yellow
            }
        }
        $registry = Join-Path $KitRoot "memory-system\project-memory-registry.tsv"
        Write-StatusRow "project memory registry" (Test-Path -LiteralPath $registry -PathType Leaf) $(if (Test-Path -LiteralPath $registry -PathType Leaf) { $registry } else { "missing" })
    } else {
        Write-Host "[SKIP] long-term memory subsystem was not enabled for this installation" -ForegroundColor DarkGray
    }
    Write-PluginStatus
    if (Test-Path -LiteralPath $EnvironmentInventoryScript -PathType Leaf) {
        & $EnvironmentInventoryScript -KitRoot $KitRoot -Status
    } else {
        Write-Host "[OPTIONAL] environment inventory helper is missing" -ForegroundColor DarkGray
    }
    Write-Host "Status check complete. No files were changed." -ForegroundColor Cyan
    exit 0
}

Ensure-Dir $CodexHome
Ensure-Dir $AgentsRoot

function Install-DirLink($Source, $Target, $Label) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing source folder: $Source" }
    if (Test-PathTargetsSource -Target $Target -Source $Source) {
        Write-Host "$Label link already correct: $Target -> $Source" -ForegroundColor DarkGray
        return
    }
    $backup = if (Test-Path -LiteralPath $Target) { Backup-Path $Target } else { $null }
    try {
        cmd /c mklink /D "$Target" "$Source" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-PathNode $Target
            Write-Host "Directory symlink failed for $Label; trying junction instead..." -ForegroundColor Yellow
            cmd /c mklink /J "$Target" "$Source" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to create $Label link: $Target -> $Source" }
        }
        Complete-Backup $Target
        Write-Host "Installed $Label link: $Target -> $Source" -ForegroundColor Green
    } catch {
        Restore-Backup -Path $Target -Backup $backup
        throw
    }
}

function Install-FileLink($Source, $Target, $Label) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-Host "Skipping missing $Label source: $Source" -ForegroundColor DarkGray
        return
    }

    if (Test-PathTargetsSource -Target $Target -Source $Source) {
        Write-Host "$Label link already correct: $Target -> $Source" -ForegroundColor DarkGray
        return
    }
    $backup = if (Test-Path -LiteralPath $Target) { Backup-Path $Target } else { $null }
    Ensure-Dir (Split-Path -Parent $Target)
    try {
        cmd /c mklink "$Target" "$Source" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-PathNode $Target
            Write-Host "File symlink failed for $Label; trying hard link instead..." -ForegroundColor Yellow
            cmd /c mklink /H "$Target" "$Source" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to create $Label link: $Target -> $Source" }
        }
        if (-not (Test-PathTargetsSource -Target $Target -Source $Source)) {
            throw "Created $Label link, but verification failed: $Target does not target $Source"
        }
        Complete-Backup $Target
        Write-Host "Installed $Label link: $Target -> $Source" -ForegroundColor Green
    } catch {
        Restore-Backup -Path $Target -Backup $backup
        throw
    }
}

function Get-RelativeChildPath($Root, $Path) {
    $resolvedRoot = Resolve-FullPath $Root
    $resolvedPath = Resolve-FullPath $Path
    if (-not $resolvedPath.StartsWith("$resolvedRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected root: $resolvedPath"
    }
    return $resolvedPath.Substring($resolvedRoot.Length).TrimStart('\')
}

function Get-CodexProjectsMergePlan($LocalRoot, $SharedRoot, [string[]]$IgnoreRelativePaths = @()) {
    $ignoredPaths = @{}
    foreach ($ignoredPath in $IgnoreRelativePaths) {
        if (-not [string]::IsNullOrWhiteSpace($ignoredPath)) {
            $ignoredPaths[$ignoredPath.Replace('/', '\').TrimStart('\')] = $true
        }
    }
    $relativeDirectories = @(
        Get-ChildItem -LiteralPath $LocalRoot -Directory -Recurse -Force -ErrorAction Stop |
            ForEach-Object { Get-RelativeChildPath -Root $LocalRoot -Path $_.FullName } |
            Where-Object { -not $ignoredPaths.ContainsKey($_) } |
            Sort-Object { $_.Length }, { $_ }
    )
    $fileEntries = @()
    $missingFiles = @()
    $conflicts = @()
    $identicalCount = 0

    foreach ($relative in $relativeDirectories) {
        $sharedPath = Join-Path $SharedRoot $relative
        $sharedItem = Get-Item -LiteralPath $sharedPath -Force -ErrorAction SilentlyContinue
        if ($sharedItem -and -not $sharedItem.PSIsContainer) {
            $conflicts += "$relative`tlocal=directory`tshared=file"
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $LocalRoot -File -Recurse -Force -ErrorAction Stop | Sort-Object FullName)) {
        $relative = Get-RelativeChildPath -Root $LocalRoot -Path $file.FullName
        if ($ignoredPaths.ContainsKey($relative)) { continue }
        $entry = [pscustomobject]@{
            Relative = $relative
            Length = [long]$file.Length
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        $fileEntries += $entry
        $sharedPath = Join-Path $SharedRoot $relative
        $sharedItem = Get-Item -LiteralPath $sharedPath -Force -ErrorAction SilentlyContinue
        if (-not $sharedItem) {
            $missingFiles += $entry
            continue
        }
        if ($sharedItem.PSIsContainer) {
            $conflicts += "$relative`tlocal=file`tshared=directory"
            continue
        }
        $sharedHash = if ([long]$sharedItem.Length -eq $entry.Length) {
            (Get-FileHash -LiteralPath $sharedPath -Algorithm SHA256).Hash
        } else { $null }
        if ($sharedHash -eq $entry.Sha256) {
            $identicalCount++
        } else {
            $conflicts += "$relative`tlocal=$($entry.Sha256)`tshared=$sharedHash"
        }
    }

    return [pscustomobject]@{
        RelativeDirectories = @($relativeDirectories)
        FileEntries = @($fileEntries)
        MissingFiles = @($missingFiles)
        IdenticalFileCount = $identicalCount
        Conflicts = @($conflicts)
    }
}

function Write-CodexProjectsConflictReport($Conflicts) {
    $stateRoot = Join-Path $env:USERPROFILE ".local\state\codexkit"
    Ensure-Dir $stateRoot
    $report = Join-Path $stateRoot ("codex-project-merge-conflicts-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"))
    $lines = @(
        "CodexProjects merge stopped because the same relative path has different content or types."
        "Local source: $CodexProjectsTarget"
        "Shared source: $CodexProjectsSource"
        ""
    ) + @($Conflicts)
    [IO.File]::WriteAllLines($report, $lines, (New-Object Text.UTF8Encoding($false)))
    return $report
}

function Undo-CodexProjectsMerge($CreatedFiles, $CreatedDirectories) {
    $sharedRoot = Resolve-FullPath $CodexProjectsSource
    $files = @($CreatedFiles)
    [array]::Reverse($files)
    foreach ($path in $files) {
        $resolved = Resolve-FullPath $path
        if ($resolved.StartsWith("$sharedRoot\", [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Remove-Item -LiteralPath $resolved -Force
        }
    }
    $directories = @($CreatedDirectories | Sort-Object { $_.Length } -Descending)
    foreach ($path in $directories) {
        $resolved = Resolve-FullPath $path
        if ($resolved.StartsWith("$sharedRoot\", [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolved -PathType Container) -and
            (Test-DirectoryEmpty $resolved)) {
            [IO.Directory]::Delete($resolved, $false)
        }
    }
}

function Install-CodexProjectsLink {
    if (-not (Test-Path -LiteralPath $ProjectWorkspaceSyncScript -PathType Leaf)) {
        throw "Missing project workspace sync helper: $ProjectWorkspaceSyncScript"
    }
    Ensure-Dir $CodexProjectsSource
    Ensure-Dir (Split-Path -Parent $CodexProjectsTarget)
    $targetItem = Get-Item -LiteralPath $CodexProjectsTarget -Force -ErrorAction SilentlyContinue
    if ($targetItem -and -not [string]::IsNullOrWhiteSpace([string]$targetItem.LinkType)) {
        if (-not (Test-PathTargetsSource -Target $CodexProjectsTarget -Source $CodexProjectsSource)) {
            throw "Refusing to replace an unrelated directory link: $CodexProjectsTarget"
        }
        Write-Host "Replacing the legacy project workspace Junction with a real local directory." -ForegroundColor Yellow
        [IO.Directory]::Delete($CodexProjectsTarget, $false)
        Ensure-Dir $CodexProjectsTarget
        Copy-DirectoryContents -Source $CodexProjectsSource -Destination $CodexProjectsTarget
        if (((Get-DirectoryFingerprint $CodexProjectsSource) -join "`n") -ne
            ((Get-DirectoryFingerprint $CodexProjectsTarget) -join "`n")) {
            throw "Legacy Junction migration verification failed. Shared data remains unchanged at $CodexProjectsSource."
        }
    } elseif (-not $targetItem) {
        Ensure-Dir $CodexProjectsTarget
    } elseif (-not $targetItem.PSIsContainer) {
        throw "The Codex project workspace path is not a directory: $CodexProjectsTarget"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ProjectWorkspaceSyncScript `
        -Pull -LocalRoot $CodexProjectsTarget -SharedRoot $CodexProjectsSource
    if ($LASTEXITCODE -ne 0) { throw "Initial project workspace Pull failed with exit code $LASTEXITCODE." }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ProjectWorkspaceSyncScript `
        -Push -LocalRoot $CodexProjectsTarget -SharedRoot $CodexProjectsSource
    if ($LASTEXITCODE -ne 0) { throw "Initial project workspace Push failed with exit code $LASTEXITCODE." }
    $script:ProjectWorkspaceSyncEnabled = $true
    Write-Host "Projectless workspaces now use controlled Pull/Push with a real local Codex directory." -ForegroundColor Green
}

function Write-AutomationsConflictReport($Conflicts) {
    $stateRoot = Join-Path $env:USERPROFILE ".local\state\codexkit"
    Ensure-Dir $stateRoot
    $report = Join-Path $stateRoot ("automation-merge-conflicts-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"))
    $lines = @(
        "Codex automations merge stopped because the same relative path has different content or types."
        "Local source: $AutomationsTarget"
        "Shared source: $AutomationsSource"
        ""
    ) + @($Conflicts)
    [IO.File]::WriteAllLines($report, $lines, (New-Object Text.UTF8Encoding($false)))
    return $report
}

function Undo-AutomationsMerge($CreatedFiles, $CreatedDirectories) {
    $sharedRoot = Resolve-FullPath $AutomationsSource
    $files = @($CreatedFiles)
    [array]::Reverse($files)
    foreach ($path in $files) {
        $resolved = Resolve-FullPath $path
        if ($resolved.StartsWith("$sharedRoot\", [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Remove-Item -LiteralPath $resolved -Force
        }
    }
    $directories = @($CreatedDirectories | Sort-Object { $_.Length } -Descending)
    foreach ($path in $directories) {
        $resolved = Resolve-FullPath $path
        if ($resolved.StartsWith("$sharedRoot\", [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolved -PathType Container) -and
            (Test-DirectoryEmpty $resolved)) {
            [IO.Directory]::Delete($resolved, $false)
        }
    }
}

function Install-AutomationsLink {
    Ensure-Dir (Split-Path -Parent $AutomationsSource)
    if (Test-PathTargetsSource -Target $AutomationsTarget -Source $AutomationsSource) {
        Write-Host "Codex automations link already correct: $AutomationsTarget -> $AutomationsSource" -ForegroundColor DarkGray
        return
    }

    $targetHasFiles = (Test-Path -LiteralPath $AutomationsTarget -PathType Container) -and
        -not (Test-DirectoryEmpty $AutomationsTarget)
    $sourceHasFiles = (Test-Path -LiteralPath $AutomationsSource -PathType Container) -and
        -not (Test-DirectoryEmpty $AutomationsSource)

    if ($targetHasFiles -and -not $MigrateExistingAutomations) {
        throw "Existing Codex automations were found at $AutomationsTarget. Close ChatGPT and rerun with -InstallAutomationsLink -MigrateExistingAutomations to copy them safely and retain a backup."
    }
    if (-not $targetHasFiles) {
        Ensure-Dir $AutomationsSource
        Install-DirLink -Source $AutomationsSource -Target $AutomationsTarget -Label "Codex automations"
        return
    }

    Write-Host "Migrating existing Codex automations into OneDrive. Run this only while ChatGPT is fully closed." -ForegroundColor Yellow
    $mergePlan = $null
    if ($sourceHasFiles) {
        $ignored = @()
        if (Test-Path -LiteralPath (Join-Path $AutomationsSource ".run-jitter-salt") -PathType Leaf) {
            $ignored += ".run-jitter-salt"
        }
        $mergePlan = Get-CodexProjectsMergePlan -LocalRoot $AutomationsTarget -SharedRoot $AutomationsSource -IgnoreRelativePaths $ignored
        if ($mergePlan.Conflicts.Count -gt 0) {
            $report = Write-AutomationsConflictReport -Conflicts $mergePlan.Conflicts
            throw "Automation merge found $($mergePlan.Conflicts.Count) conflicting relative path(s). Nothing was changed. Review: $report"
        }
        Write-Host "Automation merge preflight passed: $($mergePlan.MissingFiles.Count) new file(s), $($mergePlan.IdenticalFileCount) identical file(s)." -ForegroundColor Green
    }

    $backup = Backup-Path $AutomationsTarget
    $sourceExistedBeforeMigration = Test-Path -LiteralPath $AutomationsSource
    $sourcePopulatedForMigration = $false
    $createdMergeFiles = New-Object System.Collections.Generic.List[string]
    $createdMergeDirectories = New-Object System.Collections.Generic.List[string]
    try {
        if (-not $sourceHasFiles) {
            Ensure-Dir $AutomationsSource
            if (-not (Test-DirectoryEmpty $AutomationsSource)) {
                throw "Automation migration destination became non-empty: $AutomationsSource"
            }
            $sourcePopulatedForMigration = $true
            Copy-DirectoryContents -Source $backup -Destination $AutomationsSource

            $backupFingerprint = (Get-DirectoryFingerprint $backup) -join "`n"
            $sourceFingerprint = (Get-DirectoryFingerprint $AutomationsSource) -join "`n"
            if ($backupFingerprint -ne $sourceFingerprint) {
                throw "Automation migration verification failed; the copied directory does not match the backup."
            }
        } else {
            foreach ($relative in $mergePlan.RelativeDirectories) {
                $destinationDirectory = Join-Path $AutomationsSource $relative
                $existing = Get-Item -LiteralPath $destinationDirectory -Force -ErrorAction SilentlyContinue
                if (-not $existing) {
                    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                    $createdMergeDirectories.Add($destinationDirectory) | Out-Null
                } elseif (-not $existing.PSIsContainer) {
                    throw "Automation merge destination changed after preflight: $destinationDirectory"
                }
            }
            foreach ($entry in $mergePlan.MissingFiles) {
                $localFile = Join-Path $backup $entry.Relative
                $sharedFile = Join-Path $AutomationsSource $entry.Relative
                $existing = Get-Item -LiteralPath $sharedFile -Force -ErrorAction SilentlyContinue
                if ($existing) {
                    if ($existing.PSIsContainer -or
                        [long]$existing.Length -ne [long]$entry.Length -or
                        (Get-FileHash -LiteralPath $sharedFile -Algorithm SHA256).Hash -ne $entry.Sha256) {
                        throw "Automation merge destination changed after preflight: $sharedFile"
                    }
                    continue
                }
                Ensure-Dir (Split-Path -Parent $sharedFile)
                Copy-Item -LiteralPath $localFile -Destination $sharedFile
                $createdMergeFiles.Add($sharedFile) | Out-Null
                if ((Get-FileHash -LiteralPath $sharedFile -Algorithm SHA256).Hash -ne $entry.Sha256) {
                    throw "Merged automation file verification failed: $sharedFile"
                }
            }
            foreach ($entry in $mergePlan.FileEntries) {
                $sharedFile = Join-Path $AutomationsSource $entry.Relative
                $sharedItem = Get-Item -LiteralPath $sharedFile -Force -ErrorAction SilentlyContinue
                if (-not $sharedItem -or $sharedItem.PSIsContainer -or
                    [long]$sharedItem.Length -ne [long]$entry.Length -or
                    (Get-FileHash -LiteralPath $sharedFile -Algorithm SHA256).Hash -ne $entry.Sha256) {
                    throw "Final merged automation-file verification failed: $sharedFile"
                }
            }
        }

        Install-DirLink -Source $AutomationsSource -Target $AutomationsTarget -Label "Codex automations"
        Complete-Backup $AutomationsTarget
        Write-Host "Codex automations now sync from: $AutomationsSource" -ForegroundColor Green
        Write-Host "Rollback backup retained at: $backup" -ForegroundColor Yellow
    } catch {
        $migrationError = $_
        try {
            if ($createdMergeFiles.Count -gt 0 -or $createdMergeDirectories.Count -gt 0) {
                Undo-AutomationsMerge -CreatedFiles $createdMergeFiles -CreatedDirectories $createdMergeDirectories
            }
            if ($sourcePopulatedForMigration -and (Test-Path -LiteralPath $AutomationsSource -PathType Container)) {
                Clear-DirectoryContents $AutomationsSource
            }
            if (-not $sourceExistedBeforeMigration -and
                (Test-Path -LiteralPath $AutomationsSource -PathType Container) -and
                (Test-DirectoryEmpty $AutomationsSource)) {
                Remove-PathNode $AutomationsSource
            }
        } catch {
            Write-Host "Warning: could not fully clean the shared automation destination after failure: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Restore-Backup -Path $AutomationsTarget -Backup $backup
        throw $migrationError
    }
}

if ($Repair) {
    Write-Host "Repairing only missing or incorrect CodexKit components..." -ForegroundColor Cyan
    $InstallSkillsLink = -not (Test-PathTargetsSource -Target (Join-Path $AgentsRoot "skills") -Source (Join-Path $KitRoot "skills\agents-skills"))
    $InstallCodexSkillsLink = -not (Test-PathTargetsSource -Target (Join-Path $CodexHome "skills") -Source (Join-Path $KitRoot "skills\codex-skills"))
    $InstallMinimaxSkillsLink = -not (Test-PathTargetsSource -Target (Join-Path $CodexHome "minimax-skills") -Source (Join-Path $KitRoot "skills\minimax-skills"))
    $InstallGlobalMemoryLink = $MemorySubsystemEnabled -and
        -not (Test-PathTargetsSource -Target (Join-Path $env:USERPROFILE "global-memory") -Source (Join-Path $KitRoot "global-memory"))
    $InstallCodexProjectsLink = [bool]$ProjectWorkspaceSyncEnabled
    $previousAutomationsLinkEnabled = $PreviousInstallState -and
        ($PreviousInstallState.PSObject.Properties.Name -contains "automations_link_enabled") -and
        [bool]$PreviousInstallState.automations_link_enabled
    if ($AutomationsLinkRequested -or $previousAutomationsLinkEnabled) {
        $InstallAutomationsLink = -not (Test-PathTargetsSource -Target $AutomationsTarget -Source $AutomationsSource)
    } else {
        $InstallAutomationsLink = $false
    }
    $InstallGlobalGuidanceLinks = $false
    foreach ($entry in $expectedGuidance) {
        if ((Test-Path -LiteralPath $entry.Source -PathType Leaf) -and
            -not (Test-PathTargetsSource -Target $entry.Target -Source $entry.Source)) {
            $InstallGlobalGuidanceLinks = $true
        }
    }
    if ($SessionLinksRequested) {
        $InstallSessionLinks = $false
        foreach ($entry in $expectedSessionLinks) {
            if (-not (Test-PathTargetsSource -Target $entry.Target -Source $entry.Source)) {
                $InstallSessionLinks = $true
            }
        }
        foreach ($entry in $expectedSessionFiles) {
            if (-not (Test-PathTargetsSource -Target $entry.Target -Source $entry.Source)) {
                $InstallSessionLinks = $true
            }
        }
    }
    if ($DesktopStateLinkRequested) {
        $InstallDesktopStateLink = $false
        foreach ($entry in $expectedDesktopStateFiles) {
            if (-not (Test-PathTargetsSource -Target $entry.Target -Source $entry.Source)) {
                $InstallDesktopStateLink = $true
            }
        }
    }
    $InstallHooks = -not (Test-HooksCurrent)
    $InstallResidentStartMenuShortcut = $false
    $InstallStartMenuShortcut = -not (Test-StartMenuShortcut)
    if ($MemoryTaskRequested) {
        $taskState = Get-MemoryTaskState
        $expectedGlobalMemory = Resolve-FullPath (Join-Path $KitRoot "global-memory")
        $expectedInstaller = Resolve-FullPath (Join-Path $CodexHome "skills\memory-and-improvement\scripts\maintenance\run-windows-maintenance.ps1")
        $expectedProjectRoot = Resolve-FullPath $env:USERPROFILE
        $taskCurrent = $taskState.Available -and $taskState.Exists -and $taskState.State -eq "Ready" -and
            $taskState.Arguments -match [regex]::Escape($expectedGlobalMemory) -and
            $taskState.Arguments -match [regex]::Escape($expectedInstaller) -and
            $taskState.Arguments -match ('(?i)-ProjectRoot\s+"' + [regex]::Escape($expectedProjectRoot) + '"') -and
            $taskState.Arguments -match '(?i)-GitCommit\s+false'
        $InstallMemoryTask = $taskState.Available -and -not $taskCurrent
    } else {
        $InstallMemoryTask = $false
    }
}

if ($MemorySubsystemEnabled) {
    Merge-ProjectMemoryRegistry
}

if ($RemoveMemoryTask) {
    $taskState = Get-MemoryTaskState
    if (-not $taskState.Available) {
        Write-Host "Could not inspect Task Scheduler; skipping memory task removal." -ForegroundColor Yellow
    } elseif ($taskState.Exists) {
        Unregister-ScheduledTask -TaskName "Codex Memory Maintenance" -Confirm:$false
        Write-Host "Removed optional memory maintenance task from this machine." -ForegroundColor Green
    } else {
        Write-Host "Memory maintenance task is not installed on this machine." -ForegroundColor DarkGray
    }
    $InstallMemoryTask = $false
}

if ($InstallHooks -and (Test-HooksCurrent)) {
    Write-Host "Hooks are already current; skipping reinstallation." -ForegroundColor DarkGray
    $InstallHooks = $false
}

if ($InstallMemoryTask) {
    $taskState = Get-MemoryTaskState
    $expectedGlobalMemory = Resolve-FullPath (Join-Path $KitRoot "global-memory")
    $expectedInstaller = Resolve-FullPath (Join-Path $CodexHome "skills\memory-and-improvement\scripts\maintenance\run-windows-maintenance.ps1")
    $expectedProjectRoot = Resolve-FullPath $env:USERPROFILE
    $taskAlreadyCurrent = $taskState.Available -and $taskState.Exists -and $taskState.State -eq "Ready" -and
        $taskState.Arguments -match [regex]::Escape($expectedGlobalMemory) -and
        $taskState.Arguments -match [regex]::Escape($expectedInstaller) -and
        $taskState.Arguments -match ('(?i)-ProjectRoot\s+"' + [regex]::Escape($expectedProjectRoot) + '"') -and
        $taskState.Arguments -match '(?i)-GitCommit\s+false'
    if ($taskAlreadyCurrent) {
        Write-Host "Memory maintenance task is already current; skipping reinstallation." -ForegroundColor DarkGray
        $InstallMemoryTask = $false
    }
}

if ($InstallSkillsLink) {
    $source = Join-Path $KitRoot "skills\agents-skills"
    $target = Join-Path $AgentsRoot "skills"
    Install-DirLink -Source $source -Target $target -Label ".agents skills"
}

if ($InstallCodexSkillsLink) {
    $source = Join-Path $KitRoot "skills\codex-skills"
    $target = Join-Path $CodexHome "skills"
    Install-DirLink -Source $source -Target $target -Label ".codex skills"
}

if ($InstallMinimaxSkillsLink) {
    $source = Join-Path $KitRoot "skills\minimax-skills"
    $target = Join-Path $CodexHome "minimax-skills"
    Install-DirLink -Source $source -Target $target -Label ".codex minimax-skills"
}

if ($InstallCodexProjectsLink) {
    Install-CodexProjectsLink
    Write-Host "New projectless Codex workspaces synchronize through the Managed launcher." -ForegroundColor Green
    Write-Host "Avoid editing the same project on two machines before OneDrive has finished syncing." -ForegroundColor Yellow
}

if ($InstallAutomationsLink) {
    Install-AutomationsLink
    Write-Host "Codex automation definitions and run memory now synchronize through CodexKit\automations." -ForegroundColor Green
    Write-Host "Run Managed ChatGPT on only one machine at a time so the same schedule is not executed twice." -ForegroundColor Yellow
}

if ($InstallGlobalGuidanceLinks) {
    $sourceRoot = Join-Path $KitRoot "rules\global"
    foreach ($name in @("AGENTS.md", "AGENTS.override.md")) {
        Install-FileLink -Source (Join-Path $sourceRoot $name) -Target (Join-Path $CodexHome $name) -Label "global $name"
    }
    Write-Host "Global Codex guidance now syncs through OneDrive." -ForegroundColor Green
    Write-Host "Machine-specific .codex\rules approval files remain local." -ForegroundColor Yellow
}

if ($InstallSessionLinks) {
    if (-not (Test-SessionDataReady)) {
        throw "Session data is not exported. Run the exporter with -IncludeSessions -Force, wait for OneDrive sync, then rerun this installer with -InstallSessionLinks."
    }
    Write-Host "WARNING: session files contain complete conversation history and may include sensitive data." -ForegroundColor Yellow
    Write-SessionSyncGuidance

    foreach ($entry in $expectedSessionLinks) {
        Install-DirLink -Source $entry.Source -Target $entry.Target -Label $entry.Name
    }
    foreach ($entry in $expectedSessionFiles) {
        Install-FileLink -Source $entry.Source -Target $entry.Target -Label $entry.Name
    }
    Write-Host "Codex session directories now sync through OneDrive." -ForegroundColor Green
}

if ($InstallDesktopStateLink) {
    if (-not (Test-DesktopStateReady)) {
        throw "Desktop state is not exported. Run the exporter with -IncludeDesktopState -Force, wait for OneDrive sync, then rerun this installer with -InstallDesktopStateLink."
    }
    Write-Host "WARNING: .codex-global-state.json contains desktop UI state, host ids, prompt history, workspace hints, and project ordering." -ForegroundColor Yellow
    Write-Host "A live-linked desktop state file is single-machine only. Use the controlled Managed Pull/Push launcher instead." -ForegroundColor Yellow
    foreach ($entry in $expectedDesktopStateFiles) {
        Install-FileLink -Source $entry.Source -Target $entry.Target -Label $entry.Name
    }
    Write-Host "Codex desktop sidebar state now syncs through OneDrive." -ForegroundColor Green
}

if ($InstallHooks) {
    $template = Join-Path $KitRoot "hooks\hooks.template.json"
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Missing hooks template: $template" }
    $target = Join-Path $CodexHome "hooks.json"
    $hooksBackup = if (Test-Path -LiteralPath $target) { Backup-Path $target } else { $null }
    try {
        $raw = Get-Content -LiteralPath $template -Raw
        $jsonEscapedKit = $KitRoot.Replace('\', '\\')
        $raw = $raw.Replace("__CODEXKIT__", $jsonEscapedKit)

        $codexBinSource = Join-Path $KitRoot "hooks\scripts\codex-bin"
        $codexBinTarget = Join-Path $CodexHome "bin"
        if (Test-Path -LiteralPath $codexBinSource -PathType Container) {
            Ensure-Dir $codexBinTarget
            Copy-Item -Path (Join-Path $codexBinSource "*") -Destination $codexBinTarget -Recurse -Force
            $portableBin = Join-Path $KitRoot "hooks\scripts\codex-bin"
            $raw = $raw.Replace($portableBin.Replace('\', '\\'), $codexBinTarget.Replace('\', '\\'))
        }

        [IO.File]::WriteAllText($target, $raw, (New-Object Text.UTF8Encoding($false)))
        $installedHooks = Get-Content -LiteralPath $target -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($eventName in @("SessionStart", "UserPromptSubmit")) {
            foreach ($group in @($installedHooks.hooks.$eventName)) {
                foreach ($hook in @($group.hooks)) {
                    if ($hook.type -eq "command" -and $hook.command -match '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))') {
                        $scriptPath = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Installed hook references a missing script: $scriptPath"
                        }
                    }
                }
            }
        }
        Enable-CodexHooksFeature
        foreach ($hookScript in @(
            (Join-Path $codexBinTarget "memory-session-start.ps1"),
            (Join-Path $codexBinTarget "memory-user-prompt.ps1")
        )) {
            $tokens = $null
            $parseErrors = $null
            [Management.Automation.Language.Parser]::ParseFile($hookScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
            if (@($parseErrors).Count -gt 0) {
                throw "Installed hook script has PowerShell syntax errors: $hookScript"
            }
        }
        Complete-Backup $target
        Write-Host "Installed hooks.json: $target" -ForegroundColor Green
        Write-Host "Hook scripts passed PowerShell syntax validation." -ForegroundColor Green
        Write-Host "IMPORTANT: Codex will still skip these hooks until their exact definitions are trusted on this machine." -ForegroundColor Yellow
        $HooksInstalled = $true
        $codexCli = Find-CodexCli
        if ($codexCli) {
            Write-Host "Codex CLI found: $codexCli" -ForegroundColor Green
            Write-Host "Run this command, then enter /hooks and trust both definitions:" -ForegroundColor Yellow
            Write-Host "  & `"$codexCli`"" -ForegroundColor Cyan
        } else {
            Write-Host "Codex CLI was not found. Install it with: npm install -g @openai/codex" -ForegroundColor Yellow
        }
    } catch {
        Restore-Backup -Path $target -Backup $hooksBackup
        throw
    }
}

if ($InstallProfiles) {
    $profiles = Join-Path $KitRoot "profiles"
    if (Test-Path -LiteralPath $profiles -PathType Container) {
        Get-ChildItem -LiteralPath $profiles -File -Filter "*.config.toml" | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $CodexHome $_.Name) -Force
            Write-Host "Installed profile: $($_.Name)" -ForegroundColor Green
        }
    }
}

if ($CaptureEnvironmentInventory) {
    if (-not (Test-Path -LiteralPath $EnvironmentInventoryScript -PathType Leaf)) {
        throw "Missing environment inventory helper: $EnvironmentInventoryScript"
    }
    & $EnvironmentInventoryScript -KitRoot $KitRoot
}

if ($InstallGlobalMemory) {
    $source = Join-Path $KitRoot "global-memory"
    $target = Join-Path $env:USERPROFILE "global-memory"
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing global-memory folder: $source" }
    $backup = if (Test-Path -LiteralPath $target) { Backup-Path $target } else { $null }
    try {
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        Complete-Backup $target
        Write-Host "Installed global memory: $target" -ForegroundColor Green
    } catch {
        Restore-Backup -Path $target -Backup $backup
        throw
    }
}

if ($InstallGlobalMemoryLink) {
    $source = Join-Path $KitRoot "global-memory"
    $target = Join-Path $env:USERPROFILE "global-memory"
    Install-DirLink -Source $source -Target $target -Label "global memory"
    $GlobalMemoryLinked = $true
    Write-Host "Global memory now syncs automatically through OneDrive." -ForegroundColor Green
    Write-Host "Avoid editing the same memory file on two machines at the same time." -ForegroundColor Yellow
}

if ($InstallStartMenuShortcut -or $InstallResidentStartMenuShortcut) {
    Install-StartMenuShortcut
}

if ($InstallMemoryTask) {
    $taskConfigPath = Join-Path $KitRoot "scheduled-tasks\memory-maintenance.portable.json"
    if (-not (Test-Path -LiteralPath $taskConfigPath -PathType Leaf)) { throw "Missing portable task config: $taskConfigPath" }
    $taskConfig = Get-Content -LiteralPath $taskConfigPath -Raw | ConvertFrom-Json
    $installer = Join-Path $CodexHome "skills\memory-and-improvement\scripts\maintenance\install-windows-maintenance.ps1"
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "Install the memory-and-improvement skill before restoring the scheduled task: $installer"
    }

    $globalMemoryTarget = Join-Path $env:USERPROFILE "global-memory"
    if (-not $GlobalMemoryLinked -and (Test-Path -LiteralPath $globalMemoryTarget)) {
        $GlobalMemoryLinked = [bool]((Get-Item -LiteralPath $globalMemoryTarget -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
    }
    $effectiveGitCommit = if ($GlobalMemoryLinked) { "false" } else { [string]$taskConfig.git_commit }
    if ($GlobalMemoryLinked -and [string]$taskConfig.git_commit -eq "true") {
        Write-Host "Disabling maintenance Git commits for linked global memory to avoid syncing .git metadata across machines." -ForegroundColor Yellow
    }

    $taskArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installer,
        "-TaskName", [string]$taskConfig.task_name,
        "-Mode", [string]$taskConfig.mode,
        "-Scope", [string]$taskConfig.scope,
        "-ProjectRoot", $env:USERPROFILE,
        "-GitCommit", $effectiveGitCommit,
        "-Writeback", [string]$taskConfig.writeback,
        "-SkillPolicyWriteback", [string]$taskConfig.skill_policy_writeback,
        "-MinRecurrence", [string]$taskConfig.min_recurrence,
        "-Apply"
    )
    if ($taskConfig.mode -eq "interval") {
        $taskArgs += @("-IntervalMinutes", [string]$taskConfig.interval_minutes)
    } else {
        $taskArgs += @("-Hour", [string]$taskConfig.hour, "-Minute", [string]$taskConfig.minute)
    }

    & powershell.exe @taskArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to install memory maintenance scheduled task." }
    Write-Host "Installed memory maintenance scheduled task." -ForegroundColor Green
}

if ($OpenHooksTrust) {
    if (-not $HooksInstalled) {
        Write-Host "-OpenHooksTrust was requested without -InstallHooks; opening the current CLI for hook review." -ForegroundColor Yellow
    }
    $codexCli = Find-CodexCli
    if (-not $codexCli) {
        throw "Codex CLI was not found. Install it with 'npm install -g @openai/codex', open a new terminal, then run codex."
    }
    Write-Host "Opening Codex CLI. Enter /hooks and trust both hook definitions." -ForegroundColor Cyan
    & $codexCli
}

Write-InstallState
Write-Host "Done." -ForegroundColor Green
'@
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Install-CodexKitForWindows.ps1") -Content $helper -Category "generated"
}

function Write-SwitchCommand {
    $content = @'
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\codex-skills\codexkit-sync\scripts\Switch-CodexMachine.ps1" %*
set "exitCode=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %exitCode%
'@
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Switch-CodexMachine.cmd") -Content $content -Category "generated"
}

function Write-StartCommands {
    $managed = @'
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\codex-skills\codexkit-sync\scripts\Start-CodexWithSync.ps1" %*
set "exitCode=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %exitCode%
'@
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexManaged.cmd") -Content $managed -Category "generated"

    $managedVbs = @'
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
script = root & "\skills\codex-skills\codexkit-sync\scripts\Start-CodexWithSync.ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & script & Chr(34)
shell.Run command, 0, False
'@
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "Start-CodexManaged.vbs") -Content $managedVbs -Category "generated"
}

function Write-Readme {
    $content = @'
# CodexKit

Extracted on: __EXTRACTED_ON__
Source Codex home: `__SOURCE_CODEX_HOME__`
Source agents root: `__SOURCE_AGENTS_ROOT__`
Machine: `__MACHINE__`
User: `__USER__`

## What this folder is for

This folder is a portable sync package for reusable Codex assets across your Windows machines.
It is intended to live in OneDrive, while machine-local Codex state remains in `%USERPROFILE%\.codex`.

## Included

- `skills/agents-skills/`: skills from `%USERPROFILE%\.agents\skills`
- `skills/codex-skills/`: skills from `%USERPROFILE%\.codex\skills`
- `skills/minimax-skills/`: skills from `%USERPROFILE%\.codex\minimax-skills`, preserving the original MiniMax grouping
- `skills/custom/`: additional roots supplied through `-SkillRoots`, separated by source folder
- `hooks/`: extracted hook config and hook scripts
- `profiles/`: sanitized `*.config.toml` profile files and sanitized source config snapshot
- `environment/devices/`: one software and tool inventory JSON file per Windows machine; this records state for comparison but does not sync applications, WSL disks, binaries, or caches
- `rules/`: global `AGENTS.md` / `AGENTS.override.md` if found
- `global-memory/`: durable cross-project memory namespaces and assets
- `memory-system/project-memory-registry.tsv`: shared project-memory registry with device-scoped local paths and portable OneDrive paths
- `session-data/`: active/archived Codex conversations plus `session_index.jsonl` title metadata
- `desktop-state/`: Codex desktop sidebar/project state used by controlled Push/Pull sync
- `CodexProjects/`: synchronized transport copy for projectless workspaces normally created under `Documents\Codex`
- `scheduled-tasks/`: source XML plus portable settings for the memory maintenance task
- `plugins/inventory.json`: installed plugin names and cached versions; plugin caches themselves are excluded
- `projects/`: optional project-level Codex files, only if you ran with `-ProjectRoots` or `-ScanProjects`
- `manifest.json`: file inventory with SHA256 hashes
- `Install-CodexKitForWindows.ps1`: helper to install skills links, hooks, and profiles on another Windows machine
- `Switch-CodexMachine.cmd`: user-facing helper for Push/Pull/Status when switching machines
- `Start-CodexManaged.cmd`: unified launcher that installs shared task/sidebar organization before launch and publishes local changes after exit
- `Start-CodexManaged.vbs`: hidden background launcher for normal use

## Deliberately excluded

- `auth.json`
- `history.jsonl`
- logs, caches, and sandbox data
- machine-specific command approval rules from `.codex\rules`
- generated plugin caches (the plugin inventory is kept instead)
- SSH keys and certificate/key files
- `.env` files and likely token/secret/credential files

## Recommended setup on another Windows machine

```powershell
cd "__DESTINATION_ROOT__"
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -Recommended
```

`-Recommended` installs live skill and session links, global guidance links, hooks, linked global memory, controlled project-workspace synchronization, captures a per-device environment inventory, and installs a Start menu shortcut named `ChatGPT`. Every machine uses the same Managed launcher. Conversation history, desktop organization, and projectless workspaces are included by default. Project files are pulled before launch and pushed after exit while `Documents\Codex` remains a real local directory. Profiles, Codex configuration, Codex automations, and the memory-maintenance scheduled task remain excluded. Choose model, reasoning, feature, and other Codex preferences locally on each machine. The legacy `-InstallResidentStartMenuShortcut` parameter is accepted only for command-line compatibility and installs the same Managed shortcut.

The legacy `-InstallCodexProjectsLink` parameter remains accepted, but it now
enables the same controlled Pull/Push mode and converts an old Junction into a
real directory. Same-path edits made independently on both sides stop before
mutation and are reported under the device-local CodexKit state directory.

Install the memory-maintenance task only on the single designated maintenance host:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -InstallMemoryTask
```

On other machines, remove an accidentally installed task with:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -RemoveMemoryTask
```

Check health without changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -Status
```

The status check verifies the `manifest.json` generation time and SHA-256 hashes for the installer, README, managed launchers, skill-source inventory, and the complete `codexkit-sync` skill. It reports changed, untracked, or missing core files as `[STALE]`; refresh those records with a new export rather than `-Repair`. It also compares `plugins\inventory.json` with this machine's plugin cache and lists missing `marketplace/plugin` entries. It does not require exact cached versions and does not install plugins automatically.

If a Codex update leaves both an old marketplace cache and its renamed `-remote` counterpart for the same plugin, the exporter records only the `-remote` package identity.

Repair only missing, outdated, or incorrect recommended components:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -Repair
```

The installer stores its previous device name and paths in `%USERPROFILE%\.local\state\codexkit\installation.json`. If the Windows profile, device name, Codex home, or OneDrive CodexKit path changes, run `-Status` and then `-Repair` to migrate links, hooks, and this device's local registry rows. If the Windows profile directory itself is moved, preserve that state file at the same relative location under the new profile before running `-Repair`.

Backups use `<target>.backup.<timestamp>`. The installer keeps the newest two backups per target by default. Override this with `-BackupRetention N`. Retention cleanup runs only after replacement succeeds; a failed link or copy restores the original target automatically.

Each export removes reusable package files that were recorded in the previous
manifest but are absent from the current export. Conversation and desktop-state
data are never removed by stale cleanup, even after an opt-out; remove that
private data manually only after confirming the exact target. Files never
managed by the exporter are also preserved.

Conversation history and desktop sidebar/project state are exported by default.
`-Recommended` installs the session links, while desktop organization is
synchronized by the Managed launcher's controlled Pull/Push lifecycle instead
of a fragile live single-file link. Use `-ExcludeSessions` or
`-ExcludeDesktopState` during export only when intentionally opting out.

If the normal setup is already installed and only session links need repair:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -Repair -InstallSessionLinks
```

Every machine uses the same Managed lifecycle. The running-device warning is advisory; do not actively edit the same conversation on two machines, and allow OneDrive to finish syncing `session-data` before opening a conversation that was just updated elsewhere.

`-InstallSessionLinks` links `.codex\sessions`, `.codex\archived_sessions`, and `.codex\session_index.jsonl`. The title index controls recent thread names. Desktop sidebar project order, pinned state, task-to-project assignments, and workspace hints live in `.codex\.codex-global-state.json`; reconcile that organization with the controlled commands below.

`Pull` installs the shared primary organization locally; `Push` publishes this machine's organization to the shared primary. Both preserve device-only window, permission, browser-tab, and active-workspace state. Use `Sync` only for an intentional three-way merge; same-field conflicts then keep the currently synchronizing machine's value with device-local diagnostics.

When no other device has a fresh running heartbeat, controlled synchronization also removes duplicate `session_index.jsonl` rows by task ID and retains the newest title record. Malformed JSON blocks repair, and one rollback copy is retained device-locally.

The desktop task list is additionally indexed in each machine's local `.codex\state_5.sqlite`. A managed Pull reconciles missing top-level tasks from the linked OneDrive rollout files before launch, preserves existing database rows, ignores legacy child-rollout aliases, and includes the verified database hash in the launch receipt. Never copy or live-link this SQLite database between machines.

Synchronization also checks for catastrophic state loss before installing a merge. If a file suddenly shrinks to a small shell or loses workspace/task markers and thread references, synchronization is blocked and the candidate is copied to the device-local `%USERPROFILE%\.local\state\codexkit\desktop-state-quarantine` folder. OneDrive keeps only the shared `desktop-state\.codex-global-state.json`, one timestamped backup, and the small advisory `desktop-state\codex-running.json`; conflict reports are device-local as well.

```powershell
# After closing ChatGPT on either machine:
.\Switch-CodexMachine.cmd -Action Push

# Before opening ChatGPT on either machine:
.\Switch-CodexMachine.cmd -Action Pull

# The clearer equivalent name:
.\Switch-CodexMachine.cmd -Action Sync
```

For a menu-style workflow, run:

```powershell
.\Switch-CodexMachine.cmd
```

All machines use the same launcher. It installs the shared primary task/sidebar organization before launch, warns when another device is active, waits for ChatGPT to exit, and publishes this machine's changes back to OneDrive:

```powershell
.\Start-CodexManaged.cmd
```

For background launch without a console window, double-click `Start-CodexManaged.vbs`. Keep the `.cmd` launcher for troubleshooting when you want to see logs.

The installer always presents the shortcut as `ChatGPT` and targets `Start-CodexManaged.vbs`. `-Repair` converts legacy Resident/Synced shortcuts to Managed, refreshes the icon from the current Appx desktop executable, and removes legacy CodexKit-managed names only after the replacement verifies successfully.

Every machine is a full task/sidebar editor. An already-running ChatGPT process is never hot-patched; the next Managed start pulls the shared primary organization, while this machine publishes its organization after exit. Avoid editing the same conversation simultaneously because session JSONL files are live-linked rather than three-way merged.

Managed startup is fail-closed. ChatGPT opens only after every nested command succeeds and a fresh device-local `%USERPROFILE%\.local\state\codexkit\last-desktop-sync.json` receipt verifies the authoritative Pull plus current script, state, and organization hashes. Pull never rewrites the shared primary; Push never rewrites the local source. Inputs are hash-checked again before commit so a mid-sync OneDrive change aborts safely. The hidden shortcut shows a Windows error popup on failure; run `Start-CodexManaged.cmd` to see the full diagnostic output. The receipt is device-local and is not backed up to OneDrive.

The managed launchers update `desktop-state\codex-running.json`: `running` is `1` while at least one fresh device heartbeat exists and `0` otherwise. Opening Codex on another device shows a Yes/No warning listing the active device. Normal exit clears that device immediately; heartbeats older than five minutes are ignored after a crash or power loss. This is an advisory OneDrive signal, not a strict distributed lock, and it is never backed up as desktop state.

The launchers read the installed Appx manifest instead of assuming the desktop process is always named `Codex.exe`. This supports current packages whose desktop entry point is `app\ChatGPT.exe` while keeping compatibility with older Codex-named builds; the bundled CLI under `app\resources\codex.exe` is not mistaken for the desktop app.

Then open Codex and run:

```text
/hooks
```

Review and trust the hooks on that machine. This step is mandatory: Codex skips non-managed command hooks until the current definitions are trusted.
The installer also ensures that `[features] hooks = true` is present in `%USERPROFILE%\.codex\config.toml`. Fully exit and restart Codex before running `/hooks`.

If the desktop app does not expose `/hooks`, open Windows Terminal, run `codex`, then run `/hooks` inside the Codex CLI and trust both definitions. The trust state is stored locally in `.codex\config.toml`; do not sync it from another machine.

If `codex` is not on `PATH`, let the installer locate and open the CLI bundled with the desktop app:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexKitForWindows.ps1 -InstallHooks -OpenHooksTrust
```

After sending a prompt, verify real Codex execution by checking:

```powershell
Get-Content "$env:USERPROFILE\.local\state\memory-and-improvement\user-prompt-hook.last-run.json"
```

The `source` field must be `codex`, not `codexkit-self-test`.

## Notes

- `hooks\hooks.source.json` is the exact extracted source hook config.
- `hooks\hooks.template.json` is the portable version used by the installer. If it contains `__CODEXKIT__`, the installer replaces it with the local CodexKit path.
- `profiles\_extracted\config.sanitized.toml` is a sanitized snapshot of your main `config.toml`; it is not automatically installed as your main config.
- The source scheduled-task XML is diagnostic only. The installer recreates the task from portable JSON so the new machine gets its own user SID and paths.
- Plugin caches are deliberately omitted because Codex can redownload them; the inventory and sanitized config retain the useful installation information.
- The installer merges a legacy machine-local project registry into the shared CodexKit registry. Existing shared rows are retained.
- `-InstallGlobalMemoryLink` backs up the current local tree and links `%USERPROFILE%\global-memory` to the OneDrive CodexKit tree for automatic synchronization.
- `-InstallGlobalMemory` remains available for one-time snapshot installation.
- Linked global memory disables maintenance Git commits because OneDrive should not synchronize `.git` metadata between machines.
- `-InstallGlobalGuidanceLinks` links `.codex\AGENTS.md` and `.codex\AGENTS.override.md` to `CodexKit\rules\global` for automatic synchronization.
- `.codex\rules` remains device-local because it contains machine command approval policy.
- Device/path migration state remains local at `.local\state\codexkit\installation.json`.
- Installer backups retain the newest two copies per target by default.
- Maintenance logs, last-run state, hook reflect markers, removed-project archives, scheduled-task instances, and Git metadata remain device-local.
- Session JSONL files can contain prompts, responses, file paths, and pasted secrets. Keep the OneDrive account protected and avoid opening Codex on two linked machines at the same time.
'@
    $content = $content.Replace("__EXTRACTED_ON__", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    $content = $content.Replace("__SOURCE_CODEX_HOME__", $script:SourceCodexHome)
    $content = $content.Replace("__SOURCE_AGENTS_ROOT__", $script:SourceAgentsRoot)
    $content = $content.Replace("__MACHINE__", $env:COMPUTERNAME)
    $content = $content.Replace("__USER__", $env:USERNAME)
    $content = $content.Replace("__DESTINATION_ROOT__", $script:DestinationRoot)
    Write-TextFileSafe -Destination (Join-Path $script:DestinationRoot "README.md") -Content $content -Category "generated"
}

function Write-ManifestAndLogs {
    Write-Info "Writing manifest and logs"
    $manifest = [pscustomobject]@{
        product = "codex-synckit"
        manifest_version = 1
        generated_at = (Get-Date).ToString("o")
        machine = $env:COMPUTERNAME
        user = $env:USERNAME
        source_codex_home = $script:SourceCodexHome
        source_agents_root = $script:SourceAgentsRoot
        source_global_memory = $script:SourceGlobalMemory
        memory_task_name = $MemoryTaskName
        include_memory_subsystem = [bool]$IncludeMemorySubsystem
        include_sessions = [bool]$IncludeSessions
        include_desktop_state = [bool]$IncludeDesktopState
        destination_root = $script:DestinationRoot
        dry_run = [bool]$DryRun
        files = $script:ManifestFiles
        warnings = $script:Warnings
    }
    if (-not $DryRun) {
        $manifestPath = Join-Path $script:DestinationRoot "manifest.json"
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $logsDir = Join-Path $script:DestinationRoot "logs"
        Ensure-Directory $logsDir
        $script:Actions | Export-Csv -LiteralPath (Join-Path $logsDir "extract-actions-$script:Timestamp.csv") -NoTypeInformation -Encoding UTF8
        Add-ManifestFile -Path $manifestPath -Category "generated" -Source "generated"
    } else {
        Write-Host "[DRY]  would write manifest.json and logs" -ForegroundColor DarkCyan
    }
}

function Install-OneLocalDirLink {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Target,
        [string]$Label = "directory"
    )

    if (-not (Test-Path -LiteralPath $source -PathType Container) -and -not $DryRun) {
        throw "Cannot install link because extracted skills folder does not exist: $source"
    }

    Ensure-Directory (Split-Path -Parent $Target)

    if (Test-Path -LiteralPath $Target) {
        $backup = "$Target.backup.$script:Timestamp"
        if ($DryRun) {
            Write-Host "[DRY]  move $Target -> $backup" -ForegroundColor DarkCyan
        } else {
            Move-Item -LiteralPath $Target -Destination $backup -Force
            Write-Warn2 "Existing $Label folder moved to backup: $backup"
        }
    }

    if ($DryRun) {
        Write-Host "[DRY]  mklink /D `"$Target`" `"$Source`"" -ForegroundColor DarkCyan
        Add-Action -Type "mklink" -Source $Source -Destination $Target -Status "dry-run"
        return
    }

    cmd /c mklink /D "$Target" "$Source" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "Directory symlink failed for $Label; trying junction instead."
        cmd /c mklink /J "$Target" "$Source" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create $Label link: $Target -> $Source"
        }
    }
    Add-Action -Type "mklink" -Source $Source -Destination $Target -Status "created"
    Write-Ok "$Label link installed: $Target -> $Source"
}

function Install-LocalSkillsLink {
    Write-Info "Installing local skills links to CodexKit"
    $codexSource = Join-Path $script:DestinationRoot "skills\codex-skills"
    $agentsSource = Join-Path $script:DestinationRoot "skills\agents-skills"
    $minimaxSource = Join-Path $script:DestinationRoot "skills\minimax-skills"
    Install-OneLocalDirLink -Source $codexSource -Target (Join-Path $script:SourceCodexHome "skills") -Label ".codex skills"
    if (Test-Path -LiteralPath $agentsSource -PathType Container) {
        Install-OneLocalDirLink -Source $agentsSource -Target (Join-Path $script:SourceAgentsRoot "skills") -Label ".agents skills"
    } else {
        Write-Skip "no exported agents-skills directory to link"
    }
    if (Test-Path -LiteralPath $minimaxSource -PathType Container) {
        Install-OneLocalDirLink -Source $minimaxSource -Target (Join-Path $script:SourceCodexHome "minimax-skills") -Label ".codex minimax-skills"
    }
}

function Create-ZipArchive {
    Write-Info "Creating zip archive"
    $parent = Split-Path -Parent $script:DestinationRoot
    $name = Split-Path -Leaf $script:DestinationRoot
    $zip = Join-Path $parent "$name-$script:Timestamp.zip"
    if ($DryRun) {
        Write-Host "[DRY]  zip $script:DestinationRoot -> $zip" -ForegroundColor DarkCyan
        return
    }
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $script:DestinationRoot -DestinationPath $zip -Force
    Write-Ok "zip created: $zip"
}

# Main
try {
    $script:SourceCodexHome = Resolve-PathLoose $SourceCodexHome
    $script:SourceAgentsRoot = Resolve-PathLoose $SourceAgentsRoot
    $script:SourceGlobalMemory = Resolve-PathLoose $SourceGlobalMemory

    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
        $DestinationRoot = Join-Path (Get-OneDriveRoot) "CodexKit"
    }
    $script:DestinationRoot = Resolve-PathLoose $DestinationRoot
    $script:PreviousManagedPaths = @(Get-PreviousManagedPaths)

    Write-Info "Source Codex home: $script:SourceCodexHome"
    Write-Info "Source agents root: $script:SourceAgentsRoot"
    Write-Info "Source global memory: $script:SourceGlobalMemory"
    Write-Info "Long-term memory subsystem: $(if ($IncludeMemorySubsystem) { 'included' } else { 'excluded' })"
    Write-Info "Default skill roots: $script:SourceAgentsRoot\skills ; $script:SourceCodexHome\skills ; $script:SourceCodexHome\minimax-skills"
    Write-Info "Destination CodexKit: $script:DestinationRoot"
    if ($DryRun) { Write-Warn2 "Dry-run mode is enabled. No files will be written or changed." }

    Ensure-Directory $script:DestinationRoot
    $baseDirectories = @("skills", "hooks", "hooks\scripts", "profiles", "profiles\_extracted", "rules", "scripts", "projects", "logs", "session-data", "desktop-state", "plugins")
    if ($IncludeMemorySubsystem) {
        $baseDirectories += @("global-memory", "memory-system", "scheduled-tasks")
    }
    foreach ($d in $baseDirectories) {
        Ensure-Directory (Join-Path $script:DestinationRoot $d)
    }

    Write-GitIgnore
    Export-Skills
    Export-Hooks
    Export-ConfigsAndRules
    Export-GlobalMemory
    Export-Sessions
    Export-DesktopState
    Export-PluginInventory
    Export-MemoryScheduledTask

    $rootsToExport = New-Object System.Collections.Generic.List[string]
    foreach ($r in $ProjectRoots) { if (-not [string]::IsNullOrWhiteSpace($r)) { $rootsToExport.Add($r) | Out-Null } }
    if ($ScanProjects) {
        $scanned = @(Find-ProjectRootsForScan -BaseRoots (Get-DefaultProjectSearchRoots))
        foreach ($r in $scanned) { if (-not $rootsToExport.Contains($r)) { $rootsToExport.Add($r) | Out-Null } }
        Write-Info "Project scan found $($scanned.Count) candidate project folders."
    }
    Export-ProjectCodexFiles -Roots $rootsToExport.ToArray()

    Write-InstallHelper
    Write-SwitchCommand
    Write-StartCommands
    Write-Readme
    if ($IncludeMemorySubsystem) {
        Add-ManifestFile -Path (Join-Path $script:DestinationRoot "memory-system\project-memory-registry.tsv") -Category "memory-system" -Source "shared CodexKit state"
    }
    Remove-StaleManagedFiles

    if ($InstallLinks) {
        Install-LocalSkillsLink
        Write-Warn2 "Hooks were not automatically installed. Use Install-CodexKitForWindows.ps1 -InstallHooks, then run /hooks in Codex."
    }

    Write-ManifestAndLogs

    if ($CreateZip) { Create-ZipArchive }

    Write-Host ""
    Write-Ok "CodexKit extraction complete."
    Write-Host "Destination: $script:DestinationRoot" -ForegroundColor Green
    if ($script:Warnings.Count -gt 0) {
        Write-Host "Warnings:" -ForegroundColor Yellow
        $script:Warnings | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
    }
    Write-Host ""
    Write-Host "Next recommended command on this machine, after reviewing the extracted folder:" -ForegroundColor Cyan
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$script:DestinationRoot\Install-CodexKitForWindows.ps1`" -Recommended" -ForegroundColor White
    if ($IncludeDesktopState) {
        Write-Host "For desktop sidebar state, use: `"$script:DestinationRoot\Switch-CodexMachine.cmd`" -Action Push/Pull" -ForegroundColor White
    }
    Write-Host "Then open Codex and run: /hooks" -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
