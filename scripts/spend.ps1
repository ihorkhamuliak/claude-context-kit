#!/usr/bin/env pwsh
# spend.ps1 - realni vytraty tokeniv iz transkryptiv Claude Code
#
# Chytaye ~/.claude/projects/**/*.jsonl i sumuye FAKTYCHNI usage-tsyfry vid API.
# Tse ne otsinka po symvolah - tse te, za shcho vystavleno rakhunok.
#
# Ideia vzyata z github.com/fomoles/claude-code-spend (Python).
# Tut vlasna versiya: PowerShell, bez zalezhnostey, i bez otsinky "symvoly/4" -
# my berem lyshe fakt, a rows bez usage rahuyemo okremo, ne pidstavlyayemo nul.
#
# UVAHA: UTF-8 z BOM. Identyfikatory - latynytseiu.
#
#   .\spend.ps1                          - po dniah za ves chas
#   .\spend.ps1 -From 2026-08-20         - z daty
#   .\spend.ps1 -BySession               - po sesiyah, naydorozhchi zverhu
#   .\spend.ps1 -Split 2026-08-24        - porivnyaty "do" i "pislia" datoyu

param(
    [string]$Root = "$HOME\.claude\projects",
    [string]$From = "",
    [string]$To   = "",
    [switch]$BySession,
    [string]$Split = ""
)

$ErrorActionPreference = "Stop"

# Rehex shvydshyi za ConvertFrom-Json na 166 MB
$rxTime  = '"timestamp":"(\d{4}-\d{2}-\d{2})'
$rxIn    = '"input_tokens":(\d+)'
$rxCRead = '"cache_read_input_tokens":(\d+)'
$rxCMake = '"cache_creation_input_tokens":(\d+)'
$rxOut   = '"output_tokens":(\d+)'

$files = Get-ChildItem $Root -Filter *.jsonl -File -Recurse
Write-Host ("Транскриптів: {0}  ({1:N0} МБ)" -f $files.Count, (($files | Measure-Object Length -Sum).Sum/1MB))

$rows    = @{}
$noUsage = 0
$total   = 0

foreach ($f in $files) {
    $session = $f.BaseName
    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        if ($line -notmatch '"usage"') { continue }
        $total++

        if ($line -notmatch $rxTime) { $noUsage++; continue }
        $day = $Matches[1]

        # bereme LYSHE pershe vhodzhennia kozhnoho polia (blok message.usage);
        # "iterations" dublyuye ti sami chysla nyzhche v riadku
        $i  = if ($line -match $rxIn)    { [long]$Matches[1] } else { 0 }
        $cr = if ($line -match $rxCRead) { [long]$Matches[1] } else { 0 }
        $cm = if ($line -match $rxCMake) { [long]$Matches[1] } else { 0 }
        $o  = if ($line -match $rxOut)   { [long]$Matches[1] } else { 0 }

        if (($i + $cr + $cm + $o) -eq 0) { $noUsage++; continue }

        $key = if ($BySession) { "$day|$session" } else { $day }
        if (-not $rows.ContainsKey($key)) {
            $rows[$key] = [PSCustomObject]@{
                Ключ = $key; День = $day; Сесія = $session
                Вхід = [long]0; КешЧит = [long]0; КешЗапис = [long]0; Вихід = [long]0; Ходів = 0
            }
        }
        $r = $rows[$key]
        $r.Вхід += $i; $r.КешЧит += $cr; $r.КешЗапис += $cm; $r.Вихід += $o; $r.Ходів++
    }
}

$data = $rows.Values | Sort-Object День
if ($From) { $data = $data | Where-Object { $_.День -ge $From } }
if ($To)   { $data = $data | Where-Object { $_.День -le $To } }

if (-not $data) { "Немає даних у цьому діапазоні."; return }

# --- Porivnyannia dvoh periodiv ---
if ($Split) {
    $before = $data | Where-Object { $_.День -lt $Split }
    $after  = $data | Where-Object { $_.День -ge $Split }

    function Show-Period($set, $name) {
        if (-not $set) { "$name : немає даних"; return $null }
        $days = ($set | Select-Object -ExpandProperty День -Unique).Count
        $cr   = ($set | Measure-Object КешЧит -Sum).Sum
        $cm   = ($set | Measure-Object КешЗапис -Sum).Sum
        $o    = ($set | Measure-Object Вихід -Sum).Sum
        $h    = ($set | Measure-Object Ходів -Sum).Sum
        [PSCustomObject]@{
            Період = $name; Днів = $days; Ходів = $h
            КешЧитНаХід = [math]::Round($cr / [Math]::Max($h,1))
            КешЧитЗаДень = [math]::Round($cr / [Math]::Max($days,1))
            ВихідНаХід = [math]::Round($o / [Math]::Max($h,1))
        }
    }
    $b = Show-Period $before "до $Split"
    $a = Show-Period $after  "з $Split"
    @($b, $a) | Where-Object { $_ } | Format-Table -AutoSize

    if ($b -and $a) {
        $d = [math]::Round((1 - $a.КешЧитНаХід / [Math]::Max($b.КешЧитНаХід,1)) * 100)
        "Кеш-читання на хід: {0} -> {1}  ({2}%)" -f $b.КешЧитНаХід, $a.КешЧитНаХід, $(if($d -ge 0){"-$d"}else{"+$([Math]::Abs($d))"})
        ""
        "Кеш-читання = розмір контексту, що летить у КОЖНОМУ запиті."
        "Саме воно, а не розмір вікна, множиться на кількість ходів."
    }
    return
}

# --- Zvychainyi zvit ---
$view = if ($BySession) {
    $data | Sort-Object КешЧит -Descending | Select-Object -First 15 День,
        @{n="Ходів";e={$_.Ходів}},
        @{n="КешЧит";e={"{0:N0}" -f $_.КешЧит}},
        @{n="КешЗапис";e={"{0:N0}" -f $_.КешЗапис}},
        @{n="Вихід";e={"{0:N0}" -f $_.Вихід}},
        @{n="Сесія";e={$_.Сесія.Substring(0,8)}}
} else {
    $data | Select-Object День,
        @{n="Ходів";e={$_.Ходів}},
        @{n="КешЧит";e={"{0:N0}" -f $_.КешЧит}},
        @{n="КешЗапис";e={"{0:N0}" -f $_.КешЗапис}},
        @{n="Вихід";e={"{0:N0}" -f $_.Вихід}},
        @{n="КешЧит/хід";e={"{0:N0}" -f ($_.КешЧит / [Math]::Max($_.Ходів,1))}}
}
$view | Format-Table -AutoSize

$sumCR = ($data | Measure-Object КешЧит -Sum).Sum
$sumCM = ($data | Measure-Object КешЗапис -Sum).Sum
$sumO  = ($data | Measure-Object Вихід -Sum).Sum
$sumI  = ($data | Measure-Object Вхід -Sum).Sum
$sumH  = ($data | Measure-Object Ходів -Sum).Sum

""
"РАЗОМ за період"
"  ходів:        {0:N0}" -f $sumH
"  кеш-читання:  {0:N0}" -f $sumCR
"  кеш-запис:    {0:N0}" -f $sumCM
"  вихід:        {0:N0}" -f $sumO
"  вхід (не кеш):{0:N0}" -f $sumI
"  кеш-читання на хід: {0:N0}" -f ($sumCR / [Math]::Max($sumH,1))
if ($noUsage) { "  рядків без цифр (НЕ підставляли нуль): {0:N0} з {1:N0}" -f $noUsage, $total }
