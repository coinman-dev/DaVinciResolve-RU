<#
.SYNOPSIS
    Дополнение русского перевода DaVinci Resolve: установка, обновление, удаление.
    Russian translation completion for DaVinci Resolve: install, update, remove.

.DESCRIPTION
    Официальный русский перевод DaVinci Resolve неполный. Скрипт кладёт в папку
    Resolve два файла:
      * resolve_ru_extra.qm — недостающие русские строки;
      * dxva2.dll — загрузчик: Resolve сам загружает его из своей папки, а он
        добавляет resolve_ru_extra.qm к русскому переводу Resolve. Все функции
        системной dxva2.dll он передаёт ей без изменений.
    Файлы Resolve не меняются. Файлы берутся из GitHub Releases или из папки
    рядом со скриптом и проверяются по SHA256SUMS.txt.

    Установка кладёт в <Resolve>\DaVinciResolve-RU копию скрипта и
    DaVinciResolve-RU.cmd: оттуда потом обновляют и удаляют перевод.

    The official Russian translation of DaVinci Resolve is incomplete. The script
    puts two files into the Resolve folder: resolve_ru_extra.qm with the missing
    strings, and dxva2.dll, a loader that Resolve loads from its folder and that
    adds resolve_ru_extra.qm to the Russian translation of Resolve (it forwards
    the system dxva2.dll unchanged). Resolve's own files aren't changed. The files
    come from GitHub Releases or the folder next to the script and are verified
    with SHA256SUMS.txt. Installation also puts a copy of the script and
    DaVinciResolve-RU.cmd into <Resolve>\DaVinciResolve-RU: run it later to
    update or remove the translation.

.EXAMPLE
    irm https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest/download/Install-ResolveRU.ps1 | iex
    Запуск одной командой из PowerShell. / Run with one command from PowerShell.

.EXAMPLE
    .\Install-ResolveRU.ps1 -Action Install -Yes
    Установить или обновить без вопросов. / Install or update without questions.

.EXAMPLE
    .\Install-ResolveRU.ps1 -Action Remove
    Удалить. / Remove.

.NOTES
    Windows PowerShell 5.1 или PowerShell 7. Права администратора запрашиваются,
    только если папка Resolve защищена от записи (Program Files). Перед
    изменениями Resolve нужно закрыть.
    Windows PowerShell 5.1 or PowerShell 7. Administrator rights are requested
    only when the Resolve folder is write-protected (Program Files). Close Resolve
    before making changes.
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    # Что сделать. Без параметра открывается меню.
    [ValidateSet('Menu', 'Install', 'Remove', 'Status')]
    [string]$Action = 'Menu',

    # Папка DaVinci Resolve (где лежит Resolve.exe). По умолчанию ищется сама.
    [string]$ResolvePath,

    # Папка с dxva2.dll и resolve_ru_extra.qm. Без загрузки из сети.
    [string]$Source,

    # Тег релиза GitHub, например v1.0.0. По умолчанию — последний релиз.
    [string]$Release = 'latest',

    # Не задавать вопросов (для сценариев).
    [switch]$Yes,

    # Язык сообщений скрипта.
    [ValidateSet('auto', 'ru', 'en')]
    [string]$UILang = 'auto',

    # Не ждать нажатия клавиши перед выходом.
    [switch]$NoPause,

    # Служебный: скрипт перезапущен с правами администратора.
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$script:Repo       = 'coinman-dev/DaVinciResolve-RU'
$script:CacheRoot  = Join-Path ([IO.Path]::GetTempPath()) 'DaVinciResolve-RU'
$script:ScriptPath = $PSCommandPath
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
$script:Files      = @('dxva2.dll', 'resolve_ru_extra.qm')
# Папка в папке Resolve с копией скрипта и DaVinciResolve-RU.cmd (меню).
$script:ToolFolder = 'DaVinciResolve-RU'
# Строка из dxva2.dll проекта (UTF-16): отличает его от чужой dxva2.dll.
$script:LoaderMark = '[davinci-resolve-ru]'

#region Messages and console

# Язык сообщений: русский, если русский язык интерфейса Windows, региональных форматов
# или системы.
$script:Lang = $UILang
if ($script:Lang -eq 'auto') {
    $names = @()
    try { $names += (Get-UICulture).Name } catch { }
    try { $names += (Get-Culture).Name } catch { }
    try { $names += [Globalization.CultureInfo]::InstalledUICulture.Name } catch { }
    $script:Lang = if (@($names | Where-Object { $_ -like 'ru*' }).Count) { 'ru' } else { 'en' }
}

# Возвращает сообщение на текущем языке. Обе строки уже интерполированы.
function T {
    param([Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Ru,
          [Parameter(Position = 1)][AllowEmptyString()][string]$En)
    if ($script:Lang -eq 'en' -and $PSBoundParameters.ContainsKey('En')) { return $En }
    $Ru
}

$script:PauseOnExit = ($Action -eq 'Menu') -or $Elevated

function Test-CanPrompt {
    try { -not [Console]::IsInputRedirected -and [Environment]::UserInteractive } catch { $false }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-BeforeExit {
    if ($NoPause -or -not $script:PauseOnExit) { return }
    try { if ([Console]::IsInputRedirected) { return } } catch { return }
    Write-Host ''
    Write-Host (T '  Нажмите любую клавишу для выхода...' '  Press any key to exit...') -ForegroundColor DarkCyan
    try { $null = [Console]::ReadKey($true); return } catch { }
    try { $null = Read-Host; return } catch { }
}

function Write-Step { param([string]$Message) Write-Host "  → $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Note { param([string]$Message) Write-Host "  ! $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "  ✗ $Message" -ForegroundColor Red }

function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    if ($Yes -or -not (Test-CanPrompt)) { return $Default }
    $hint = if ($Default) { T '[Да/нет]' '[Yes/no]' } else { T '[да/Нет]' '[yes/No]' }
    while ($true) {
        $answer = (Read-Host "  $Question $hint").Trim().ToLower()
        if (-not $answer) { return $Default }
        if ($answer -in @('д', 'да', 'y', 'yes', '1', '+')) { return $true }
        if ($answer -in @('н', 'нет', 'n', 'no', '0', '-')) { return $false }
    }
}

#endregion

#region Elevation

# Командная строка перезапуска: обычный -File с параметрами (не -EncodedCommand: его
# антивирусы считают признаком вредоносного скрипта).
function Get-ElevationArguments {
    param([string]$ScriptPath, [Collections.IDictionary]$Parameters)
    # Кавычки по правилам разбора командной строки Windows: «\» перед кавычкой удваиваются.
    $quote = { param([string]$Text) '"' + ($Text -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $ScriptPath))
    foreach ($key in $Parameters.Keys) {
        if ($key -eq 'Elevated') { continue }
        $value = $Parameters[$key]
        if ($value -is [switch] -or $value -is [bool]) {
            if ($value) { $list += "-$key" }
        } else {
            $list += "-$key"
            $list += (& $quote ([string]$value))
        }
    }
    ($list + '-Elevated') -join ' '
}

function Restart-Elevated {
    param([Collections.IDictionary]$Parameters)
    $path = $script:ScriptPath
    if (-not $path) {
        # Запуск через «irm ... | iex»: у скрипта нет файла, скачиваем его копию.
        $null = New-Item -ItemType Directory -Force -Path $script:CacheRoot
        $path = Join-Path $script:CacheRoot 'Install-ResolveRU.ps1'
        Save-Url -Url (Get-ReleaseUrl 'Install-ResolveRU.ps1') -Destination $path
    }
    $hostExe = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not $hostExe -or $hostExe -notmatch '(pwsh|powershell)\.exe$') {
        $hostExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    }
    $arguments = Get-ElevationArguments -ScriptPath $path -Parameters $Parameters
    Write-Host ''
    Write-Host (T '  Папка Resolve защищена от записи: нужны права администратора.' '  The Resolve folder is write-protected: administrator rights are required.') -ForegroundColor Yellow
    Write-Host (T '  Перезапускаю скрипт — подтвердите запрос системы.' '  Restarting the script - please confirm the system prompt.') -ForegroundColor Yellow
    try {
        $null = Start-Process -FilePath $hostExe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
    } catch {
        throw (T 'Запуск от имени администратора отменён. Откройте PowerShell от имени администратора и запустите скрипт оттуда.' 'Elevation was cancelled. Open PowerShell as administrator and run the script from there.')
    }
    # Дальше работает окно администратора.
    $script:PauseOnExit = $false
}

#endregion

#region Files and downloads

function Get-ReleaseUrl {
    param([string]$Name)
    if ($Release -eq 'latest') { return "https://github.com/$($script:Repo)/releases/latest/download/$Name" }
    "https://github.com/$($script:Repo)/releases/download/$Release/$Name"
}

function Save-Url {
    param([string]$Url, [string]$Destination)
    $partial = "$Destination.part"
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    try {
        if (Test-Path -LiteralPath $curl) {
            & $curl -L --fail --silent --show-error --connect-timeout 20 --retry 2 --retry-delay 3 -o $partial $Url
            if ($LASTEXITCODE -ne 0) { throw (T "не удалось скачать $Url (curl, код $LASTEXITCODE)" "failed to download $Url (curl exit code $LASTEXITCODE)") }
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
        }
        if (-not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -le 0) {
            throw (T "получен пустой файл: $Url" "empty download: $Url")
        }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    } finally {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# SHA256SUMS.txt: строки «<sha256>  <имя файла>».
function Read-Checksums {
    param([string]$Path)
    $sums = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { $sums[$Matches[2]] = $Matches[1].ToLowerInvariant() }
    }
    $sums
}

function Test-Payload {
    param([string]$Dir)
    foreach ($name in $script:Files) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $name))) { return $false }
    }
    $true
}

# Папка с файлами для установки: -Source, папка рядом со скриптом или загрузка из релиза.
function Get-Payload {
    $dir = $null
    if ($Source) {
        $dir = (Resolve-Path -LiteralPath $Source).Path
        if (-not (Test-Payload $dir)) { throw (T "В папке $dir нет dxva2.dll и resolve_ru_extra.qm." "$dir has no dxva2.dll and resolve_ru_extra.qm.") }
    } elseif ($script:ScriptRoot -and (Test-Payload $script:ScriptRoot)) {
        $dir = $script:ScriptRoot
    }

    if ($dir) {
        Write-Step (T "Файлы из папки $dir" "Files from $dir")
    } else {
        $dir = Join-Path $script:CacheRoot ([Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path $dir
        Write-Step (T "Загрузка с GitHub ($($script:Repo), релиз $Release)" "Downloading from GitHub ($($script:Repo), release $Release)")
        foreach ($name in $script:Files + 'SHA256SUMS.txt') {
            Save-Url -Url (Get-ReleaseUrl $name) -Destination (Join-Path $dir $name)
        }
    }

    $sumsPath = Join-Path $dir 'SHA256SUMS.txt'
    if (Test-Path -LiteralPath $sumsPath) {
        $sums = Read-Checksums $sumsPath
        foreach ($name in $script:Files) {
            if ($sums[$name] -ne (Get-Sha256 (Join-Path $dir $name))) {
                throw (T "Контрольная сумма $name не совпадает с SHA256SUMS.txt." "The checksum of $name doesn't match SHA256SUMS.txt.")
            }
        }
        Write-Ok (T 'Контрольные суммы совпадают' 'Checksums match')
    } else {
        Write-Note (T 'SHA256SUMS.txt не найден: файлы не проверены.' 'SHA256SUMS.txt not found: the files are not verified.')
    }
    $dir
}

#endregion

#region Resolve

function Find-ResolvePath {
    if ($ResolvePath) {
        $dir = $ResolvePath
        if ((Split-Path -Leaf $dir) -ieq 'Resolve.exe') { $dir = Split-Path -Parent $dir }
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'Resolve.exe'))) { throw (T "В папке $dir нет Resolve.exe." "$dir has no Resolve.exe.") }
        return (Resolve-Path -LiteralPath $dir).Path
    }

    # Скрипт запущен из <Resolve>\DaVinciResolve-RU (копия, которую кладёт установка) — этот Resolve.
    if ($script:ScriptRoot -and (Split-Path -Leaf $script:ScriptRoot) -eq $script:ToolFolder) {
        $parent = Split-Path -Parent $script:ScriptRoot
        if (Test-Path -LiteralPath (Join-Path $parent 'Resolve.exe')) { return $parent }
    }

    # Ярлык в меню «Пуск»: установщик Resolve позволяет выбрать любую папку.
    $shell = New-Object -ComObject WScript.Shell
    foreach ($root in @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs'))) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($link in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue) {
            if ($link.Name -notlike '*Resolve*') { continue }
            $target = try { $shell.CreateShortcut($link.FullName).TargetPath } catch { $null }
            if ($target -and (Split-Path -Leaf $target) -ieq 'Resolve.exe' -and (Test-Path -LiteralPath $target)) {
                return (Split-Path -Parent $target)
            }
        }
    }

    $default = Join-Path $env:ProgramFiles 'Blackmagic Design\DaVinci Resolve'
    if (Test-Path -LiteralPath (Join-Path $default 'Resolve.exe')) { return $default }

    throw (T 'DaVinci Resolve не найден. Укажите папку: -ResolvePath "D:\...\DaVinci Resolve".' 'DaVinci Resolve not found. Pass its folder: -ResolvePath "D:\...\DaVinci Resolve".')
}

function Get-ResolveVersion {
    param([string]$Dir)
    try { (Get-Item -LiteralPath (Join-Path $Dir 'Resolve.exe')).VersionInfo.ProductVersion } catch { '?' }
}

function Test-Writable {
    param([string]$Dir)
    $probe = Join-Path $Dir ('.ru-write-test-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($probe, [byte[]]@())
        Remove-Item -LiteralPath $probe -Force
        $true
    } catch { $false }
}

# dxva2.dll в папке Resolve: 'none', 'ours' или 'foreign'.
function Get-LoaderState {
    param([string]$Dir)
    $path = Join-Path $Dir 'dxva2.dll'
    if (-not (Test-Path -LiteralPath $path)) { return 'none' }
    $text = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($path))
    if ($text.Contains($script:LoaderMark)) { 'ours' } else { 'foreign' }
}

function Wait-ResolveClosed {
    param([string]$Dir)
    while ($true) {
        $running = @(Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue | Where-Object {
            $p = $null
            try { $p = $_.Path } catch { }
            -not $p -or $p.StartsWith($Dir + '\', [StringComparison]::OrdinalIgnoreCase)
        })
        if (-not $running.Count) { return }
        Write-Note (T 'DaVinci Resolve запущен: пока он работает, файлы в его папке менять нельзя.' 'DaVinci Resolve is running: files in its folder cannot be changed while it runs.')
        if ($Yes -or -not (Test-CanPrompt)) { throw (T 'Закройте DaVinci Resolve и повторите.' 'Close DaVinci Resolve and try again.') }
        $answer = Read-Host (T '  Закройте Resolve и нажмите Enter (0 — отмена)' '  Close Resolve and press Enter (0 - cancel)')
        if ($answer.Trim() -eq '0') { throw (T 'Отменено.' 'Cancelled.') }
    }
}

# Мод Windhawk проекта делает то же самое; вместе с загрузчиком он не нужен.
function Test-WindhawkMod {
    foreach ($id in @('davinci-resolve-ru', 'local@davinci-resolve-ru')) {
        $mod = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$id" -ErrorAction SilentlyContinue
        if ($mod -and -not $mod.Disabled) { return $true }
    }
    $false
}

# Текст этого скрипта. При «irm | iex» файла нет, поэтому берётся корень AST, в котором
# разобран скрипт: это весь исходный текст при любом способе запуска.
function Get-ScriptText {
    $ast = {}.Ast
    while ($ast.Parent) { $ast = $ast.Parent }
    $ast.Extent.Text
}

# Запуск меню двойным щелчком. «Удалить» удаляет и этот файл, а cmd после команды снова
# читает пакетный файл. «(goto) 2>nul» завершает пакетный файл заранее: строка уже разобрана
# (%~dp0 и %* подставлены) и выполняется до конца.
function Get-LauncherText {
    @(
        '@echo off'
        'rem DaVinciResolve-RU: install, update or remove the Russian translation completion of DaVinci Resolve.'
        '(goto) 2>nul & "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ResolveRU.ps1" %*'
    ) -join "`r`n"
}

# Копия скрипта и DaVinciResolve-RU.cmd в <Resolve>\DaVinciResolve-RU: оттуда потом обновляют
# и удаляют перевод, не скачивая скрипт заново.
function Install-ScriptCopy {
    param([string]$Dir)
    $toolDir = Join-Path $Dir $script:ToolFolder
    $null = New-Item -ItemType Directory -Force -Path $toolDir
    $text = Get-ScriptText
    # ASCII-копия из релиза остаётся как в релизе; текст с кириллицей — UTF-8 с BOM.
    $encoding = if ($text -match '[^\x00-\x7F]') { New-Object Text.UTF8Encoding $true } else { [Text.Encoding]::ASCII }
    $target = Join-Path $toolDir 'Install-ResolveRU.ps1'
    # Запуск из этой же копии: файл уже на месте.
    if (-not $script:ScriptPath -or -not [IO.Path]::GetFullPath($script:ScriptPath).Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::WriteAllText($target, $text, $encoding)
    }
    $launcher = Join-Path $toolDir "$($script:ToolFolder).cmd"
    [IO.File]::WriteAllText($launcher, (Get-LauncherText), [Text.Encoding]::ASCII)
    $launcher
}

#endregion

#region Actions

function Show-Status {
    param([string]$Dir)
    Write-Host ''
    Write-Host ("  DaVinci Resolve {0}" -f (Get-ResolveVersion $Dir))
    Write-Host ("  {0} {1}" -f (T 'Папка:' 'Folder:'), $Dir)
    $state = Get-LoaderState $Dir
    $qm = Join-Path $Dir 'resolve_ru_extra.qm'
    $text = switch ($state) {
        'ours'    { if (Test-Path -LiteralPath $qm) { T "установлено ($((Get-Item -LiteralPath $qm).LastWriteTime.ToString('yyyy-MM-dd')))" "installed ($((Get-Item -LiteralPath $qm).LastWriteTime.ToString('yyyy-MM-dd')))" } else { T 'установлено частично (нет resolve_ru_extra.qm)' 'partly installed (no resolve_ru_extra.qm)' } }
        'foreign' { T 'не установлено (в папке чужая dxva2.dll)' 'not installed (a foreign dxva2.dll is in the folder)' }
        default   { T 'не установлено' 'not installed' }
    }
    Write-Host ("  {0} {1}" -f (T 'Дополнение перевода:' 'Translation completion:'), $text)
    if (Test-WindhawkMod) {
        Write-Note (T 'Включён мод Windhawk «DaVinci Resolve: Russian translation completion» — с загрузчиком он не нужен, выключите его.' 'The Windhawk mod "DaVinci Resolve: Russian translation completion" is enabled - it is not needed with the loader, disable it.')
    }
}

function Invoke-Install {
    param([string]$Dir)
    if ((Get-LoaderState $Dir) -eq 'foreign') {
        throw (T "В папке Resolve уже есть чужая dxva2.dll ($Dir\dxva2.dll). Скрипт её не заменяет." "The Resolve folder already has a foreign dxva2.dll ($Dir\dxva2.dll). The script doesn't replace it.")
    }
    $payload = Get-Payload
    Wait-ResolveClosed $Dir
    foreach ($name in $script:Files) {
        Copy-Item -LiteralPath (Join-Path $payload $name) -Destination (Join-Path $Dir $name) -Force
    }
    Write-Ok (T "Установлено в $Dir" "Installed to $Dir")
    $launcher = Install-ScriptCopy $Dir
    Write-Ok (T "Меню для обновления и удаления: $launcher" "Menu to update or remove: $launcher")
    Write-Host ''
    Write-Host (T '  Запустите DaVinci Resolve. Язык интерфейса — русский (или «Auto» при русской Windows):' '  Start DaVinci Resolve. The interface language must be Russian (or Auto on Russian Windows):')
    Write-Host (T '  DaVinci Resolve → Preferences → User → UI Settings → Language.' '  DaVinci Resolve → Preferences → User → UI Settings → Language.')
    if (Test-WindhawkMod) {
        Write-Note (T 'Включён мод Windhawk этого проекта — выключите его, загрузчик его заменяет.' "This project's Windhawk mod is enabled - disable it, the loader replaces it.")
    }
}

function Invoke-Remove {
    param([string]$Dir)
    $state = Get-LoaderState $Dir
    $qm = Join-Path $Dir 'resolve_ru_extra.qm'
    $toolDir = Join-Path $Dir $script:ToolFolder
    if ($state -ne 'ours' -and -not (Test-Path -LiteralPath $qm) -and -not (Test-Path -LiteralPath $toolDir)) {
        Write-Ok (T 'Дополнение перевода не установлено.' 'The translation completion is not installed.')
        return
    }
    Wait-ResolveClosed $Dir
    if ($state -eq 'ours') { Remove-Item -LiteralPath (Join-Path $Dir 'dxva2.dll') -Force }
    Remove-Item -LiteralPath $qm -Force -ErrorAction SilentlyContinue
    # Копия скрипта: если он запущен из неё, PowerShell уже прочитал файл целиком.
    Remove-Item -LiteralPath $toolDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok (T 'Удалено. Resolve снова показывает только официальный перевод.' 'Removed. Resolve shows only the official translation again.')
}

function Show-Menu {
    param([string]$Dir)
    while ($true) {
        Show-Status $Dir
        # По умолчанию (Enter): установить, если ещё не установлено, иначе выйти.
        $default = if ((Get-LoaderState $Dir) -eq 'ours') { '0' } else { '1' }
        $mark = { param([string]$Key) if ($Key -eq $default) { '*' } else { ' ' } }
        Write-Host ''
        Write-Host ((T '   {0} 1. Установить / обновить' '   {0} 1. Install / update') -f (& $mark '1'))
        Write-Host ((T '   {0} 2. Удалить' '   {0} 2. Remove') -f (& $mark '2'))
        Write-Host ((T '   {0} 0. Выход' '   {0} 0. Exit') -f (& $mark '0'))
        Write-Host ''
        $answer = (Read-Host (T "  Выберите действие (Enter — $default)" "  Choose an action (Enter - $default)")).Trim()
        if (-not $answer) { $answer = $default }
        try {
            switch ($answer) {
                '1' { Invoke-Install $Dir }
                '2' { if (Read-YesNo (T 'Удалить дополнение перевода?' 'Remove the translation completion?') $true) { Invoke-Remove $Dir } }
                '0' { return }
                default { continue }
            }
        } catch {
            Write-Fail $_.Exception.Message
        }
    }
}

#endregion

#region Main

$exitCode = 0
try {
    Write-Host ''
    Write-Host (T '  DaVinciResolve-RU — дополнение русского перевода DaVinci Resolve' '  DaVinciResolve-RU - Russian translation completion for DaVinci Resolve') -ForegroundColor Cyan
    $dir = Find-ResolvePath
    if ($Action -ne 'Status' -and -not (Test-Writable $dir) -and -not (Test-Admin)) {
        $parameters = [ordered]@{}
        foreach ($key in $PSBoundParameters.Keys) { $parameters[$key] = $PSBoundParameters[$key] }
        $parameters['ResolvePath'] = $dir
        Restart-Elevated -Parameters $parameters
    } else {
        switch ($Action) {
            'Menu'    { Show-Menu $dir }
            'Install' { Invoke-Install $dir }
            'Remove'  { Invoke-Remove $dir }
            'Status'  { Show-Status $dir }
        }
    }
} catch {
    Write-Fail $_.Exception.Message
    $exitCode = 1
    $script:PauseOnExit = $script:PauseOnExit -or (Test-CanPrompt)
} finally {
    Wait-BeforeExit
}
# При запуске через «irm | iex» exit закрыл бы окно пользователя.
if ($script:ScriptPath) { exit $exitCode }

#endregion
