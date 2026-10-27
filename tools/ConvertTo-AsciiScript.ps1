#Requires -Version 5.1
<#
.SYNOPSIS
    Writes the release copy of Install-ResolveRU.ps1: plain ASCII, so that
    "irm ... | iex" also works in Windows PowerShell 5.1.
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OutFile,
    # Link to the readable source, written into the header of the copy.
    [string]$SourceUrl
)
$ErrorActionPreference = 'Stop'

# Копия установщика для релиза — только ASCII. Windows PowerShell 5.1 читает ответ «irm» без
# charset (так отдаёт GitHub Releases) как Latin-1, а PowerShell 7.4 — как UTF-8, и BOM ни тот,
# ни другой не пропускает: «<#» после него уже не комментарий, param() не первый. Файл без BOM
# с кириллицей тоже нельзя: при запуске файлом Windows PowerShell читает его в кодировке ANSI.
# Поэтому текст вне ASCII в строках пишется кодами символов, русские комментарии не попадают.
function Get-CharCodes {
    param([string]$Run)
    '$(-join [char[]](' + ((@($Run.ToCharArray()) | ForEach-Object { '0x{0:X4}' -f [int]$_ }) -join ',') + '))'
}

function ConvertTo-AsciiScript {
    param([string]$Text)
    $nonAscii = [regex]'[^\x00-\x7F]+'
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Install-ResolveRU.ps1, line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)" }
    $sb = New-Object Text.StringBuilder $Text
    # С конца файла: смещения ещё не обработанных токенов не сдвигаются.
    $todo = @($tokens | Where-Object { $nonAscii.IsMatch($_.Text) } | Sort-Object { $_.Extent.StartOffset } -Descending)
    foreach ($t in $todo) {
        $start = $t.Extent.StartOffset; $end = $t.Extent.EndOffset; $at = "line $($t.Extent.StartLineNumber)"
        if ($t.Kind -eq 'Comment' -and $t.Text.StartsWith('<#')) {
            $lines = $t.Text -split "`r?`n"
            if ($nonAscii.IsMatch($lines[0]) -or $nonAscii.IsMatch($lines[-1])) { throw "${at}: non-ASCII text on the first or last line of a block comment" }
            $kept = (@($lines | Where-Object { -not $nonAscii.IsMatch($_) }) -join "`r`n") -replace '\r\n(?:[ \t]*\r\n){2,}', "`r`n`r`n"
            $kept = $kept -replace '(?m)^(\.[A-Z]+\b[^\r\n]*)\r\n(?:[ \t]*\r\n)+', "`$1`r`n"
            [void]$sb.Remove($start, $end - $start).Insert($start, $kept)
        } elseif ($t.Kind -eq 'Comment') {
            $text = $sb.ToString()
            $lineStart = if ($start -gt 0) { $text.LastIndexOf([char]10, $start - 1) + 1 } else { 0 }
            if ($text.Substring($lineStart, $start - $lineStart).Trim()) {
                # Комментарий после кода: убираем его и пробелы перед ним.
                $from = $start
                while ($from -gt $lineStart -and ' ', "`t" -contains $text[$from - 1]) { $from-- }
                [void]$sb.Remove($from, $end - $from)
            } else {
                $nl = $text.IndexOf([char]10, $end)
                $to = if ($nl -ge 0) { $nl + 1 } else { $end }
                [void]$sb.Remove($lineStart, $to - $lineStart)
            }
        } elseif ($t.Kind -eq 'StringLiteral') {
            # 'текст' → "текст" с экранированием и кодами символов.
            $body = $t.Value -replace '([`"$])', '`$1'
            $body = $nonAscii.Replace($body, { param($m) Get-CharCodes $m.Value })
            [void]$sb.Remove($start, $end - $start).Insert($start, '"' + $body + '"')
        } elseif ($t.Kind -eq 'StringExpandable') {
            if ($nonAscii.IsMatch($t.Text.Substring(0, 1)) -or $nonAscii.IsMatch($t.Text.Substring($t.Text.Length - 1))) { throw "${at}: typographic quotes delimit a string" }
            if (@($t.NestedTokens | Where-Object { $nonAscii.IsMatch($_.Text) }).Count) { throw "${at}: non-ASCII text inside `$(...) or a variable of an expandable string" }
            if ($t.Text -match '`[^\x00-\x7F]') { throw "${at}: an escaped non-ASCII character" }
            $body = $nonAscii.Replace($t.Text, { param($m) Get-CharCodes $m.Value })
            [void]$sb.Remove($start, $end - $start).Insert($start, $body)
        } else {
            throw "${at}: non-ASCII text in a $($t.Kind) token is not supported"
        }
    }
    $result = $sb.ToString()

    # Проверка: только ASCII, разбирается, и код тот же — кроме комментариев и записи строк.
    if ($nonAscii.IsMatch($result)) { throw 'The ASCII copy still contains non-ASCII characters' }
    $newTokens = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($result, [ref]$newTokens, [ref]$errors)
    if ($errors.Count) { throw "The ASCII copy does not parse, line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)" }
    $code = {
        param($List)
        $prev = $null
        foreach ($x in $List) {
            if ($x.Kind -eq 'Comment' -or ($x.Kind -eq 'NewLine' -and $prev -eq 'NewLine')) { continue }
            $prev = $x.Kind; $x
        }
    }
    $a = @(& $code $tokens); $b = @(& $code $newTokens)
    if ($a.Count -ne $b.Count) { throw "The ASCII copy has $($b.Count) code tokens instead of $($a.Count)" }
    $decode = [regex]'\$\(-join \[char\[\]\]\(((?:0x[0-9A-F]{4},?)+)\)\)'
    for ($i = 0; $i -lt $a.Count; $i++) {
        $x = $a[$i]; $y = $b[$i]
        if ($x.Text -ceq $y.Text -and $x.Kind -eq $y.Kind) { continue }
        $same = if ($x.Kind -eq 'StringLiteral' -and $y.Kind -eq 'StringExpandable') {
            # Кроме кодов символов, в строке нет «$»: её значение можно вычислить.
            ($decode.Replace($y.Text, '') -replace '`.', '') -notmatch '\$' -and
                ([scriptblock]::Create($y.Text).InvokeReturnAsIs() -ceq $x.Value)
        } elseif ($x.Kind -eq 'StringExpandable' -and $y.Kind -eq 'StringExpandable') {
            $decode.Replace($y.Text, { param($m) -join @($m.Groups[1].Value -split ',' | ForEach-Object { [char][Convert]::ToInt32($_, 16) }) }) -ceq $x.Text
        } else { $false }
        if (-not $same) { throw "The ASCII copy differs from the source at line $($x.Extent.StartLineNumber): $($x.Text)" }
    }
    $result
}

$source = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$ascii = ConvertTo-AsciiScript $source
$note = @(
    "# Release copy of Install-ResolveRU.ps1 (source SHA256 $((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash))."
    '# Plain ASCII, so that "irm ... | iex" also works in Windows PowerShell 5.1: text in other'
    '# alphabets is written as character codes, Russian comments are left out.'
)
if ($SourceUrl) { $note += "# Readable source: $SourceUrl" }
$requires = [regex]::Match($ascii, '(?m)^#Requires ')
if (-not $requires.Success) { throw 'Install-ResolveRU.ps1: #Requires line not found' }
[IO.File]::WriteAllText($OutFile, $ascii.Insert($requires.Index, ($note -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
