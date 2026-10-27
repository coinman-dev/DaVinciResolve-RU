# Installs the mod from mod\davinci-resolve-ru.wh.cpp into Windhawk as a local
# mod, with logging, for testing (asks for admin rights). Needs the Windhawk
# developer tools.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`""
    return
}

$appDir = 'C:\Program Files\Windhawk'
$cli = Join-Path $appDir 'windhawk-cli.exe'
$src = Join-Path $PSScriptRoot '..\mod\davinci-resolve-ru.wh.cpp'

$ini = Get-Content (Join-Path $appDir 'windhawk.ini') -Encoding Unicode
if ($ini -match '^CompilerPath=$') {
    throw 'Developer tools are not installed: Windhawk -> install developer tools first.'
}

& $cli mod install --file (Resolve-Path $src)
& $cli mod config set local@davinci-resolve-ru loggingEnabled true

Write-Host 'Done. Restart DaVinci Resolve.'
