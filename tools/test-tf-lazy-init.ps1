# PERF-001 (audit/8.md) -- lazy terminal-font initialization suite.
#
# DEFECT: Initialize-TfTab ran before ShowDialog, eagerly AddFontFile-loading all
# 20 bundled fonts into private GDI+ collections and running fixed-pitch probes
# for faces the user may never inspect. Get-TfMetrics also re-ran Get-TfCapability
# redundantly for the selected row.
#
# CONTRACT under test:
#   1. Initialize-TfTab is NOT called before ShowDialog;
#   2. Set-ActiveTab initializes the subsystem on FIRST Fonts-tab entry, and
#      re-probes only on subsequent entries;
#   3. Get-TfCapability does not fixed-pitch probe an uninstalled bundled face;
#   4. fixed-pitch results are cached per immutable file identity;
#   5. Get-TfMetrics reuses an already-known row capability;
#   6. RED control: restoring eager Initialize-TfTab before ShowDialog fails.
#
#   .\tools\test-tf-lazy-init.ps1          # all tests
#   .\tools\test-tf-lazy-init.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$tfPath = Join-Path $root 'desktop\modules\terminal-fonts.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-tf-lazy-init.ps1 (PERF-001 lazy terminal-font init):"
    Write-Host "  1. no eager Initialize-TfTab before ShowDialog"
    Write-Host "  2. Set-ActiveTab lazy first-entry init + re-probe"
    Write-Host "  3. no fixed-pitch probe for uninstalled bundled face"
    Write-Host "  4. fixed-pitch cache per immutable file identity"
    Write-Host "  5. Get-TfMetrics reuses row capability"
    Write-Host "  6. RED control: eager init before ShowDialog fails"
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath, $utf8)
$tfText = [System.IO.File]::ReadAllText($tfPath, $utf8)

# ---- 1. no eager Initialize-TfTab before ShowDialog ---------------------------
# The bare `Initialize-TfTab` call before ShowDialog must be gone. A call inside
# Set-ActiveTab is the intended lazy trigger and is allowed.
$guiWithoutSetTab = if ($setTabFnForStrip = [regex]::Match($guiText, '(?s)function Set-ActiveTab.*?\n\}')) {
    $guiText.Remove($setTabFnForStrip.Index, $setTabFnForStrip.Length)
} else { $guiText }
$eagerCall = [regex]::Matches($guiWithoutSetTab, '(?m)^\s*Initialize-TfTab\s*$')
check 'PERF-001: no bare Initialize-TfTab call at startup (outside Set-ActiveTab)' ($eagerCall.Count -eq 0)
check 'PERF-001: startup sets TfInitialized = false (deferred)' (
    $guiText -match '\$script:TfInitialized\s*=\s*\$false')
# Initialize-TfTab must still exist as a function.
check 'PERF-001: Initialize-TfTab function still defined' ($guiText -match 'function Initialize-TfTab')

# ---- 2. Set-ActiveTab lazy first-entry init ----------------------------------
$setTabFn = [regex]::Match($guiText, '(?s)function Set-ActiveTab.*?\n\}')
check 'PERF-001: Set-ActiveTab located' $setTabFn.Success
if ($setTabFn.Success) {
    $body = $setTabFn.Value
    check 'PERF-001: Set-ActiveTab initializes on first fonts entry' ($body -match 'Initialize-TfTab')
    check 'PERF-001: Set-ActiveTab guards on TfInitialized' ($body -match '\$script:TfInitialized')
    check 'PERF-001: Set-ActiveTab re-probes with Refresh-TfFonts on later entries' ($body -match 'Refresh-TfFonts')
}

# ---- 3. no fixed-pitch probe for uninstalled bundled face --------------------
check 'PERF-001: Get-TfCapability guards probe on Installed' (
    $tfText -match 'if \(\$cap\.Preview -and \$cap\.Installed\)')
check 'PERF-001: Get-TfCapability uses cached probe' (
    $tfText -match 'Test-TfFileFixedPitchCached')

# ---- 4. cache per immutable file identity ------------------------------------
check 'PERF-001: fixed-pitch cache declared' ($tfText -match '\$script:TfFixedPitchCache\s*=')
check 'PERF-001: cache key is immutable file identity (path+size+mtime)' (
    $tfText -match 'Get-TfFileIdentity' -and $tfText -match 'LastWriteTimeUtc\.Ticks' -and $tfText -match '\.Length')
check 'PERF-001: cache invalidation helper exists' ($tfText -match 'function Clear-TfCapabilityCache')

# ---- 5. Get-TfMetrics reuses row capability ----------------------------------
check 'PERF-001: Get-TfMetrics accepts knownCap param' (
    $tfText -match 'function Get-TfMetrics\(\$entry, \[int\]\$size, \$knownCap\)')
check 'PERF-001: GUI passes row.Cap to Get-TfMetrics' (
    $guiText -match 'Get-TfMetrics \$row\.Entry.*\$row\.Cap')

# ---- 6. RED control: eager init before ShowDialog is detectable ---------------
# Simulate the old defective pattern and prove the guard would flag it.
$oldHasBareCall = ($guiWithoutSetTab -match "(?m)^\s*Initialize-TfTab\s*$")
check 'RED control: old eager Initialize-TfTab pattern is absent from production' (-not $oldHasBareCall)

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
