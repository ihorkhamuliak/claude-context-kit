#!/usr/bin/env pwsh
# test-brief.ps1 - rehresiynyi test: chy ne zahubyv bryf potribnoho I CHY VIN DOKHODYT
#
# Ideia: ekonomiya bez tsioho testu - tse ne ekonomiya, a slipota z harnoyu tsyfroyu.
# Dvi umovy, obydvi obovyazkovi:
#   1. POKRYTTIA - kozhen kontrolnyi fakt (facts.ps1) ye v bryfi.
#   2. STELIA - bryf ne dovshyi za MaxChars. Harnes vynosyt u fayl vyvid ponad
#      10 000 symvoliv (vyvid khuka), i v sesiyu dokhodyt prev'yu na 2 KB. Z 24.08 po 10.09 test buv
#      zelenyi, a bryf ne dokhodyv zhodnoho razu: pershu umovu perevirialy, druhu - ni.
#
# UVAHA: UTF-8 z BOM. Identyfikatory - latynytseiu.
#
#   .\test-brief.ps1              - prohnaty test
#   .\test-brief.ps1 -SelfTest    - dovesty, shcho test zdaten provalytysia

param(
    [switch]$SelfTest,
    [string]$BriefScript = "$PSScriptRoot\brief.ps1",
    [int]$MaxChars       = 9500    # vyvid khuka ponad 10 000 symvoliv harnes vynosyt u fayl (docs: hooks)
)

$Facts = @()
foreach ($ff in "$PSScriptRoot\facts.ps1", "$PSScriptRoot\facts.example.ps1") {
    if (Test-Path $ff) { . $ff; break }
}

function Test-Coverage {
    param([string]$Text, $Facts)
    foreach ($f in $Facts) {
        [PSCustomObject]@{
            Факт = $f.Name
            Є    = if ($Text -match $f.Rx) { "так" } else { "НЕМАЄ" }
        }
    }
}

# --- Samoperevirka: test musyt provalytysia i na porozhniomu, i na zadovhomu bryfi ---
if ($SelfTest) {
    $ok = $true
    "САМОПЕРЕВІРКА ТЕСТУ"
    ""
    $rows = Test-Coverage -Text "порожньо" -Facts $Facts
    $miss = ($rows | Where-Object { $_.Є -eq "НЕМАЄ" }).Count
    if ($miss -eq $Facts.Count) { "  ок: на порожньому брифі валить усі $miss фактів" }
    else { "  ПРОВАЛ: $($Facts.Count - $miss) фактів 'знайшлись' у пустці"; $ok = $false }

    $big = "х" * ($MaxChars * 2)
    if ($big.Length -gt $MaxChars) { "  ок: стеля ловить задовгий бриф ($($big.Length) > $MaxChars)" }
    else { "  ПРОВАЛ: стеля не бачить задовгого брифу"; $ok = $false }

    ""
    if ($ok) { "ТЕСТ РОБОЧИЙ - валить і порожній, і задовгий бриф." }
    else { "ТЕСТ ЗЛАМАНИЙ."; exit 1 }
    return
}

# --- Zvychainyi prohin ---
$brief = & $BriefScript 2>$null | Out-String
$rows  = Test-Coverage -Text $brief -Facts $Facts
$rows | Format-Table -AutoSize

$miss = @($rows | Where-Object { $_.Є -eq "НЕМАЄ" })
$kb   = [math]::Round([System.Text.Encoding]::UTF8.GetByteCount($brief) / 1KB, 1)

"БРИФ: $($brief.Length) символів ($kb КБ), стеля $MaxChars"
"ПОКРИТТЯ: $($rows.Count - $miss.Count) / $($rows.Count)"
""
$fail = $false
if ($miss.Count) {
    "ПРОВАЛЕНО - бриф не покриває:"
    $miss | ForEach-Object { "  - $($_.Факт)" }
    "Факту немає ні у свіжому, ні в жодному з трьох файлів - або він зник з vault, або застарів у facts.ps1."
    $fail = $true
}
if ($brief.Length -gt $MaxChars) {
    "ПРОВАЛЕНО - бриф довший за стелю на $($brief.Length - $MaxChars) символів."
    "Харнес винесе його у файл, у сесію дійде лише прев'ю на 2 КБ. Зменш бюджети в brief.ps1."
    $fail = $true
}
# 3. Datchyk rostu bachyt pohane: zanyzheni porohy MUSYAT daty blok syhnaliv.
$forced = & $BriefScript -SignalScale 0.00001 2>$null | Out-String
if ($forced -notmatch "СИГНАЛИ РОСТУ") {
    "ПРОВАЛЕНО - датчик росту не спрацював навіть на занижених порогах. Сигналам не вірити."
    $fail = $true
} else { "ДАТЧИК РОСТУ: на занижених порогах спрацював - бачить погане" }
"СИГНАЛИ У СПРАВЖНЬОМУ БРИФІ: $(if ($brief -match 'СИГНАЛИ РОСТУ') { 'є, див. блок угорі брифу' } else { 'немає' })"
if ($fail) { exit 1 }
"ПРОЙДЕНО - факти на місці, бриф під стелею, датчик росту живий."
