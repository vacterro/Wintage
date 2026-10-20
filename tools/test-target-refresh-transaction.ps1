# T-967: transactional target refresh + stale-inventory safety.
#
# The legacy Load-Targets cleared both visible target lists BEFORE asking the
# listing child for a result, so a failed discovery left the window with no
# target rows at all and every selectability lookup answered "not found on this
# machine" for targets that are installed and themed. That is not cosmetic:
# Get-TargetSelectability answering 'not found' on a stale table is what lets
# Apply mutate a target the machine cannot vouch for.
#
# This gate drives the REAL transaction functions from
# desktop/WintageInstaller.ps1 against REAL WinForms CheckedListBoxes and the
# production listing seam ($script:TargetListingRunner), so every failure path
# is exercised with a listing that genuinely fails, without ever breaking a real
# install.ps1.
#
# It proves the transaction's LOGIC, not a live Windows GUI session.

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$root = Split-Path $PSScriptRoot -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$pass = 0
$fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}
if ($List) {
    Write-Host 'test-target-refresh-transaction.ps1 (transactional target refresh)'
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath)

# Extract one top-level function definition from the shipped source, so the gate
# never carries a second copy of the logic it is judging.
function Get-GuiFunctionText([string]$text, [string]$name) {
    # The parameter block between the name and the brace is optional because the
    # shipped functions are a mix of `function X {` and `function X($a) {`.
    $m = [regex]::Match($text, 'function\s+' + [regex]::Escape($name) + '\s*(\([^)]*\))?\s*\{')
    if (-not $m.Success) { return $null }
    $bodyStart = $m.Index + $m.Length          # first byte AFTER the opening brace
    $depth = 1
    $i = $bodyStart
    while ($i -lt $text.Length -and $depth -gt 0) {
        $ch = $text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth-- }
        if ($depth -eq 0) { return $text.Substring($m.Index, ($i - $m.Index + 1)) }
        $i++
    }
    return $null
}

$wanted = @('Get-TargetRowSnapshot', 'Restore-TargetRows', 'ConvertTo-TargetRecord',
    'Test-TargetSelectableByState', 'Get-TargetListing', 'Load-Targets')
$extracted = @{}
foreach ($n in $wanted) {
    $extracted[$n] = Get-GuiFunctionText $guiText $n
    check "the real $n was located in WintageInstaller.ps1" ($null -ne $extracted[$n])
}
if ($script:fail) {
    Write-Host ''
    Write-Host ("test-target-refresh-transaction.ps1: $pass PASS / $fail FAIL (extraction failed; no behavioural verdict claimed)") -ForegroundColor Red
    exit 1
}

# --- harness chrome (same discipline as test-presets.ps1) ---------------------
$script:customPaths = @{}
$PATH_TARGETS = @('zcode', 'cinema4d')
$MY_APP_KEYS = @('windows', 'terminal', 'obs', 'notepadplusplus')
$clbMyApps = New-Object Windows.Forms.CheckedListBox
$clbMyApps.Name = 'clbMyApps'
$clbPopularApps = New-Object Windows.Forms.CheckedListBox
$clbPopularApps.Name = 'clbPopularApps'
$TARGET_LISTS = @($clbMyApps, $clbPopularApps)
$script:logLines = @()
function Say-Log($m) { $script:logLines += $m }
$status = New-Object Windows.Forms.Label
$btnRefreshTargets = New-Object Windows.Forms.Button
$here = $root

Invoke-Expression (($wanted | ForEach-Object { $extracted[$_] }) -join "`n")

# The listing the fixture supplies to the production seam. Get-TargetListing reads
# the child's output stream and $LASTEXITCODE, so the seam must supply BOTH in the
# same shape the real child does. A raw array is NOT enough: PowerShell pipes the
# scriptblock's own output AND the child's output together, so returning the lines
# directly makes every row arrive twice (verified: the duplicated-row bug this
# gate caught during development). The seam therefore writes the lines to a
# throwaway file and then emits them, so the observed stream is exactly what a
# powershell child produces.
$script:listingLines = @()
$script:listingExit = 0
$script:TargetListingRunner = { param()
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllLines($tmp, $script:listingLines)
        & powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '$tmp'; exit $($script:listingExit)"
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function New-ListingLines([object[]]$rows) {
    $lines = @('')
    $lines += '  target            app                                     state                   palette'
    foreach ($r in $rows) { $lines += ('  {0,-16} {1,-38} {2,-22} {3}' -f $r.Key, $r.Name, $r.State, $r.Palette) }
    # T-970: the completion witness the real install.ps1 prints as its last
    # machine-readable line. A listing WITHOUT it is not a complete inventory, so
    # the fixture supplies both shapes and the gate judges the difference.
    $lines += ("# wintage-listing-complete rows=$($rows.Count)")
    return $lines
}
# A listing that stops early: real rows, no completion witness. This is what a
# truncated pipe or a child killed before its tail actually looks like on the wire,
# and it is the shape the pre-T-970 predicate published as a fresh full inventory.
function New-TruncatedListingLines([object[]]$rows) {
    $lines = @('')
    $lines += '  target            app                                     state                   palette'
    foreach ($r in $rows) { $lines += ('  {0,-16} {1,-38} {2,-22} {3}' -f $r.Key, $r.Name, $r.State, $r.Palette) }
    return $lines
}
function New-Row([string]$k, [string]$s) {
    [pscustomobject]@{ Key = $k; Name = "Test $k"; State = $s; Palette = '-' }
}
function Set-Listing([object[]]$rows, [int]$code = 0) { $script:listingLines = New-ListingLines $rows; $script:listingExit = $code }
function Set-TruncatedListing([object[]]$rows, [int]$code = 0) { $script:listingLines = New-TruncatedListingLines $rows; $script:listingExit = $code }
# A listing that CLAIMS a completion count it did not emit -- a malformed or
# partially-consumed stream where the reader can see the rows but not all of them.
function Set-ListingWithDeclared([object[]]$rows, [int]$declared, [int]$code = 0) {
    $script:listingLines = @(New-TruncatedListingLines $rows) + ("# wintage-listing-complete rows=$declared")
    $script:listingExit = $code
}

# --- 1..2: a failed FIRST discovery names itself ------------------------------
Set-Listing @() 1
$ok = Load-Targets
check 'a failing first discovery returns false (nothing published as authoritative)' ($ok -eq $false)
check 'a failing first discovery shows an explicit unavailable row, not an empty list' (
    $clbMyApps.Items.Count -ge 1 -and "$($clbMyApps.Items[0])" -match 'unavailable')
check 'a failing first discovery leaves the inventory NOT fresh' ($script:targetsFresh -eq $false)
check 'a failing first discovery states a reason' ($script:targetsRefreshReason.Length -gt 0)

# --- 3: a successful listing replaces the rows --------------------------------
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'zcode' 'listing failed'))
$ok = Load-Targets
check 'a successful listing returns true' ($ok -eq $true)
check 'a successful listing marks the inventory fresh' ($script:targetsFresh -eq $true)
check 'a successful listing populates both visible lists' ($clbMyApps.Items.Count -eq 2 -and $clbPopularApps.Items.Count -eq 1)
check 'a successful listing ticks a selectable target' ($clbMyApps.GetItemChecked(0))
check 'a successful listing does NOT tick a listing-failed target' (-not $clbPopularApps.GetItemChecked(0))
check 'the unavailable placeholder is gone after a success' (-not ($clbMyApps.Items -match 'unavailable'))

# --- 4..5: a FAILED refresh preserves the prior inventory ---------------------
$clbMyApps.SetItemChecked(1, $true)
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'obs' 'themed')) 1
$logBefore = @($script:logLines)
$ok = Load-Targets
$logAfter = @($script:logLines[$logBefore.Count..($script:logLines.Count - 1)])
check 'a failed refresh returns false' ($ok -eq $false)
check 'a failed refresh does NOT erase the prior visible target inventory' (
    $clbMyApps.Items.Count -eq 2 -and $clbPopularApps.Items.Count -eq 1)
check 'a failed refresh keeps the operator checks exactly as they were' ($clbMyApps.GetItemChecked(1))
check 'a failed refresh clears freshness so no mutation is authorised by it' ($script:targetsFresh -eq $false)
check 'a failed refresh reports the reason to the log' (
    (($logAfter -join "`n") -match 'TARGET DISCOVERY FAILED') -and (($logAfter -join "`n") -match 'exited 1'))

# --- 6..7: recovery + selection preservation --------------------------------
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'obs' 'themed'), (New-Row 'notepadplusplus' 'themed'))
# De-select terminal with suppression ON, exactly as the shipped preset loader
# does, so the click is a pure state change and not a path prompt. The real
# handler is what decides whether a path prompt fires; this gate is about which
# key stays selected, so it must not depend on a dialog.
$clbMyApps.SetItemChecked(1, $false)   # de-select terminal, keep windows ticked
$selBefore = @($clbMyApps.CheckedIndices)
$ok = Load-Targets
$selAfter = @($clbMyApps.CheckedIndices)
check 'a successful refresh after a failure restores freshness' ($script:targetsFresh -eq $true)
check 'a de-selected key stays de-selected across the refresh' (-not $clbMyApps.GetItemChecked(1))
check 'a still-selected key stays selected across the refresh' ($clbMyApps.GetItemChecked(0))
check 'a newly appearing selectable target is ticked by default' ($clbMyApps.GetItemChecked(2))
check 'the refresh published every row exactly once (no duplicates)' (
    $clbMyApps.Items.Count -eq 4 -and @($script:targets).Count -eq 4)
$idxOk = $true
foreach ($t in $script:targets) { if ($t.ItemIndex -lt 0 -or $null -eq $t.List) { $idxOk = $false } }
check 'every published record carries a resolved List and ItemIndex' $idxOk

# --- 8: a target that becomes unusable is UNTICKED ---------------------------
$clbMyApps.SetItemChecked(3, $true)     # notepadplusplus is ticked
$script:logLines = @()
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'obs' 'themed'), (New-Row 'notepadplusplus' 'not installed'))
$ok = Load-Targets
check 'a target that became not-installed is unticked, not silently left ticked' (-not $clbMyApps.GetItemChecked(3))
check 'the loss of a usable target is reported with its reason' (
    ($script:logLines -join "`n") -match 'no longer usable' -and ($script:logLines -join "`n") -match 'notepadplusplus')

# --- 9: a path target without a remembered folder is never ticked ------------
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'zcode' 'themed'))
$ok = Load-Targets
check 'a path-backed target with no remembered folder is not ticked' (-not $clbPopularApps.GetItemChecked(0))
check 'the shared predicate is the single selectability rule' (
    (Test-TargetSelectableByState 'zcode' 'themed') -eq $false -and
    (Test-TargetSelectableByState 'zcode' 'listing failed') -eq $false -and
    (Test-TargetSelectableByState 'windows' 'themed') -eq $true)

# --- 10: zero rows with exit 0 is a failure, never "nothing installed" -------
$script:logLines = @()
Set-Listing @() 0
$ok = Load-Targets
check 'a zero-row listing with exit 0 is treated as a failed discovery' ($ok -eq $false)
check 'a zero-row successful-exit listing does NOT publish an empty list over a known inventory' (
    $clbMyApps.Items.Count -ge 1 -and $clbPopularApps.Items.Count -ge 1)
check 'the zero-row failure names the parse problem, not "nothing is installed"' (
    ($script:logLines -join "`n") -match 'no parseable target rows')

# --- 11: T-970 a TRUNCATED listing must not replace a full inventory ----------
# The mission's required negative control: one valid target row, a real exit 0,
# and no completion witness. Under the pre-T-970 predicate this is "a successful
# listing of one target" and the four rows the operator could see a moment ago
# vanish. The transaction must refuse it and keep the prior inventory.
$script:logLines = @()
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'obs' 'themed'), (New-Row 'notepadplusplus' 'themed'))
$ok = Load-Targets
check 'T-970 setup: a complete four-row listing publishes and is fresh' ($ok -eq $true -and $clbMyApps.Items.Count -eq 4)

Set-TruncatedListing @((New-Row 'windows' 'themed'))
$ok = Load-Targets
check 'T-970: a truncated listing with one valid row and exit 0 is NOT usable' ($ok -eq $false)
check 'T-970: a truncated listing does NOT replace the prior full inventory' (
    $clbMyApps.Items.Count -eq 4 -and $clbPopularApps.Items.Count -eq 0)
check 'T-970: a truncated listing clears freshness' ($script:targetsFresh -eq $false)
check 'T-970: a truncated listing says the inventory may be incomplete, not "nothing installed"' (
    ($script:logLines -join "`n") -match 'never reported completion' -and
    ($script:logLines -join "`n") -notmatch 'no parseable target rows')

# --- 12: T-970 a witness count that does not match the parsed rows is a failure -
$script:logLines = @()
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'), (New-Row 'obs' 'themed'), (New-Row 'notepadplusplus' 'themed'))
$null = Load-Targets
Set-ListingWithDeclared @((New-Row 'windows' 'themed'), (New-Row 'obs' 'listing failed')) 9
$ok = Load-Targets
check 'T-970: a listing whose declared count exceeds its parseable rows is NOT usable' ($ok -eq $false)
check 'T-970: a count mismatch does not replace the prior inventory' ($clbMyApps.Items.Count -eq 4)
check 'T-970: a count mismatch states both numbers' (
    ($script:logLines -join "`n") -match 'claims 9 target row' -and ($script:logLines -join "`n") -match 'only 2 were parseable')

# --- 13: T-970 the witness is REQUIRED, and a matching one is still accepted ---
# A listing that parses to the same rows WITH the witness must still publish, so
# the new gate cannot pass by refusing everything.
$script:logLines = @()
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed'))
$ok = Load-Targets
check 'T-970: an intact listing with a matching witness still publishes' ($ok -eq $true -and $clbMyApps.Items.Count -eq 2)
$listing = Get-TargetListing
check 'T-970: Get-TargetListing reports the witness it saw' ($listing.Declared -eq 2 -and $listing.Complete -eq $true)
Set-TruncatedListing @((New-Row 'windows' 'themed'))
$listing = Get-TargetListing
check 'T-970: a listing without a witness reports Declared null, Complete false' (
    $null -eq $listing.Declared -and $listing.Complete -eq $false)

# --- 14: an exception from the listing child is caught, not fatal -----------
$global:LASTEXITCODE = 0
$script:TargetListingRunner = { param() throw 'child process could not be started: the system cannot find the file specified' }
$ok = Load-Targets
check 'a listing child that cannot start is a handled failure, not a crash' ($ok -eq $false)
check 'a start failure also clears freshness' ($script:targetsFresh -eq $false)

# --- RED CONTROL: the legacy Load-Targets is caught by this gate --------------
# The assertions above are only worth something if the OLD behaviour fails them.
# This is the shipped legacy shape (clear both lists, then ask the child, then
# publish whatever came back) run against the SAME failing listing. It must leave
# the operator with no inventory and no freshness, which is exactly what the
# transaction assertions above forbid.
function Invoke-LegacyLoadTargets {
    $clbMyApps.Items.Clear()
    $clbPopularApps.Items.Clear()
    $listing = Get-TargetListing
    $script:targets = @()
    foreach ($t in $listing.Rows) {
        $list = if ($t.Key -in $MY_APP_KEYS) { $clbMyApps } else { $clbPopularApps }
        [void]$list.Items.Add(('{0,-16} {1}' -f $t.Key, $t.State))
    }
    $script:targetsFresh = $true
    return $true
}
# T-970 RED CONTROL: the legacy SUCCESS PREDICATE itself -- exit 0 and at least
# one recognised row -- evaluated against the truncated listing the transaction now
# refuses. This is the exact expression the shipped pre-T-970 Get-TargetListing
# computed; it answers TRUE, which is why a truncated stream used to be published
# as a fresh full inventory.
function Test-LegacyListingOk([object]$listing) {
    return ($listing.ExitCode -eq 0 -and $listing.Rows.Count -gt 0)
}
$script:listingLines = @(''); $script:listingExit = 0
$script:TargetListingRunner = { param()
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllLines($tmp, $script:listingLines)
        & powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '$tmp'; exit $($script:listingExit)"
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
Set-Listing @((New-Row 'windows' 'themed'), (New-Row 'terminal' 'themed')) 0
$null = Invoke-LegacyLoadTargets
Set-Listing @() 1
$legacyOk = Invoke-LegacyLoadTargets
# The exact expression the section-4 assertion uses, evaluated against legacy:
$inventorySurvived = ($clbMyApps.Items.Count -eq 2 -and $clbPopularApps.Items.Count -eq 1)
check 'RED: legacy refresh still claims success after a failed listing' ($legacyOk -eq $true)
check 'RED: the transaction inventory assertion is FALSE under the legacy refresh' (-not $inventorySurvived)
check 'RED: legacy reports the stale table as fresh (mutation authority from a failed refresh)' ($script:targetsFresh -eq $true)

# T-970 RED: the truncated listing is exactly the shape the legacy predicate calls
# a success, and the transaction now calls a failure -- so the new control is not
# vacuous and the two predicates genuinely disagree.
Set-TruncatedListing @((New-Row 'windows' 'themed'))
$legacyListing = Get-TargetListing
check 'T-970 RED: the legacy success predicate accepts the truncated listing' (Test-LegacyListingOk $legacyListing)
check 'T-970 RED: the shipped predicate rejects the same listing' ($legacyListing.Ok -eq $false)
check 'T-970 RED: the two predicates disagree on identical input (the control is not vacuous)' (
    (Test-LegacyListingOk $legacyListing) -and (-not $legacyListing.Ok))

Write-Host ''
Write-Host ("test-target-refresh-transaction.ps1: $pass PASS / $fail FAIL") -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
