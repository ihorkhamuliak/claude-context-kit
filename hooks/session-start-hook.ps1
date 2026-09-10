#!/usr/bin/env pwsh
# session-start-hook.ps1 - viddaye bryf u kontekst sesii
#
# VYMYKACH: stvory fayl ".claude\brief-off" u vaulti - khuk vidrazu movchyt.
#   New-Item "<vault>\.claude\brief-off" -ItemType File
# Vydalyty fayl - khuk znovu pratsiuye. Restart sesii ne potriben.
#
# FAIL-SAFE: bud-yakyi zbiy = porozhniy vyvid, sesiya startuye yak zavzhdy.
# Krashche bez bryfu, nizh zlamanyi start.
#
# UVAHA: UTF-8 z BOM. Identyfikatory - latynytseiu.

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Vault  = $(if ($env:CLAUDE_VAULT) { $env:CLAUDE_VAULT } else { "$HOME\Vault" })
$Brief  = "$PSScriptRoot\..\scripts\brief.ps1"
$OffFlag = Join-Path $Vault ".claude\brief-off"

function Write-Empty {
    '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
    exit 0
}

try {
    if (Test-Path $OffFlag) { Write-Empty }
    if (-not (Test-Path $Brief)) { Write-Empty }

    # stderr bryfera - tse yoho statystyka, u kontekst ne yde
    $text = & $Brief 2>$null | Out-String

    if ([string]::IsNullOrWhiteSpace($text)) { Write-Empty }

    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = "SessionStart"
            additionalContext = $text
        }
    }
    $payload | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
catch {
    # nikoly ne lamayemo start sesii cherez bryf
    Write-Empty
}
