#!/usr/bin/env pwsh
# brief.ps1 - zbyraye kompaktnyi start sesii zamist chytannia 434 KB
#
# Pryntsyp: ne "os use", a "os stan + de shukaty reshtu".
# Svizhyi shar - u mezhah biudzhetu symvoliv, starshe - lyshe karta z nomeramy riadkiv,
# shchob ahent dohruzhav tochkovo (Read -offset / Grep), a ne tiahnuv use napered.
#
# STELIA. Harnes Claude Code vynosyt u fayl vyvid khuka ponad 10 000 symvoliv (docs hooks: "capped at 10,000 characters") i kladе v
# kontekst lyshe prev'yu na 2 KB. Z 24.08 po 10.09 bryf (57-98 tys. symvoliv) vynosyvsia
# u fayl 72 razy. Tomu kozhen blok maye biudzhet, a test-brief perevirIaye stelIu.
# Bez stelI bryf rostav razom z _Nastupni dii.md, bo toi bravsia tsilkom.
#
# UVAHA: fayl zberihaty v UTF-8 z BOM (PowerShell 5.1 lamaye kyrylytsiu bez noho).
# Identyfikatory - tilky latynytseiu.
#
#   .\brief.ps1                      - bryf dlia tg-autopost
#   .\brief.ps1 -Project "02 - Проєкти\linkedin-autopost"

param(
    [string]$Vault     = $(if ($env:CLAUDE_VAULT) { $env:CLAUDE_VAULT } else { "$HOME\Vault" }),
    [string]$Project   = $(if ($env:CLAUDE_PROJECT) { $env:CLAUDE_PROJECT } else { "02 - Проєкти\my-project" }),
    [int]$NextBudget   = 2100,   # svizhe z _Nastupni dii.md, symvoliv
    [int]$DashBudget   = 0,      # ostanniy zapys Dashboard (0 = ne braty: dubliuye _Nastupni dii)
    [int]$StaticBudget = 1300,   # Aktyvni proyekty + Fokus z Dashboard
    [int]$StateBudget  = 1400,   # svizhe z _stan.md
    [int]$MapBudget    = 800,    # kozhna karta
    [int]$MaxChars     = 9500,   # stelia: vyvid khuka ponad 10 000 symvoliv harnes vynosyt u fayl
    [string]$MemoryDir = $(if ($env:CLAUDE_MEMORY_DIR) { $env:CLAUDE_MEMORY_DIR } else { "$HOME\.claude\projects\my-vault\memory" }),
    [double]$SignalScale = 1.0   # mnozhnyk porohiv syhnaliv rostu; test stavyt 0.00001 - dovesty, shcho datchyk bachyt
)

$ErrorActionPreference = "Stop"

# kontrolni fakty - spilni z test-brief.ps1. Svoyi (facts.ps1) abo pryklad; nemaye oboh - bryf usio odno zbyrayetsia.
$Facts = @()
foreach ($ff in "$PSScriptRoot\facts.ps1", "$PSScriptRoot\facts.example.ps1") {
    if (Test-Path $ff) { . $ff; break }
}

function Read-Lines($path) {
    if (Test-Path $path) { @(Get-Content $path -Encoding UTF8) } else { @() }
}

# Sektsii po '## '. Preambula do pershoho ## - sektsiya bez nazvy.
function Get-Sections($lines) {
    $secs = New-Object System.Collections.Generic.List[object]
    $start = 0; $title = ""
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s') {
            if ($i -gt $start) { $secs.Add(@{ Start = $start; End = $i - 1; Title = $title }) }
            $start = $i; $title = $lines[$i].TrimStart('#').Trim()
        }
    }
    if ($lines.Count -gt $start) { $secs.Add(@{ Start = $start; End = $lines.Count - 1; Title = $title }) }
    return $secs
}

# Riadky zverhu, poky vlazyt u biudzhet. Povertaye nomer pershoho nevzhytoho riadka (-1 = vse vlizlo).
function Add-Budgeted($lines, $secs, [int]$budget, [string]$label) {
    $used = 0; $cut = -1
    foreach ($s in $secs) {
        for ($i = $s.Start; $i -le $s.End; $i++) {
            $len = $lines[$i].Length + 1
            if ($used + $len -gt $budget) { $cut = $i; break }
            & $add $lines[$i]; $used += $len
        }
        if ($cut -ge 0) { break }
    }
    if ($cut -ge 0) { & $add "_(далі обрізано - з рядка $($cut + 1) у $label)_" }
    return $cut
}

# Karta: zaholovky z nomeramy riadkiv, u mezhah biudzhetu.
function Add-Map($secs, [int]$from, [int]$budget, [string]$label) {
    $used = 0; $left = 0
    foreach ($s in $secs) {
        if ($s.End -lt $from -or -not $s.Title) { continue }
        $line = "  {0,5}  {1}" -f ($s.Start + 1), $s.Title
        if ($used + $line.Length + 1 -gt $budget) { $left++; continue }
        & $add $line; $used += $line.Length + 1
    }
    if ($left) { & $add "  ... ще $left розділів - Grep по $label" }
}

$statePath = "$Vault\$Project\_стан.md"
$state     = Read-Lines $statePath
$dash      = Read-Lines "$Vault\Dashboard.md"
$next      = Read-Lines "$Vault\_Наступні дії.md"

$out = New-Object System.Collections.Generic.List[string]
$add = { param($s) $out.Add($s) }

& $add "# БРИФ СЕСІЇ - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
& $add ""
& $add "Свіжий шар у межах бюджету + карти з номерами рядків. Решту догружай точково:"
& $add "Read з -offset по номеру рядка або Grep по темі. Великі файли цілком не читай."
& $add ""

# --- 1. Nastupni dii: svizhe + karta ---
if ($next.Count) {
    $secs = Get-Sections $next
    & $add "---"
    & $add "## НАСТУПНІ ДІЇ - свіже (``_Наступні дії.md``, $($next.Count) рядків)"
    & $add ""
    $cut = Add-Budgeted $next $secs $NextBudget "_Наступні дії.md"
    if ($cut -ge 0) {
        & $add ""
        & $add "Карта решти ``_Наступні дії.md``:"
        Add-Map $secs $cut $MapBudget "_Наступні дії.md"
    }
    & $add ""
}

# --- 2. Dashboard: Aktyvni proyekty + Fokus, ostanniy zapys, karta statyky ---
if ($dash.Count) {
    $secs = Get-Sections $dash
    & $add "---"
    & $add "## DASHBOARD - структурна частина"
    & $add ""
    $keep = @($secs | Where-Object { $_.Title -match '^(Активні проєкти|Фокус)' })
    if ($keep.Count) { $null = Add-Budgeted $dash $keep $StaticBudget "Dashboard.md" }
    & $add ""
    if ($DashBudget -gt 0) {
        & $add "## DASHBOARD - останній запис"
        & $add ""
        $null = Add-Budgeted $dash $secs $DashBudget "Dashboard.md"
        & $add ""
    }
    $rest = @($secs | Where-Object { $_.Title -match '^(Зони|Завершені)' })
    if ($rest.Count) {
        & $add "Ще в Dashboard.md:"
        Add-Map $rest 0 $MapBudget "Dashboard.md"
    }
    & $add "Хроніка Dashboard - Grep по даті або темі."
    & $add ""
}

# --- 3. _stan.md: svizhe + karta ---
if ($state.Count) {
    $secs = Get-Sections $state
    & $add "---"
    & $add "## СТАН ПРОЄКТУ - свіже (``_стан.md``, $($state.Count) рядків)"
    & $add ""
    $cut = Add-Budgeted $state $secs $StateBudget "_стан.md"
    & $add ""
    & $add "---"
    & $add "## КАРТА СТАНУ - решта файлу, догружати за номером рядка"
    & $add ""
    Add-Map $secs ([Math]::Max($cut, 0)) $MapBudget "_стан.md"
    & $add ""
}

# --- 4. Pokazhchyky ---
& $add "---"
& $add "## ДЕ ЩО ЛЕЖИТЬ"
& $add ""
& $add "- стан проєкту: ``$Project\_стан.md`` ($($state.Count) рядків)"
& $add "- наступні дії: ``_Наступні дії.md`` ($($next.Count) рядків)"
& $add "- Dashboard:    ``Dashboard.md`` ($($dash.Count) рядків)"
& $add "- знання:       ``04 - Знання\`` - Grep по темі"
& $add "- архів:        ``06 - Архів\`` - історія до 31.07"
& $add ""

# Komanda startu na serveri - lokalna, poza git (mistyt adresu servera).
# Poklady odyn riadok u <vault>\.claude\start-command.txt
$cmdFile = "$Vault\.claude\start-command.txt"
if (Test-Path $cmdFile) {
    $cmd = (Get-Content $cmdFile -Raw -Encoding UTF8).Trim()
    if ($cmd) {
        & $add "Старт сесії на сервері:"
        & $add "``$cmd``"
        & $add ""
    }
}

# --- 6. Kontrolni fakty - ostanniymy, shchob bachyty VES bryf ---
# Tak nichoho ne hubytsia: fakt abo v bryfi, abo v bryfi ye yoho riadok z adresoyu.
$sofar   = $out -join "`n"
$sources = @(
    @{ N = "_стан.md";         L = $state }
    @{ N = "_Наступні дії.md"; L = $next }
    @{ N = "Dashboard.md";     L = $dash }
)
$factLines = @()
foreach ($f in $Facts) {
    if ($sofar -match $f.Rx) { continue }
    foreach ($src in $sources) {
        $hit = $false
        for ($i = 0; $i -lt $src.L.Count; $i++) {
            if ($src.L[$i] -notmatch $f.Rx) { continue }
            # vyrizka navkolo zbihu, shchob sam fakt ne vidrizavsia
            $t = $src.L[$i].Trim()
            $m = [regex]::Match($t, $f.Rx)
            $from = [Math]::Max(0, $m.Index - 60)
            $len  = [Math]::Min(170, $t.Length - $from)
            $cutT = $t.Substring($from, $len)
            if ($from -gt 0) { $cutT = "..." + $cutT }
            if ($from + $len -lt $t.Length) { $cutT += "..." }
            $factLines += "  [{0}:{1}] {2}" -f $src.N, ($i + 1), $cutT
            $hit = $true; break
        }
        if ($hit) { break }
    }
}
if ($factLines.Count) {
    & $add "---"
    & $add "## КОНТРОЛЬНІ ФАКТИ, що не влізли у свіже (файл:рядок)"
    & $add ""
    $factLines | ForEach-Object { & $add $_ }
}

# --- 6. Hroshi - ostanniymy: naymensh vazhlyve, pershym ide pid nizh stelI ---
$money = @()
foreach ($set in @(@{L=$state; N="стан"}, @{L=$dash; N="dash"})) {
    for ($i = 0; $i -lt [Math]::Min(500, $set.L.Count); $i++) {
        if ($set.L[$i] -match '\$\s?\d' -and $set.L[$i] -match '(міс|добу|день|запит|канал|витрат)') {
            $t = $set.L[$i].Trim(); if ($t.Length -gt 170) { $t = $t.Substring(0, 170) + "..." }
            $money += "  [{0} {1,4}] {2}" -f $set.N, ($i + 1), $t
        }
    }
}
if ($money.Count) {
    & $add ""
    & $add "---"
    & $add "## ЦИФРИ ВИТРАТ (грепом, бо потрібні частіше, ніж лежать зверху)"
    & $add ""
    $money | Select-Object -First 4 | ForEach-Object { & $add $_ }
}

# --- 7. Syhnaly rostu: pravylo "rostemo - pereviryayemo, chy mozhna ekonomyty" (10.09) ---
# U zvychainyi den blok porozhniy i v bryf ne ide. Z'yavyvsia - chas na zamir
# (reread-by-tool.py, spend.ps1) abo /revision. Porohy - rozmir, pry yakomu rist
# uzhe koshtuye kontekstu.
$signals = New-Object System.Collections.Generic.List[string]
function Test-Size($path, [double]$limitKB, [string]$what) {
    if (-not (Test-Path $path)) { return }
    $kb = [math]::Round((Get-Item $path).Length / 1KB)
    $lim = [math]::Round($limitKB * $SignalScale, 3)
    if ($kb -gt $lim) { $signals.Add("  - $what $kb КБ > $lim КБ") }
}
Test-Size "$MemoryDir\MEMORY.md"    30  "MEMORY.md (іде в КОЖНУ сесію):"
Test-Size "$Vault\CLAUDE.md"        15  "CLAUDE.md (іде в КОЖНУ сесію):"
Test-Size "$Vault\_Наступні дії.md" 100 "_Наступні дії.md:"
Test-Size "$Vault\Dashboard.md"     250 "Dashboard.md:"
Test-Size $statePath                500 "_стан.md проєкту:"
if (Test-Path $MemoryDir) {
    Get-ChildItem $MemoryDir -Filter *.md | Where-Object { $_.Name -ne "MEMORY.md" } |
        ForEach-Object { Test-Size $_.FullName 100 "памʼять $($_.Name):" }
}

# Blok syhnaliv staye odrazu pislia shapky - shchob yoho bulo vydno pershym.
function Join-Brief {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange($out)
    if ($signals.Count) {
        $blk = @("---", "## ⚠️ СИГНАЛИ РОСТУ - перевір, чи можна зекономити (правило growth-economy-check)", "") + @($signals) + @("")
        $lines.InsertRange([Math]::Min(5, $lines.Count), [string[]]$blk)
    }
    return ($lines -join "`n")
}

$text = Join-Brief

# --- Stelia - ostanniy zapobizhnyk. Khuk zapuskayetsia sam, test - lyshe koly yoho hanyaiut.
# Pereyty 10 000 = movchky vtratyty VES bryf (harnes vyneset u fayl). Tomu rizhemo khvist
# i kazhemo pro tse zverhu - tse tezh syhnal rostu.
if ($text.Length -gt $MaxChars) {
    $signals.Add("  - бриф уперся в стелю: $($text.Length) символів > $MaxChars, хвіст обрізано - переглянь бюджети")
    $text = Join-Brief
    $keep = $text.LastIndexOf("`n", $MaxChars - 150)
    $text = $text.Substring(0, $keep) + "`n_(бриф обрізано до стелі хука - решта за картами у файлах)_"
    [Console]::Error.WriteLine("[УВАГА: бриф обрізано до стелі $MaxChars символів]")
}
$text

# statystyka v stderr, shchob ne potrapyla v samyi bryf
$kb = [math]::Round([System.Text.Encoding]::UTF8.GetByteCount($text) / 1KB, 1)
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("[бриф: $($text.Length) символів, $kb КБ, $($out.Count) рядків]")
