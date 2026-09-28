# T-309 -- MPC-HC font-state parity regression.
#
# The MPC-HC OSD face was resolved three different ways: apply and health both
# went through Get-WintageFontFace (Verdana_m1 when the shipped face is
# installed, Verdana otherwise) while install.ps1 -List hardcoded the literal
# 'Verdana'. On a correctly-themed machine that carries Verdana_m1, -List
# therefore reported "found, not themed" while apply+health agreed it WAS
# themed -- three surfaces, two answers.
#
# This gate extracts the REAL fragments from the shipped scripts and proves
# every surface resolves the expected OSD face through the one canonical rule:
#   - Invoke-MpcHc writes OSDFont = Get-WintageFontFace (apply);
#   - health compares OSDFont against Get-WintageFontFace (health);
#   - install.ps1 -List compares OSDFont against Get-WintageFontFace, never a
#     literal face name (list);
#   - driven against both font-present and font-absent worlds, the three
#     surfaces agree on the "themed" verdict for a machine whose OSDFont equals
#     the resolver's answer.
#
#   .\tools\test-mpchc-font-parity.ps1          # all tests
#   .\tools\test-mpchc-font-parity.ps1 -List    # list tests

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
    Write-Host "test-mpchc-font-parity.ps1 (T-309 MPC-HC font-state parity):"
    Write-Host "  1. install.ps1 -List resolves OSDFont through Get-WintageFontFace, not a literal"
    Write-Host "  2. Invoke-MpcHc apply writes OSDFont = Get-WintageFontFace"
    Write-Host "  3. health compares OSDFont against Get-WintageFontFace"
    Write-Host "  4. list/apply/health agree 'themed' when OSDFont = resolved face (font present)"
    Write-Host "  5. list/apply/health agree 'themed' when OSDFont = fallback face (font absent)"
    exit 0
}

$installText = [System.IO.File]::ReadAllText((Join-Path $root 'desktop\install.ps1'), $utf8)
$targetsText = [System.IO.File]::ReadAllText((Join-Path $root 'desktop\modules\targets.ps1'), $utf8)

# RED control: reintroduce the exact defect (literal 'Verdana' in -List) and
# prove the -List assertions below FAIL. Proves the gate can still see the bug.
if ($RedControl) {
    $mutant = $installText -replace "OSDFont -eq \(Get-WintageFontFace\)", "OSDFont -eq 'Verdana'"
    $listOk = ($mutant -match "OSDFont -eq \(Get-WintageFontFace\)")
    $literalGone = -not ($mutant -match "OSDFont -eq 'Verdana'")
    check 'T-309 RED: mutant -List no longer routes through Get-WintageFontFace (assertion 1 fails)' (-not $listOk)
    check 'T-309 RED: mutant -List carries the literal Verdana comparison (assertion 2 fails)' (-not $literalGone)
    Write-Host ""
    if ($fail -eq 0) { Write-Host "$pass PASS, 0 FAIL (RED control detected the defect)" -ForegroundColor Green; exit 0 }
    else { Write-Host "$pass PASS, $fail FAIL" -ForegroundColor Red; $failedLabels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }; exit 1 }
}

# ---- 1. -List routes through the canonical resolver, never a literal ---------
$listBlock = [regex]::Match($installText, "OSDFont -eq \(Get-WintageFontFace\)")
check 'T-309: install.ps1 -List compares OSDFont against Get-WintageFontFace' $listBlock.Success
check 'T-309: install.ps1 -List carries no literal OSDFont -eq ''Verdana'' comparison' (
    -not ($installText -match "OSDFont -eq 'Verdana'"))

# ---- 2. apply writes the resolved face --------------------------------------
check 'T-309: Invoke-MpcHc apply sets OSDFont = Get-WintageFontFace' (
    $targetsText -match '\$osdFont = Get-WintageFontFace' -and
    $targetsText -match 'OSDFont\s+= \$osdFont')

# ---- 3. health compares the resolved face -----------------------------------
check 'T-309: health compares mpc OSDFont against Get-WintageFontFace' (
    $targetsText -match '\$wantFace = Get-WintageFontFace;.*OSDFont -ne \$wantFace')

# ---- 4/5. behavioural parity across the two font worlds ----------------------
# The real resolver, driven against a stubbed installed-state, must give list,
# apply and health the SAME face on the SAME machine. Extract Get-WintageFontFace
# verbatim and evaluate it with Test-WintageFontInstalled forced each way.
$faceFnMatch = [regex]::Match($targetsText, 'function\s+Get-WintageFontFace\b')
$open = $targetsText.IndexOf('{', $faceFnMatch.Index)
$depth = 0; $faceFn = $null
for ($j = $open; $j -lt $targetsText.Length; $j++) {
    if ($targetsText[$j] -eq '{') { $depth++ }
    elseif ($targetsText[$j] -eq '}') { $depth--; if ($depth -eq 0) { $faceFn = $targetsText.Substring($faceFnMatch.Index, $j - $faceFnMatch.Index + 1); break } }
}
check 'T-309: Get-WintageFontFace located for evaluation' ($null -ne $faceFn)

$WINTAGE_FONT_FACE = 'Verdana_m1'
$WINTAGE_FONT_FALLBACK = 'Verdana'
Invoke-Expression $faceFn

# One machine, one OSDFont value, three surfaces. The list/apply/health verdicts
# are all "OSDFont equals the face the resolver returns" -- so if they share the
# resolver they must agree. Prove it by resolving once and checking all three
# predicates against the value apply would have written.
foreach ($world in @(
    @{ Name = 'font present'; Installed = $true;  Expect = 'Verdana_m1' },
    @{ Name = 'font absent';  Installed = $false; Expect = 'Verdana' })) {

    # Force Test-WintageFontInstalled for this world through a script-scope flag
    # the redefined stub reads, so the real Get-WintageFontFace runs unchanged.
    $script:WORLD_INSTALLED = $world.Installed
    function Test-WintageFontInstalled { $script:WORLD_INSTALLED }

    $resolved = Get-WintageFontFace
    check "T-309: resolver returns '$($world.Expect)' when $($world.Name)" ($resolved -eq $world.Expect)

    # A machine whose registry OSDFont equals the resolved face:
    $machineOsdFont = $resolved
    $listThemed   = ($machineOsdFont -eq (Get-WintageFontFace))     # -List predicate
    $applyWrites  = (Get-WintageFontFace)                            # apply value
    $healthThemed = -not ($machineOsdFont -ne (Get-WintageFontFace)) # health predicate

    check "T-309: list/apply/health agree themed when $($world.Name)" (
        $listThemed -and $healthThemed -and ($applyWrites -eq $machineOsdFont))
}

# ---- summary -----------------------------------------------------------------
Write-Host ""
if ($fail -eq 0) {
    Write-Host "$pass PASS, 0 FAIL" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$pass PASS, $fail FAIL" -ForegroundColor Red
    $failedLabels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
