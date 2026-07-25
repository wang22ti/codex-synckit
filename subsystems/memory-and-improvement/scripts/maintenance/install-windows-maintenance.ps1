[CmdletBinding()]
param(
    [ValidateSet('project', 'global', 'both')]
    [string]$Scope,

    [ValidateSet('fixed', 'interval')]
    [string]$Mode,

    [int]$IntervalMinutes,
    [int]$Hour,
    [int]$Minute,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$TaskName = 'Codex Memory Maintenance',
    [string]$BashPath,
    [ValidateSet('true', 'false')]
    [string]$GitCommit,
    [ValidateSet('true', 'false')]
    [string]$Writeback,
    [ValidateSet('true', 'false')]
    [string]$SkillPolicyWriteback,
    [int]$MinRecurrence,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Find-GitBash {
    $candidates = @(
        $BashPath,
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Git for Windows Bash was not found. Install Git for Windows or pass -BashPath.'
}

function Convert-ToBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive/$rest"
    }
    return ($Path -replace '\\', '/')
}

function Convert-FromBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^/([A-Za-z])/(.*)$') {
        $drive = $Matches[1].ToUpperInvariant()
        $rest = $Matches[2] -replace '/', '\'
        return "${drive}:\$rest"
    }
    return $Path
}

function Quote-BashArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Quote-TaskArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedBash = Find-GitBash
$settingsScript = Convert-ToBashPath (Join-Path $scriptDir 'resolve-maintenance-settings.sh')
$settingsLines = & $resolvedBash -lc (Quote-BashArgument $settingsScript)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to resolve memory maintenance defaults through Git Bash.'
}

$settings = @{}
foreach ($line in $settingsLines) {
    if ($line -match '^([^=]+)=(.*)$') {
        $settings[$Matches[1]] = $Matches[2]
    }
}

if (-not $PSBoundParameters.ContainsKey('Scope')) { $Scope = $settings.scope }
if (-not $PSBoundParameters.ContainsKey('Mode')) { $Mode = $settings.mode }
if (-not $PSBoundParameters.ContainsKey('IntervalMinutes')) { $IntervalMinutes = [int]$settings.interval_minutes }
if (-not $PSBoundParameters.ContainsKey('Hour')) { $Hour = [int]$settings.hour }
if (-not $PSBoundParameters.ContainsKey('Minute')) { $Minute = [int]$settings.minute }
if (-not $PSBoundParameters.ContainsKey('GitCommit')) { $GitCommit = $settings.git_commit }
if (-not $PSBoundParameters.ContainsKey('Writeback')) { $Writeback = $settings.writeback }
if (-not $PSBoundParameters.ContainsKey('SkillPolicyWriteback')) { $SkillPolicyWriteback = $settings.skill_policy_writeback }
if (-not $PSBoundParameters.ContainsKey('MinRecurrence')) { $MinRecurrence = [int]$settings.min_recurrence }

if ($IntervalMinutes -le 0) { throw '-IntervalMinutes must be greater than 0.' }
if ($Hour -lt 0 -or $Hour -gt 23) { throw '-Hour must be between 0 and 23.' }
if ($Minute -lt 0 -or $Minute -gt 59) { throw '-Minute must be between 0 and 59.' }

$runner = Join-Path $scriptDir 'run-windows-maintenance.ps1'
$powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$hiddenRunner = Join-Path $scriptDir 'run-windows-maintenance-hidden.vbs'
$globalRoot = Convert-FromBashPath $settings.global_root
$globalNamespacesRoot = Convert-FromBashPath $settings.global_namespaces_root
$stateRoot = Convert-FromBashPath $settings.state_root
$runnerArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Quote-TaskArgument $runner),
    '-Scope', $Scope,
    '-Mode', $Mode,
    '-ProjectRoot', (Quote-TaskArgument ([IO.Path]::GetFullPath($ProjectRoot))),
    '-Namespace', $settings.namespace,
    '-GlobalRoot', (Quote-TaskArgument $globalRoot),
    '-GlobalNamespacesRoot', (Quote-TaskArgument $globalNamespacesRoot),
    '-StateRoot', (Quote-TaskArgument $stateRoot),
    '-BashPath', (Quote-TaskArgument $resolvedBash),
    '-IntervalMinutes', [string]$IntervalMinutes,
    '-GitCommit', $GitCommit,
    '-Writeback', $Writeback,
    '-SkillPolicyWriteback', $SkillPolicyWriteback,
    '-MinRecurrence', [string]$MinRecurrence
)
$argumentString = $runnerArgs -join ' '
$hiddenArguments = @(
    '//B',
    '//Nologo',
    (Quote-TaskArgument $hiddenRunner),
    (Quote-TaskArgument $powerShell)
) + $runnerArgs
$hiddenArgumentString = $hiddenArguments -join ' '

$summary = [ordered]@{
    task_name = $TaskName
    mode = $Mode
    scope = $Scope
    project_root = [IO.Path]::GetFullPath($ProjectRoot)
    interval_minutes = $IntervalMinutes
    daily_time = '{0:D2}:{1:D2}' -f $Hour, $Minute
    bash_path = $resolvedBash
    executable = $wscript
    arguments = $hiddenArgumentString
}

if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 3
    return
}

$action = New-ScheduledTaskAction -Execute $wscript -Argument $hiddenArgumentString
if ($Mode -eq 'interval') {
    $start = (Get-Date).AddMinutes(1)
    $intervalTrigger = New-ScheduledTaskTrigger -Once -At $start `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $logonTrigger = New-ScheduledTaskTrigger `
        -AtLogOn `
        -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $trigger = @($intervalTrigger, $logonTrigger)
} else {
    $at = Get-Date -Hour $Hour -Minute $Minute -Second 0
    $trigger = New-ScheduledTaskTrigger -Daily -At $at
}

$settingsObject = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal `
    -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settingsObject `
    -Principal $principal `
    -Description 'Runs memory-and-improvement organization and writeback through Git Bash.' `
    -Force | Out-Null

Write-Output "Installed Windows scheduled task: $TaskName"
