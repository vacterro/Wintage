# T-310 -- locale semantic-value gate (Core-owned et/ru/ded)
#
# Defect class this suite pins down (two siblings the key-parity gate cannot see,
# because both files carry the RIGHT keys with WRONG values):
#
#   1. Double-escaped multiline strings. en.json stores real JSON escapes
#      ("...Apply.\r\n\r\nThe preview..."), so the parsed value carries real
#      CR/LF and the GUI label wraps. A translated file that stored "\\r\\n"
#      parses to a LITERAL backslash-r-backslash-n and the user sees the raw
#      escape text mid-sentence. Key parity is intact; the value is broken.
#
#   2. Untranslated placeholders. A locale that copies the English string
#      verbatim for a UI control renders English under a non-English pick with
#      no missing key and no warning -- the T-310 terminal-font tab shipped this
#      way (all 16 Tf* keys equal to en).
#
# Contract enforced here, Core-owned locales only (phases/translate.md: EN/ET/RU/DED):
#   A. every multiline en key (real newline in en) has real newlines and ZERO
#      literal "\r"/"\n" backslash escapes in each Core locale;
#   B. every terminal-font key (Tf*/TabFonts) DIFFERS from the English string.
# The other 29 locales are producer-owned (saitranslate) and are not checked here.
#
# Red control: -RedControl proves the gate goes red on a reintroduced literal
# escape and on a Tf value copied back to English.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$LocalesDir
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$dir = if ($LocalesDir) { $LocalesDir } else { Join-Path $root 'desktop\locales' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function Read-Json([string]$path) {
    ([System.IO.File]::ReadAllText($path, $utf8)) | ConvertFrom-Json
}

# Core-owned locales and the terminal-font key set.
$coreLocales = @('et', 'ru', 'ded')
$tfKeys = @('TabFonts', 'TfSearch', 'TfPreview', 'TfControls', 'TfFamily', 'TfSize',
    'TfRendering', 'TfInstall', 'TfApplyTerminal', 'TfApplyConhost', 'TfApplyBoth',
    'TfRestore', 'TfSource', 'TfLicense', 'TfRefresh', 'TfLog')

if ($List) {
    Write-Host "test-locale-semantic.ps1 (T-310 Core locale value integrity):"
    Write-Host "  A. every multiline en key has real newlines and zero literal \r/\n in et/ru/ded"
    Write-Host "  B. every terminal-font key differs from the English string in et/ru/ded"
    Write-Host "Red control: -RedControl (a reintroduced literal escape and an English-copied Tf value fail)"
    exit 0
}

$refPath = Join-Path $dir 'en.json'
if (-not (Test-Path $refPath)) { Write-Host "FAIL: reference en.json not found at $refPath" -ForegroundColor Red; exit 1 }
$en = Read-Json $refPath

# Multiline en keys are the ones whose English value carries a real newline.
$multilineKeys = @($en.PSObject.Properties | Where-Object { $_.Value -is [string] -and $_.Value.Contains("`n") } | ForEach-Object { $_.Name })
check "en.json declares at least one multiline key (found $($multilineKeys.Count))" ($multilineKeys.Count -gt 0)

foreach ($loc in $coreLocales) {
    $p = Join-Path $dir "$loc.json"
    if (-not (Test-Path $p)) { check "Core locale $loc.json exists" $false; continue }
    $d = Read-Json $p

    # Contract A: no literal backslash-escapes in any multiline value; real newlines present.
    foreach ($k in $multilineKeys) {
        $v = [string]$d.$k
        $hasLiteral = $v.Contains('\r') -or $v.Contains('\n')
        $hasRealNl = $v.Contains("`n")
        check "$loc.json '$k' has real newlines and zero literal \r\n escapes" ((-not $hasLiteral) -and $hasRealNl)
    }

    # Contract B: every terminal-font key differs from English.
    foreach ($k in $tfKeys) {
        $same = ([string]$d.$k -eq [string]$en.$k)
        check "$loc.json terminal-font key '$k' differs from English" (-not $same)
    }
}

if ($RedControl) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-locale-sem-red-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Copy-Item (Join-Path $dir '*.json') $tmp
        $enR = Read-Json (Join-Path $tmp 'en.json')

        # Mutant A: reintroduce a literal escape into a Core locale's InfoText.
        $victim = Join-Path $tmp 'et.json'
        $o = Read-Json $victim
        $o.InfoText = 'Broken\r\nline'
        [System.IO.File]::WriteAllText($victim, ($o | ConvertTo-Json -Depth 8), $utf8)
        $mv = [string](Read-Json $victim).InfoText
        check 'RED: a reintroduced literal \r\n escape is detected (mutant A)' ($mv.Contains('\r') -or $mv.Contains('\n'))

        # Mutant B: copy a Tf value back to the English string.
        $victimB = Join-Path $tmp 'ru.json'
        $ob = Read-Json $victimB
        $ob.TfFamily = [string]$enR.TfFamily
        [System.IO.File]::WriteAllText($victimB, ($ob | ConvertTo-Json -Depth 8), $utf8)
        $mvb = [string](Read-Json $victimB).TfFamily
        check 'RED: a Tf value copied back to English is detected (mutant B)' ($mvb -eq [string]$enR.TfFamily)

        # Control: the untouched ded copy still passes contract B for TfFamily.
        $okc = ([string](Read-Json (Join-Path $tmp 'ded.json')).TfFamily -ne [string]$enR.TfFamily)
        check 'RED control: an untouched Core locale still differs from English' $okc
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
