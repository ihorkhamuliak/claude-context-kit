#!/usr/bin/env pwsh
# read-guard-hook.ps1 - ne daye chytaty duzhe velykyi fayl tsilkom
#
# CHOMU: zamir po transkryptah za 20-24.08 pokazav, shcho Read - tse 56% usioho,
# shcho potraplyaye v kontekst vid instrumentiv. Serednii vyklyk - 41 575 symvoliv
# (~20 000 tokeniv). Bash pry 920 vyklykah daye lyshe 2 736 symvoliv na vyklyk.
# Otzhe holovnyi vazhil - ne stysnennia komand, a chytannia faylivv tsilkom.
#
# SHCHO ROBYT: yakshcho fayl bilshyi za porih I nemaye offset/limit - vidmovlyaye
# i kazhe, yak vziaty potribne. Ne blokuye nichoho inshoho.
#
# VYMYKACH: fayl ".claude\read-guard-off" u vaulti.
# FAIL-SAFE: bud-yakyi zbiy = dozvil. Guard nikoly ne lamaye robotu.
#
# UVAHA: UTF-8 z BOM. Identyfikatory - latynytseiu.

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Vault    = $(if ($env:CLAUDE_VAULT) { $env:CLAUDE_VAULT } else { "$HOME\Vault" })
$OffFlag  = Join-Path $Vault ".claude\read-guard-off"
$LimitKB  = 100     # nyzhche tsioho porohu - chytay yak zavzhdy

function Allow { '{"hookSpecificOutput":{"hookEventName":"PreToolUse"}}'; exit 0 }

try {
    if (Test-Path $OffFlag) { Allow }

    # stdin prykhodyt po-riznomu: cherez konveyer PowerShell tse $input,
    # cherez `powershell -File` z realnym stdin - tse [Console]::In.
    # Chytayemo obydva, inakshe khuk movchky propuskaye vse (bulo 24.08).
    $raw = @($input) -join "`n"
    if (-not $raw) { try { $raw = [Console]::In.ReadToEnd() } catch { } }
    if (-not $raw) { Allow }
    $j = $raw | ConvertFrom-Json

    if ($j.tool_name -ne "Read") { Allow }

    $ti = $j.tool_input
    # shmatok vzhe zaproshenyi - propuskayemo
    if ($ti.offset -or $ti.limit) { Allow }

    $path = $ti.file_path
    if (-not $path -or -not (Test-Path $path)) { Allow }

    $item = Get-Item $path
    $kb = [math]::Round($item.Length / 1KB, 1)
    if ($kb -le $LimitKB) { Allow }

    # tilky tekstovi - kartynky i PDF chytayutsia inakshe
    if ($item.Extension -notin @(".md",".txt",".json",".csv",".log",".ps1",".py",".js",".ts",".sh",".yml",".yaml")) { Allow }

    $lines = 0
    try { $lines = (Get-Content $path -ReadCount 0 -Encoding UTF8).Count } catch { $lines = 0 }
    $tok = [math]::Round($item.Length / 2.07 / 1000)

    $reason = @"
Файл $kb КБ (~${tok}k токенів, $lines рядків) — забагато, щоб брати цілком.
Це 56% усіх витрат контексту йде саме на такі читання.

Візьми потрібне:
  Grep по темі (найдешевше)
  Read -offset <рядок> -limit 200  — номери рядків є в карті брифу
  Read -limit 200 — якщо треба початок

Треба справді весь файл — читай шматками по 500 рядків.
Вимкнути перевірку назовсім: створи файл .claude\read-guard-off у vault.
"@

    $out = @{
        hookSpecificOutput = @{
            hookEventName            = "PreToolUse"
            permissionDecision       = "deny"
            permissionDecisionReason = $reason
        }
    }
    $out | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
catch { Allow }
