# measure-context.ps1 - skilky koshtuye start sesii
#
# Rahuye FAKT (symvoly, baity) i daye OTSINKU tokeniv cherez koefitsiyent.
# Koefitsiyent kalibruyetsia odyn raz po realniy tsyfri z /context (-Calibrate).
# Bez kalibruvannia tsyfra tokeniv nablyzna; vidnoshennia "do/pislia" tochne zavzhdy.
#
# UVAHA: fayl zberihaty v UTF-8 z BOM, inakshe PowerShell 5.1 lamaye kyrylytsiu.
# Identyfikatory - tilky latynytseiu. Kyrylytsia - lyshe v tekstovyh riadkah.
#
#   .\measure-context.ps1                    - zamir i zapys u loh
#   .\measure-context.ps1 -SelfTest          - dovesty, shcho zamir bachyt pohane
#   .\measure-context.ps1 -Calibrate 164599  - vpysaty realnu tsyfru z /context

param(
    [string]$Vault   = $(if ($env:CLAUDE_VAULT) { $env:CLAUDE_VAULT } else { "$HOME\Vault" }),
    [string]$Project = $(if ($env:CLAUDE_PROJECT) { $env:CLAUDE_PROJECT } else { "02 - Проєкти\my-project" }),
    [string]$Log     = "$PSScriptRoot\..\docs\measurements.csv",
    [double]$CharsPerToken = 2.07,   # kalibrovano 24.08 po /context: MEMORY.md 12429 symv = 6.0k tok
    [int]$WindowK = 1000,            # vikno modeli v tysiachah tokeniv (Opus 5 = 1M)
    [switch]$SelfTest,
    [double]$Calibrate = 0
)

$Memory = "$(if ($env:CLAUDE_MEMORY_DIR) { $env:CLAUDE_MEMORY_DIR } else { "$HOME\.claude\projects\my-vault\memory" })\MEMORY.md"

# Shcho vantazhytsia na starti sesii za pravylamy CLAUDE.md
function Get-StartFiles {
    @(
        @{ Role = "інструкції"; Path = "$Vault\CLAUDE.md" }
        @{ Role = "огляд";      Path = "$Vault\Dashboard.md" }
        @{ Role = "проєкт";     Path = "$Vault\$Project\_стан.md" }
        @{ Role = "пам'ять";    Path = $Memory }
    )
}

function Measure-Set {
    param($Files, $Cpt)
    foreach ($f in $Files) {
        if (-not (Test-Path $f.Path)) { continue }
        $chars = (Get-Content $f.Path -Raw -Encoding UTF8).Length
        [PSCustomObject]@{
            Роль    = $f.Role
            Файл    = Split-Path $f.Path -Leaf
            КБ      = [math]::Round((Get-Item $f.Path).Length / 1KB, 1)
            Символи = $chars
            Токени  = [math]::Round($chars / $Cpt)
        }
    }
}

# --- Kalibruvannia: vpysuyemo realnu tsyfru z /context ---
if ($Calibrate -gt 0) {
    $rows  = Measure-Set (Get-StartFiles) $CharsPerToken
    $chars = ($rows | Measure-Object Символи -Sum).Sum
    $new   = [math]::Round($chars / $Calibrate, 3)
    "Символів у старті: $chars"
    "Реальних токенів:  $Calibrate"
    "Коефіцієнт:        $new  (було $CharsPerToken)"
    ""
    'Впиши в скрипт: [double]$CharsPerToken = ' + $new
    return
}

# --- Samoperevirka: zamir musyt pobachyty rozdutyi fayl ---
if ($SelfTest) {
    $before = (Measure-Set (Get-StartFiles) $CharsPerToken | Measure-Object Токени -Sum).Sum

    $tmp = Join-Path $env:TEMP "ctx-selftest-$(Get-Random)"
    New-Item -ItemType Directory -Path "$tmp\$Project" -Force | Out-Null
    foreach ($f in Get-StartFiles) {
        if ($f.Path -eq $Memory) { continue }
        $dst = $f.Path.Replace($Vault, $tmp)
        New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
        Copy-Item $f.Path $dst -Force
    }

    # dokleyuyemo 25k symvoliv smittia u _stan.md - tsyfra ZOBOVYAZANA vyrosty
    $fake = "$tmp\$Project\_стан.md"
    Add-Content $fake ("х" * 25000) -Encoding UTF8

    $after = (Measure-Set @(
        @{ Role="інструкції"; Path="$tmp\CLAUDE.md" }
        @{ Role="огляд";      Path="$tmp\Dashboard.md" }
        @{ Role="проєкт";     Path=$fake }
        @{ Role="пам'ять";    Path=$Memory }
    ) $CharsPerToken | Measure-Object Токени -Sum).Sum

    Remove-Item $tmp -Recurse -Force
    $delta    = $after - $before
    $expected = [math]::Round(25000 / $CharsPerToken)

    "САМОПЕРЕВІРКА ЗАМІРУ"
    "  до роздування:       $before tok"
    "  після +25k символів: $after tok"
    "  приріст:             $delta tok   (очікували ~$expected)"
    ""
    if ($delta -ge $expected * 0.9) {
        "ЗАМІР РОБОЧИЙ - бачить роздування."
    } else {
        "ЗАМІР ЗЛАМАНИЙ - не побачив 25k символів. Цифрам не вірити."
        exit 1
    }
    return
}

# --- Zvychainyi zamir ---
$rows = Measure-Set (Get-StartFiles) $CharsPerToken
$rows | Format-Table -AutoSize

$tok = ($rows | Measure-Object Токени -Sum).Sum
$kb  = [math]::Round(($rows | Measure-Object КБ -Sum).Sum, 1)
$pct = [math]::Round($tok / ($WindowK * 10), 1)
"ЧИТАННЯ ЗА СТАРИМ ПРАВИЛОМ: $kb КБ  ~$tok токенів  ($pct% вікна ${WindowK}k)"
""
"Це НЕ автоматична витрата: порожня сесія коштує ~37k (промпт+інструменти+пам'ять)."
"Ці токени з'являються, лише якщо агент реально прочитає ці файли."
"Головна ціна не тут, а в тому, що контекст летить у КОЖНОМУ запиті - див. spend.ps1."

# loh: odyn riadok na zamir, shchob bachyty dreif
$dir = Split-Path $Log
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (-not (Test-Path $Log)) { "дата,КБ,токени,примітка" | Out-File $Log -Encoding utf8 }
$note = if ($env:CTX_NOTE) { $env:CTX_NOTE } else { "" }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$kb,$tok,$note" | Add-Content $Log -Encoding utf8
"записано в $Log"
