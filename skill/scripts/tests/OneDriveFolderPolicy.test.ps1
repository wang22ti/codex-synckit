#requires -version 5.1
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'Set-OneDriveFolderExclusions.ps1'
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
$function = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-MissingFolderValues'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$path = 'HKCU:\Software\CodexKit-Policy-Test-' + [guid]::NewGuid().ToString('N')
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    New-Item -Path $path | Out-Null
    New-ItemProperty -LiteralPath $path -Name 'node_modules' -Value 'node_modules' -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $path -Name '.venv' -Value 'custom-folder' -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $path -Name 'custom-number' -Value 7 -PropertyType DWord | Out-Null
    Add-MissingFolderValues $path @('node_modules', '.venv', '__pycache__')
    $key=Get-Item -LiteralPath $path
    Assert ($key.GetValue('node_modules') -eq 'node_modules') 'Existing rule was removed'
    Assert ($key.GetValue('.venv') -eq 'custom-folder') 'Custom collision was overwritten'
    Assert ($key.GetValue('custom-number') -eq 7 -and $key.GetValueKind('custom-number') -eq 'DWord') 'Custom value/type changed'
    Assert ($key.GetValue('CodexKit-.venv-1') -eq '.venv') 'Colliding requested rule not added'
    $count=$key.ValueCount
    Add-MissingFolderValues $path @('node_modules', '.venv', '__pycache__')
    Assert ((Get-Item -LiteralPath $path).ValueCount -eq $count) 'Second apply added duplicates'
    Write-Host '[OK] Registry policy preserves existing rules/types, handles collisions, and is idempotent.'
} finally {
    if ($path -notmatch '^HKCU:\\Software\\CodexKit-Policy-Test-[a-f0-9]{32}$') { throw 'Unsafe test cleanup' }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
