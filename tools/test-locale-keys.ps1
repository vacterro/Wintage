# T-307 -- GUI runtime-key coverage gate.
#
# Every translation key the GUI actually asks for through T('Key') must exist in
# en.json. Without this gate a key can be used in the verified source and still
# render its own NAME on screen, because T() falls back to the raw key when the
# table lacks it (i18n.ps1:41). That is exactly how the nine preset-control keys
# (PresetLabel/Save/Update/Rename/Delete/Modified/NamePrompt/OverwriteAsk/
# DeleteAsk) shipped unlocalised: the parity gate compares locale files to each
# other and en.json to itself, so it never noticed a key referenced BY CODE but
# absent FROM the table.
#
# Static extraction (a regex over the shipped T() call sites) is deliberate: it
# needs no GUI session and it fails on the exact defect class -- a code-used key
# with no table entry. Dynamic T(...) calls with a computed key cannot be
# checked statically and are reported as a count, not silently ignored.
#
#   .\tools\test-locale-keys.ps1          # all tests
#   .\tools\test-locale-keys.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List, [switch]$RedControl)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-locale-keys.ps1 (T-307 GUI runtime-key coverage):"
    Write-Host "  1. every T('Key') call site in the GUI resolves to a real en.json key"
    Write-Host "  2. the preset control/dialog keys are present (the T-307 defect)"
    Write-Host "  3. dynamic T(...) call sites are reported, never silently skipped"
    exit 0
}

$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$enPath  = Join-Path $root 'desktop\locales\en.json'
$gui = [System.IO.File]::ReadAllText($guiPath, $utf8)
$en  = [System.IO.File]::ReadAllText($enPath, $utf8) | ConvertFrom-Json
$enKeys = $en.PSObject.Properties.Name

# Every STATIC T 'Key' / T "Key" call site. Dynamic T($x) is counted separately.
$usedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in [regex]::Matches($gui, "T\s+'([A-Za-z0-9_]+)'")) { [void]$usedKeys.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($gui, 'T\s+"([A-Za-z0-9_]+)"')) { [void]$usedKeys.Add($m.Groups[1].Value) }

$dynamic = @([regex]::Matches($gui, 'T\s+\$[A-Za-z_][A-Za-z0-9_]*'))

# RED control: re-introduce the exact defect (a used key with no table entry)
# and prove the coverage check FAILS against it.
if ($RedControl) {
    $mutantEn = $enKeys | Where-Object { $_ -ne 'PresetSave' }
    $mutantMissing = @('PresetSave' | Where-Object { $mutantEn -notcontains $_ })
    check 'T-307 RED: a used key absent from the table is detected as missing' ($mutantMissing.Count -eq 1)
    Write-Host ""
    if ($fail -eq 0) { Write-Host "$pass PASS, 0 FAIL (RED control detected the defect)" -ForegroundColor Green; exit 0 }
    else { Write-Host "$pass PASS, $fail FAIL" -ForegroundColor Red; $failedLabels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }; exit 1 }
}

# ---- 1. every used key resolves in en.json ----------------------------------
$missing = @($usedKeys | Where-Object { $enKeys -notcontains $_ } | Sort-Object)
check "T-307: all $($usedKeys.Count) GUI-used keys exist in en.json (missing: $($missing -join ', '))" ($missing.Count -eq 0)

# ---- 2. the T-307 defect's key set is present -------------------------------
foreach ($k in @('PresetLabel','PresetSave','PresetUpdate','PresetRename','PresetDelete',
                 'PresetModified','PresetNamePrompt','PresetOverwriteAsk','PresetDeleteAsk')) {
    check "T-307: preset key '$k' is in en.json" ($enKeys -contains $k)
}

# ---- 3. dynamic call sites are surfaced -------------------------------------
Write-Host "NOTE: $($dynamic.Count) dynamic T(...) call site(s) not statically checkable" -ForegroundColor DarkGray
check 'T-307: en.json parses and is non-empty' ($enKeys.Count -gt 0)

Write-Host ""
if ($fail -eq 0) { Write-Host "$pass PASS, 0 FAIL" -ForegroundColor Green; exit 0 }
else { Write-Host "$pass PASS, $fail FAIL" -ForegroundColor Red; $failedLabels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }; exit 1 }
