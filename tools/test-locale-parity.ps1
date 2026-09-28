# T-250 / HUNT-001 -- locale key parity
#
# Defect class this suite pins down:
# The GUI's T() loader (desktop/i18n.ps1) overlays the selected locale on the
# English base and silently falls back to the English string for any key the
# locale lacks. A locale that lags en.json therefore renders English text with
# no crash and no warning -- invisible at runtime and easy to reintroduce.
#
# The contract is that every locale file carries the SAME key SET as en.json,
# missing none and adding none. Order is cosmetic: these files are hand-edited
# and not sorted, so only the set is compared.
#
# Red control: run with -RedControl to prove the gate goes red when a locale
# loses a key the base still has (and when it invents a key the base lacks).

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

function Get-KeySet([string]$path) {
    $obj = ([System.IO.File]::ReadAllText($path, $utf8)) | ConvertFrom-Json
    @($obj.PSObject.Properties.Name | Sort-Object)
}

if ($List) {
    Write-Host "test-locale-parity.ps1 (T-250 locale key parity):"
    Write-Host "  1. every locale parses as JSON"
    Write-Host "  2. en.json is the reference and holds the full key set"
    Write-Host "  3. every locale carries the exact same key set as en.json (no missing, no extra)"
    Write-Host "  4. all 33 expected locale files are present"
    Write-Host "Red control: -RedControl (a locale missing a base key, and a locale with an extra key, both fail)"
    exit 0
}

$expectedCount = 33
$refPath = Join-Path $dir 'en.json'
if (-not (Test-Path $refPath)) { Write-Host "FAIL: reference en.json not found at $refPath" -ForegroundColor Red; exit 1 }

$refKeys = Get-KeySet $refPath
check 'en.json parses and is non-empty' ($refKeys.Count -gt 0)

$localeFiles = @(Get-ChildItem $dir -Filter '*.json' | Sort-Object Name)
check "all $expectedCount expected locale files are present (found $($localeFiles.Count))" ($localeFiles.Count -eq $expectedCount)

foreach ($lf in $localeFiles) {
    $keys = $null
    $parsed = $true
    try { $keys = Get-KeySet $lf.FullName } catch { $parsed = $false }
    check "$($lf.Name) parses as JSON" $parsed
    if (-not $parsed) { continue }
    $missing = @($refKeys | Where-Object { $keys -notcontains $_ })
    $extra = @($keys | Where-Object { $refKeys -notcontains $_ })
    check "$($lf.Name) key set matches en.json (missing: $($missing -join ',') | extra: $($extra -join ','))" `
        (($missing.Count -eq 0) -and ($extra.Count -eq 0))
}

if ($RedControl) {
    # Prove the gate can fail. Work on a private copy; never touch the real tree.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-locale-redcontrol-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Copy-Item (Join-Path $dir '*.json') $tmp
        $refKeys2 = Get-KeySet (Join-Path $tmp 'en.json')

        # Mutant A: a locale loses a key en still has.
        $victim = Join-Path $tmp 'de.json'
        $obj = ([System.IO.File]::ReadAllText($victim, $utf8)) | ConvertFrom-Json
        $mutA = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) { if ($p.Name -ne 'LanguageLabel') { $mutA[$p.Name] = $p.Value } }
        [System.IO.File]::WriteAllText($victim, ($mutA | ConvertTo-Json -Depth 8), $utf8)
        $keysA = Get-KeySet $victim
        $missingA = @($refKeys2 | Where-Object { $keysA -notcontains $_ })
        check 'RED: a locale missing a base key is detected (mutant A)' ($missingA.Count -ge 1)

        # Mutant B: a locale invents a key en does not have.
        $victimB = Join-Path $tmp 'fr.json'
        $objB = ([System.IO.File]::ReadAllText($victimB, $utf8)) | ConvertFrom-Json
        $mutB = [ordered]@{}
        foreach ($p in $objB.PSObject.Properties) { $mutB[$p.Name] = $p.Value }
        $mutB['BogusKeyNotInEn'] = 'x'
        [System.IO.File]::WriteAllText($victimB, ($mutB | ConvertTo-Json -Depth 8), $utf8)
        $keysB = Get-KeySet $victimB
        $extraB = @($keysB | Where-Object { $refKeys2 -notcontains $_ })
        check 'RED: a locale inventing a key en lacks is detected (mutant B)' ($extraB.Count -ge 1)

        # Control: an untouched locale copy is clean under the same comparison.
        $keysC = Get-KeySet (Join-Path $tmp 'en.json')
        $clean = (($refKeys2 | Where-Object { $keysC -notcontains $_ }).Count -eq 0)
        check 'RED control: the unmutated reference copy passes the same comparison' $clean
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
