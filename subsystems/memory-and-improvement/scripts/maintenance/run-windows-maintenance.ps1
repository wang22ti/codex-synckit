[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('project', 'global', 'both')]
    [string]$Scope,

    [Parameter(Mandatory = $true)]
    [ValidateSet('fixed', 'interval')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$Namespace,

    [Parameter(Mandatory = $true)]
    [string]$GlobalRoot,

    [Parameter(Mandatory = $true)]
    [string]$GlobalNamespacesRoot,

    [Parameter(Mandatory = $true)]
    [string]$StateRoot,

    [Parameter(Mandatory = $true)]
    [string]$BashPath,

    [int]$IntervalMinutes = 240,
    [ValidateSet('true', 'false')]
    [string]$GitCommit = 'true',
    [ValidateSet('true', 'false')]
    [string]$Writeback = 'true',
    [ValidateSet('true', 'false')]
    [string]$SkillPolicyWriteback = 'false',
    [int]$MinRecurrence = 2
)

$ErrorActionPreference = 'Stop'

function Convert-ToBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive/$rest"
    }
    return ($Path -replace '\\', '/')
}

function Quote-BashArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

if (-not (Test-Path -LiteralPath $BashPath -PathType Leaf)) {
    throw "Git Bash was not found at: $BashPath"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$maintenanceScript = if ($Mode -eq 'interval') {
    Join-Path $scriptDir 'interval-maintenance.sh'
} else {
    Join-Path $scriptDir 'nightly-maintenance.sh'
}

$logDir = Join-Path $StateRoot 'logs'
$null = New-Item -ItemType Directory -Force -Path $logDir
$logFile = Join-Path $logDir 'windows-maintenance.log'

$env:HOME = $env:USERPROFILE
$env:SELF_IMPROVING_GLOBAL_ROOT = $GlobalRoot
$env:SELF_IMPROVING_GLOBAL_NAMESPACES_ROOT = $GlobalNamespacesRoot
$env:SELF_IMPROVING_GIT_AUTOCOMMIT = $GitCommit
$env:SELF_IMPROVING_NIGHTLY_WRITEBACK = $Writeback
$env:SELF_IMPROVING_SKILL_POLICY_WRITEBACK = $SkillPolicyWriteback
$env:SELF_IMPROVING_ORGANIZE_MIN_RECURRENCE = [string]$MinRecurrence

$arguments = @(
    (Convert-ToBashPath $maintenanceScript),
    '--scope', $Scope,
    '--project-root', (Convert-ToBashPath $ProjectRoot),
    '--namespace', $Namespace,
    '--git-commit', $GitCommit,
    '--writeback', $Writeback,
    '--skill-policy-writeback', $SkillPolicyWriteback,
    '--min-recurrence', [string]$MinRecurrence
)

if ($Mode -eq 'interval') {
    $arguments += @(
        '--interval-minutes', [string]$IntervalMinutes,
        '--state-file', (Convert-ToBashPath (Join-Path $StateRoot 'interval-maintenance.last-run'))
    )
}

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"[$timestamp] Starting Windows memory maintenance mode=$Mode scope=$Scope" |
    Out-File -LiteralPath $logFile -Encoding utf8 -Append

$command = ($arguments | ForEach-Object { Quote-BashArgument ([string]$_) }) -join ' '
$quotedCommand = '"' + ($command -replace '"', '\"') + '"'
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $BashPath
$startInfo.Arguments = "-lc $quotedCommand"
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
$null = $process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$exitCode = $process.ExitCode

foreach ($stream in @($stdout, $stderr)) {
    if (-not [string]::IsNullOrEmpty($stream)) {
        $stream | Out-File -LiteralPath $logFile -Encoding utf8 -Append
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"[$timestamp] Finished Windows memory maintenance exit=$exitCode" |
    Out-File -LiteralPath $logFile -Encoding utf8 -Append

if ($exitCode -ne 0) {
    exit $exitCode
}
