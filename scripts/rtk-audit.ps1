#!/usr/bin/env pwsh
# rtk-audit.ps1 - chy varto vmykaty avtohuk RTK
#
# Vidpovidaye na odne pytannia: skilky dovhyh komand za sesiyu, i skilky z nyh
# RTK vzahali zdaten stysnuty. Rahuye FAKTYCHNU dovzhynu vyvodu z transkryptiv
# (~/.claude/projects/**/*.jsonl) - te, shcho realno potrapylo v kontekst.
#
# NICHOHO NE ZAPUSKAYE i nichoho ne minyaye: tilky chytannia zhurnaliv.
# Serveru ne torkayetsia. Koefitsiyenty - z nashoho zamiru 24.08 (README).
#
# UVAHA: fayl zberihaty v UTF-8 z BOM. Identyfikatory - lyshe latynytseiu.
#
#   .\rtk-audit.ps1                 - zvit
#   .\rtk-audit.ps1 -SelfTest       - dovesty, shcho zamir bachyt pohane
#   .\rtk-audit.ps1 -From 2026-08-10 - z daty
#   .\rtk-audit.ps1 -Detail         - shche y rozklad po komandah

param(
    [string]$Root = "$HOME\.claude\projects",
    [string]$From = "",
    [switch]$SelfTest,
    [switch]$Detail
)

$ErrorActionPreference = "Stop"

# Pidkomandy, yaki RTK maye (rtk --help, znyato 09.09.2026).
# Vse, choho tut nemaye, RTK ne bachyt fizychno - i my ne krediytuyemo yomu ekonomiyu.
$RtkKnows = @(
    'ls','tree','read','git','gh','glab','aws','psql','pnpm','json','deps','env',
    'find','diff','log','dotnet','docker','kubectl','oc','grep','rg','wget','wc',
    'npm','npx','curl','jest','vitest','prisma','tsc','next','lint','prettier',
    'format','playwright','cargo','ruff','smart','err','test','summary'
)

# Koefitsiyenty ekonomii z NASHOHO zamiru na realnyh komandah (README, "Shcho pokazav RTK").
# Bilsh spetsyfichnyi prefiks vyhraye. Choho tut nemaye - 0 (ne domumuyemo).
$Ratio = [ordered]@{
    'systemctl status' = 0.49
    'docker logs'      = 0.00
    'docker ps'        = 0.72
    'git status'       = 0.70
    'git log'          = 0.00
    'journalctl'       = 0.00
    'find'             = 0.95
    'grep'             = 0.53
    'rg'               = 0.53
    'ls'               = 0.56
    'df'               = 0.46
}

function Get-Payload {
    # dovzhyna JSON-riadka v symvolah pislia rozekranuvannia (\n = 1 symvol, ne 2)
    param([string]$Escaped)
    if (-not $Escaped) { return 0 }
    $s = [regex]::Replace($Escaped, '\\u[0-9a-fA-F]{4}', 'X')
    $s = [regex]::Replace($s, '\\.', 'X')
    return $s.Length
}

function Get-Core {
    # vidkydaye obhortky, shchob dobratys do komandy, yaka daye vyvid
    param([string]$Cmd)
    $c = $Cmd.Trim()
    # "cd ... && real" / "VAR=x && real" - beremo ostanniu lanku
    while ($c -match '^(cd\s[^&|]+|[A-Za-z_][A-Za-z0-9_]*=[^&|]*)&&\s*(.+)$') { $c = $Matches[2].Trim() }
    return $c
}

function Get-Inner {
    # ssh root@host 'INNER'  ->  INNER
    param([string]$Cmd)
    if ($Cmd -match "^ssh\s.*?'(.*)'\s*$") { return $Matches[1].Trim() }
    if ($Cmd -match '^ssh\s.*?"(.*)"\s*$') { return $Matches[1].Trim() }
    return ""
}

function Get-Ratio {
    param([string]$Cmd)
    foreach ($k in $Ratio.Keys) {
        if ($Cmd -like "$k*") { return [double]$Ratio[$k] }
    }
    return 0.0
}

function Test-RtkKnows {
    param([string]$Cmd)
    $head = ($Cmd -split '\s+')[0]
    return ($RtkKnows -contains $head)
}

function Read-Calls {
    # povertaye zapysy: sesiya, den, komanda, symvoliv u vyvodi
    param([string]$Path)

    $rxUse  = '"id":"(toolu_[^"]+)","name":"Bash","input":\{"command":"((?:[^"\\]|\\.)*)"'
    $rxRes  = '"tool_use_id":"(toolu_[^"]+)","type":"tool_result","content":"((?:[^"\\]|\\.)*)"'
    $rxDay  = '"timestamp":"(\d{4}-\d{2}-\d{2})'

    $out = New-Object System.Collections.ArrayList
    $files = Get-ChildItem $Path -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $pending = @{}
        foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
            if ($line -match $rxUse) {
                $id = $Matches[1]
                $cmd = [regex]::Replace($Matches[2], '\\"', '"')
                $cmd = [regex]::Replace($cmd, '\\n', ' ')
                $cmd = [regex]::Replace($cmd, '\\\\', '\')
                $day = if ($line -match $rxDay) { $Matches[1] } else { "" }
                $pending[$id] = @{ Cmd = $cmd; Day = $day }
                continue
            }
            if ($line -match $rxRes) {
                $id = $Matches[1]
                if (-not $pending.ContainsKey($id)) { continue }
                $len = Get-Payload $Matches[2]
                $p = $pending[$id]
                $pending.Remove($id)
                [void]$out.Add([PSCustomObject]@{
                    Session = $f.BaseName
                    Day     = $p.Day
                    Cmd     = $p.Cmd
                    Chars   = $len
                })
            }
        }
    }
    return $out
}

function Invoke-Report {
    param($Calls, [switch]$WithDetail)

    if (-not $Calls -or $Calls.Count -eq 0) { "Немає викликів Bash у транскриптах."; return $null }

    $rows = foreach ($c in $Calls) {
        $core  = Get-Core $c.Cmd
        $inner = Get-Inner $core
        $isSsh = ($core -like 'ssh *')
        # te, shcho RTK bachyt na PK: sam ryadok komandy. Dlia ssh tse "ssh", yakoho vin ne znaye.
        $seen  = $core
        $known = Test-RtkKnows $seen
        $save  = if ($known) { [math]::Round($c.Chars * (Get-Ratio $seen)) } else { 0 }
        # hipotetychno: yakby hook perepysuvav komandu VSEREDYNI lapok ssh
        $hSave = if ($isSsh -and $inner -and (Test-RtkKnows $inner)) {
            [math]::Round($c.Chars * (Get-Ratio $inner))
        } else { $save }

        [PSCustomObject]@{
            Session = $c.Session; Day = $c.Day; Chars = $c.Chars
            Head    = ($seen -split '\s+')[0]
            IsSsh   = $isSsh
            Save    = $save
            HypSave = $hSave
        }
    }

    $n        = $rows.Count
    $sessions = ($rows | Select-Object -ExpandProperty Session -Unique).Count
    $chars    = ($rows | Measure-Object Chars -Sum).Sum
    $save     = ($rows | Measure-Object Save -Sum).Sum
    $hyp      = ($rows | Measure-Object HypSave -Sum).Sum
    $ssh      = ($rows | Where-Object IsSsh).Count
    $sshChars = ($rows | Where-Object IsSsh | Measure-Object Chars -Sum).Sum

    "ЗАМІР RTK - скільки довгих команд і що з них можна стиснути"
    "  сесій:            {0:N0}" -f $sessions
    "  викликів Bash:    {0:N0}   ({1:N1} на сесію)" -f $n, ($n / [Math]::Max($sessions,1))
    "  символів усього:  {0:N0}   (~{1:N0} токенів)" -f $chars, ($chars / 2.07)
    ""
    "  Скільки з них ДОВГІ (саме тут живе виграш):"
    foreach ($t in 2000, 5000, 10000, 20000) {
        $set = $rows | Where-Object { $_.Chars -gt $t }
        $cnt = ($set | Measure-Object).Count
        $sum = ($set | Measure-Object Chars -Sum).Sum
        "    > {0,6:N0} символів: {1,5:N0} викликів ({2,4:N1} на сесію), {3,10:N0} символів" -f `
            $t, $cnt, ($cnt / [Math]::Max($sessions,1)), $sum
    }
    ""
    "  Через ssh (RTK не має такої підкоманди - не бачить нічого):"
    "    {0:N0} викликів з {1:N0} ({2:N0}%), {3:N0} символів ({4:N0}% усього виводу)" -f `
        $ssh, $n, (100*$ssh/[Math]::Max($n,1)), $sshChars, (100*$sshChars/[Math]::Max($chars,1))
    ""
    "  ЕКОНОМІЯ, якщо ввімкнути автохук на ПК (ssh не переписуємо):"
    "    {0:N0} символів = ~{1:N0} токенів за весь період" -f $save, ($save/2.07)
    "    ~{0:N0} токенів на сесію   ({1:N2}% від виводу Bash)" -f `
        (($save/2.07) / [Math]::Max($sessions,1)), (100*$save/[Math]::Max($chars,1))
    ""
    "  Для порівняння - якби хук переписував команду ВСЕРЕДИНІ лапок ssh:"
    "    ~{0:N0} токенів на сесію" -f (($hyp/2.07) / [Math]::Max($sessions,1))

    if ($WithDetail) {
        ""
        "  Розклад по командах (топ-15 за обсягом виводу):"
        "    {0,-16} {1,8} {2,12} {3,5} {4,10}" -f "команда", "викликів", "символів", "RTK", "економія"
        $rows | Group-Object Head | ForEach-Object {
            [PSCustomObject]@{
                Name  = $_.Name
                Cnt   = $_.Count
                Sum   = ($_.Group | Measure-Object Chars -Sum).Sum
                Known = if (Test-RtkKnows $_.Name) { "так" } else { "-" }
                Save  = ($_.Group | Measure-Object Save -Sum).Sum
            }
        } | Sort-Object Sum -Descending | Select-Object -First 15 | ForEach-Object {
            $nm = if ($_.Name.Length -gt 16) { $_.Name.Substring(0,15) + "~" } else { $_.Name }
            "    {0,-16} {1,8:N0} {2,12:N0} {3,5} {4,10:N0}" -f $nm, $_.Cnt, $_.Sum, $_.Known, $_.Save
        }
    }

}

# --- Samoperevirka: zamir zobovyazanyi pobachyty y vyhrash, y slipu zonu ---
if ($SelfTest) {
    $tmp = Join-Path $env:TEMP "rtk-audit-selftest-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $big = "x" * 30000

    $lines = @(
        '{"timestamp":"2026-09-09T10:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_AAA","name":"Bash","input":{"command":"find /opt -name \u0027*.py\u0027","description":"t"}}]}}'.Replace('\u0027',"'")
        '{"timestamp":"2026-09-09T10:00:01Z","message":{"content":[{"tool_use_id":"toolu_AAA","type":"tool_result","content":"' + $big + '"}]}}'
        '{"timestamp":"2026-09-09T10:00:02Z","message":{"content":[{"type":"tool_use","id":"toolu_BBB","name":"Bash","input":{"command":"ssh root@1.2.3.4 \u0027find /opt -name *.py\u0027","description":"t"}}]}}'.Replace('\u0027',"'")
        '{"timestamp":"2026-09-09T10:00:03Z","message":{"content":[{"tool_use_id":"toolu_BBB","type":"tool_result","content":"' + $big + '"}]}}'
    )
    Set-Content -Path (Join-Path $tmp "selftest.jsonl") -Value $lines -Encoding UTF8

    $calls = Read-Calls $tmp
    $ok = $true
    "САМОПЕРЕВІРКА ЗАМІРУ"
    ""

    # 1. zamir vzahali bachyt vyklyky y yih rozmir
    if ($calls.Count -ne 2) { "  ПРОВАЛ: знайдено $($calls.Count) викликів замість 2"; $ok = $false }
    else { "  ок: обидва виклики знайдені" }

    $lens = ($calls | Measure-Object Chars -Sum).Sum
    if ($lens -lt 59000) { "  ПРОВАЛ: розмір виводу $lens, очікували ~60000"; $ok = $false }
    else { "  ок: розмір виводу порахований ($lens символів)" }

    # 2. bachyt vyhrash tam, de vin ye
    $localFind = $calls | Where-Object { $_.Cmd -like 'find *' }
    $expect = [math]::Round(30000 * 0.95)
    $got = [math]::Round($localFind.Chars * (Get-Ratio (Get-Core $localFind.Cmd)))
    if ($got -lt $expect * 0.9) { "  ПРОВАЛ: локальний find дав економію $got замість ~$expect"; $ok = $false }
    else { "  ок: бачить виграш на локальному find ($got символів)" }

    # 3. NE prypysuye vyhrash tam, de RTK slipyi (ssh)
    $sshCall = $calls | Where-Object { $_.Cmd -like 'ssh *' }
    $sshSeen = Get-Core $sshCall.Cmd
    if (Test-RtkKnows $sshSeen) { "  ПРОВАЛ: замір вважає, що RTK бачить ssh"; $ok = $false }
    else { "  ок: ssh порахований як сліпа зона (економія 0)" }

    Remove-Item $tmp -Recurse -Force
    ""
    if ($ok) { "ЗАМІР РОБОЧИЙ - бачить і виграш, і сліпу зону." }
    else { "ЗАМІР ЗЛАМАНИЙ - цифрам не вірити."; exit 1 }
    return
}

# --- Zvychainyi zvit ---
$calls = Read-Calls $Root
if ($From) { $calls = $calls | Where-Object { $_.Day -ge $From } }
Invoke-Report $calls -WithDetail:$Detail
