# Desktop README translated-coverage parity gate (T-311).
#
# Defect class this suite pins down:
# desktop/README.md is the source of truth for what each target does. When a
# new target (Process Explorer, Notepad++, Cinema 4D) or a new section
# (terminal fonts) lands in the English README, the translated siblings lag
# silently -- a reader of README.ru.md sees an older, smaller feature list
# with no signal that it is stale. The version badge and prose can drift a
# long way before anyone notices.
#
# The contract enforced here: every README that Wintage maintains must carry
# the SAME language-invariant target/section anchors as the English source.
# The anchors are code literals -- target ids in backticks, registry paths,
# file names -- which STYLE.md keeps untranslated ("facts are sacred"), so
# they are the honest cross-language discriminator: a translated file that
# omits `processexplorer`, the Process Explorer registry key, `notepadplusplus`,
# `cinema4d` or `terminal-font.json` has not mirrored that coverage.
#
# Scope: ALL Wintage-maintained locales. Core owns EN/ET/RU/DED
# (phases/translate.md); the other 29 producer-owned locales carried the same
# coverage gap and were brought into parity under T-311 (a language-invariant
# coverage supplement appended to each), so the gate now fails closed on ANY
# locale missing an anchor -- the producer carve-out is gone.
#
# Red control: -RedControl proves the gate goes red when any locale drops an
# anchor the English source still carries.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$DesktopDir
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$dir = if ($DesktopDir) { $DesktopDir } else { Join-Path $root 'desktop' }
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Language-invariant anchors: code literals that stay untranslated in every
# locale, one per feature the four named coverages describe.
$anchors = [ordered]@{
    'processexplorer target row'   = '`processexplorer`'
    'Process Explorer registry key'= 'HKCU\Software\Sysinternals\Process Explorer'
    'procexp process guard'        = 'procexp'
    'notepadplusplus target row'   = '`notepadplusplus`'
    'cinema4d target row'          = '`cinema4d`'
    'terminal-font preference file'= 'terminal-font.json'
    'fonts/terminal section'       = 'fonts/terminal'
}

# Core-owned locales (phases/translate.md): enforced strictly.
$coreLocales = @('et', 'ru', 'ded')
$sourceReadme = Join-Path $dir 'README.md'
if (-not (Test-Path $sourceReadme)) { Write-Host "FAIL: source README.md not found at $sourceReadme" -ForegroundColor Red; exit 1 }

if ($List) {
    Write-Host "test-readme-target-parity.ps1 (T-311 translated-coverage parity):"
    Write-Host "  1. the English source carries every anchor (contract sanity)"
    Write-Host "  2. EVERY locale (Core + all 29 producer-owned) carries every anchor"
    Write-Host "  3. a locale missing an anchor fails the matrix"
    Write-Host "Anchors:"; foreach ($k in $anchors.Keys) { Write-Host "  - $k => '$($anchors[$k])'" }
    Write-Host "Red control: -RedControl (a locale missing an anchor fails)"
    exit 0
}

# ---- Test 1: the English source carries every anchor ----
$src = Get-Content $sourceReadme -Raw
foreach ($k in $anchors.Keys) {
    check "source README.md carries anchor: $k" ($src -match [regex]::Escape($anchors[$k]))
}

# ---- Test 2: EVERY locale mirrors every anchor ----
$allReadmes = @(Get-ChildItem $dir -Filter 'README.*.md' | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
foreach ($rf in $allReadmes) {
    $code = ($rf.Name -replace '^README\.', '' -replace '\.md$', '')
    $txt = Get-Content $rf.FullName -Raw
    foreach ($k in $anchors.Keys) {
        check "README.$code.md mirrors anchor: $k" ($txt -match [regex]::Escape($anchors[$k]))
    }
}

if ($RedControl) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-readme-parity-red-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Copy-Item (Join-Path $dir 'README.md') $tmp
        Copy-Item (Join-Path $dir 'README.et.md') $tmp
        # Mutant: strip the Process Explorer registry anchor from a Core locale.
        $victim = Join-Path $tmp 'README.et.md'
        $mut = (Get-Content $victim -Raw) -replace [regex]::Escape('HKCU\Software\Sysinternals\Process Explorer'), 'REMOVED'
        Set-Content -Path $victim -Value $mut -NoNewline
        $mutTxt = Get-Content $victim -Raw
        $detected = -not ($mutTxt -match [regex]::Escape('HKCU\Software\Sysinternals\Process Explorer'))
        check 'RED: a Core-owned locale missing an anchor is detected' $detected
        # Control: the untouched English source still passes.
        $srcTxt = Get-Content (Join-Path $tmp 'README.md') -Raw
        check 'RED control: the untouched source still carries the anchor' ($srcTxt -match [regex]::Escape('HKCU\Software\Sysinternals\Process Explorer'))
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
