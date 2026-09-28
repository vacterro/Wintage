# Focused regression gates for the imp-vacterro-wintage-20260927-2 audit wave
# (Core seat antigravity-01, RUN 1). One suite, one place, so a future edit that
# re-introduces any of these defects fails here instead of surviving a green
# Run-Tests run.
#
#   T-321  Select-TfPreferenceRow must resolve against the VISIBLE rows
#   T-327  Apply/Revert must classify from the machine-result records, not the
#          log prose, and must not read .Output off the batch STATE object
#   T-328  Invoke-TfApply must not forward the '<custom>' GUI sentinel as a slug
#   T-330  the Fonts-tab Refresh button must not overlap the rendering combo
#   T-332  the -Reapply PLANNING health probes must not throw out of the loop
#   T-333  the wintage-result record must not pass through an identity -replace
#   T-334  the Process Explorer recovery reader must validate the ledger SHAPE
#   T-337  the "nothing to revert" arm must complete its dir-prestate snapshot
#   T-338  the write-only $script:fbPreviewPending flag is gone
#
# Parse-gated: every file it reads is parsed with the real PowerShell parser
# before any assertion, so a syntax error is reported as a failure, not a
# silent pass.
#
#   .\tools\test-audit-20260927-fixes.ps1

[CmdletBinding()]
param([switch]$List)

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
    Write-Host 'test-audit-20260927-fixes.ps1:'
    Write-Host '  T-321  Fonts selection resolves against the visible rows'
    Write-Host '  T-327  Apply/Revert classify from the machine-result records'
    Write-Host '  T-328  Fonts Apply normalises the <custom> sentinel'
    Write-Host '  T-330  Refresh button and rendering combo do not overlap'
    Write-Host '  T-332  reapply planning health probes are contained'
    Write-Host '  T-333  no identity -replace on the wintage-result record'
    Write-Host '  T-334  Process Explorer recovery validates the ledger shape'
    Write-Host '  T-337  the nothing-to-revert arm completes its snapshot'
    Write-Host '  T-338  the write-only fbPreviewPending flag is gone'
    exit 0
}

function Get-Text([string]$rel) { [System.IO.File]::ReadAllText((Join-Path $root $rel), $utf8) }

function Get-FnText([string]$text, [string]$name) {
    $m = [regex]::Match($text, 'function\s+' + [regex]::Escape($name) + '\b')
    if (-not $m.Success) { return $null }
    $open = $text.IndexOf('{', $m.Index)
    if ($open -lt 0) { return $null }
    $depth = 0
    for ($j = $open; $j -lt $text.Length; $j++) {
        if ($text[$j] -eq '{') { $depth++ }
        elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($m.Index, $j - $m.Index + 1) } }
    }
    return $null
}

# Pull the source of a single Add_Click handler by its anchor line, so a change
# in the surrounding event wiring cannot smuggle the old body back in.
function Get-HandlerText([string]$text, [string]$anchor) {
    $start = $text.IndexOf($anchor)
    if ($start -lt 0) { return $null }
    $open = $text.IndexOf('{', $start)
    if ($open -lt 0) { return $null }
    $depth = 0
    for ($j = $open; $j -lt $text.Length; $j++) {
        if ($text[$j] -eq '{') { $depth++ }
        elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start, $j - $start + 1) } }
    }
    return $null
}

# ---- parse gate ----------------------------------------------------------------
$files = @(
    'desktop\WintageInstaller.ps1',
    'desktop\install.ps1',
    'desktop\modules\common.ps1',
    'desktop\modules\targets.ps1'
)
foreach ($f in $files) {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$errs) | Out-Null
    check "$f parses with zero syntax errors" ($errs.Count -eq 0)
    if ($errs.Count) { $errs | Select-Object -First 3 | ForEach-Object { Write-Host ("       " + $_.Message) -ForegroundColor Red } }
}

$gui = Get-Text 'desktop\WintageInstaller.ps1'
$inst = Get-Text 'desktop\install.ps1'
$common = Get-Text 'desktop\modules\common.ps1'
$targets = Get-Text 'desktop\modules\targets.ps1'

# ---- T-321 ---------------------------------------------------------------------
$selectFn = Get-FnText $gui 'Select-TfPreferenceRow'
check 'T-321: Select-TfPreferenceRow exists' ($null -ne $selectFn)
if ($selectFn) {
    check 'T-321: it indexes the VISIBLE rows, not the unfiltered catalog' ($selectFn -match '\$script:TfVisibleRows\[\$i\]')
    check 'T-321: it does NOT index the unfiltered catalog' ($selectFn -notmatch '\$script:TfRows\[\$i\]')
    # The loop bound is the ListBox item count; the array it indexes must be the
    # one the ListBox is filled from.
    check 'T-321: the loop is still bounded by the ListBox item count' ($selectFn -match '\$lstTfFonts\.Items\.Count')
}

# ---- T-327 ---------------------------------------------------------------------
$classify = Get-FnText $gui 'Classify-BatchResult'
check 'T-327: Classify-BatchResult exists' ($null -ne $classify)
if ($classify) {
    check 'T-327: it accepts an explicit selected set' ($classify -match '\[string\[\]\]\$Selected')
    check 'T-327: it reports the failed target names' ($classify -match 'FailedNames')
}
foreach ($pair in @(@('Apply', '$btnApply.Add_Click'), @('Revert', '$btnRevert.Add_Click'))) {
    $h = Get-HandlerText $gui $pair[1]
    check ("T-327: the $($pair[0]) handler exists") ($null -ne $h)
    if ($h) {
        # Comments are stripped first: the fix explains in prose that reading
        # $child.Output was the defect, and a naive substring match would then
        # fail the gate on its own explanation.
        $code = ($h -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        check ("T-327: $($pair[0]) classifies from the machine-result records") ($code -match 'Classify-BatchResult')
        check ("T-327: $($pair[0]) does NOT read .Output off the batch state") ($code -notmatch '\$child\.Output')
        check ("T-327: $($pair[0]) does NOT blanket-fail every key on a non-zero exit") (
            $code -notmatch '\$child\.ExitCode\s+-ne\s+0\s+-and\s+-not\s+\$failed\.Count\s*\{\s*\$failed\s*=\s*@\(\$keys\)')
    }
}

# ---- T-328 ---------------------------------------------------------------------
$tfApply = Get-FnText $gui 'Invoke-TfApply'
check 'T-328: Invoke-TfApply exists' ($null -ne $tfApply)
if ($tfApply) {
    check 'T-328: it normalises the <custom> sentinel before dispatch' ($tfApply -match "\`$script:current\s+-eq\s+'<custom>'")
    check 'T-328: the child invocation carries the normalised slug, not $script:current' (
        $tfApply -match "-Palette'\s*,\s*\`$paletteSlug" -or $tfApply -match '-Palette\s+\$paletteSlug')
    check 'T-328: it does NOT forward $script:current verbatim as -Palette' ($tfApply -notmatch "-Palette'\s*,\s*\`$script:current")
}

# ---- T-330 ---------------------------------------------------------------------
function Get-Rect([string]$varName) {
    $loc = [regex]::Match($gui, [regex]::Escape($varName) + "\.Location\s*=\s*'(\d+),(\d+)'")
    $siz = [regex]::Match($gui, [regex]::Escape($varName) + "\.Size\s*=\s*'(\d+),(\d+)'")
    if (-not ($loc.Success -and $siz.Success)) { return $null }
    [pscustomobject]@{
        X = [int]$loc.Groups[1].Value; Y = [int]$loc.Groups[2].Value
        W = [int]$siz.Groups[1].Value; H = [int]$siz.Groups[2].Value
    }
}
$combo = Get-Rect '$cmbTfRendering'
$refresh = Get-Rect '$btnTfRefresh'
$panel = Get-Rect '$pnlFonts'
check 'T-330: the rendering combo rect is readable' ($null -ne $combo)
check 'T-330: the Refresh button rect is readable' ($null -ne $refresh)
if ($combo -and $refresh) {
    $overlapX = [Math]::Min($combo.X + $combo.W, $refresh.X + $refresh.W) - [Math]::Max($combo.X, $refresh.X)
    $overlapY = [Math]::Min($combo.Y + $combo.H, $refresh.Y + $refresh.H) - [Math]::Max($combo.Y, $refresh.Y)
    $overlaps = ($overlapX -gt 0 -and $overlapY -gt 0)
    check 'T-330: Refresh does NOT overlap the rendering combo' (-not $overlaps)
    if ($overlaps) { Write-Host ("       overlap: $($overlapX)x$($overlapY) px at ($($refresh.X),$($refresh.Y))") -ForegroundColor Red }
    if ($panel) {
        check 'T-330: Refresh stays inside the Fonts panel' (
            ($refresh.X + $refresh.W -le $panel.W) -and ($refresh.Y + $refresh.H -le $panel.H))
    }
}

# ---- T-332 ---------------------------------------------------------------------
$health = Get-FnText $targets 'Test-TargetNeedsReapply'
check 'T-332: Test-TargetNeedsReapply exists' ($null -ne $health)
if ($health) {
    # A health probe that throws escapes the -Reapply PLANNING loop and aborts
    # every other target, so each state-reading probe needs a local guard.
    $conhostCall = [regex]::Match($health, "(?s)\}\s*'conhost'\s*\{(.*?)\n            \}")
    check 'T-332: the conhost health branch is readable' ($conhostCall.Success)
    if ($conhostCall.Success) {
        $body = $conhostCall.Groups[1].Value
        check 'T-332: the conhost font probe is guarded' ($body -match 'catch')
        check 'T-332: the conhost guard reports a reason instead of throwing' ($body -match '\$reasons\s*\+=')
    }
    $peCall = [regex]::Match($health, "(?s)'processexplorer'\s*\{(.*?)\n            \}")
    check 'T-332: the processexplorer health branch is readable' ($peCall.Success)
    if ($peCall.Success) {
        $body = $peCall.Groups[1].Value
        check 'T-332: the Process Explorer state read is guarded' ($body -match 'catch')
    }
}

# ---- T-333 ---------------------------------------------------------------------
$emit = Get-FnText $inst 'Emit-BatchResult'
check 'T-333: Emit-BatchResult exists' ($null -ne $emit)
if ($emit) {
    check 'T-333: the record is not passed through an identity -replace' ($emit -notmatch "-replace\s+`"'", '')
    check 'T-333: the record is emitted with ConvertTo-Json -Compress' ($emit -match 'ConvertTo-Json -Compress')
}

# ---- T-334 ---------------------------------------------------------------------
$peInvoke = Get-FnText $targets 'Invoke-ProcessExplorer'
$peRestore = Get-FnText $targets 'Restore-ProcessExplorerState'
check 'T-334: Invoke-ProcessExplorer exists' ($null -ne $peInvoke)
check 'T-334: Restore-ProcessExplorerState exists' ($null -ne $peRestore)
if ($peInvoke) {
    check 'T-334: the recovery root is rejected when it is not a JSON object' ($peInvoke -match "-is\s+\[System\.Array\]")
    check 'T-334: the values ledger is read through a validated property' ($peInvoke -match "\`$valuesProp\s*=")
    check 'T-334: a non-object values ledger is refused' ($peInvoke -match 'valuesProp\.Value\s+-is\s+\[System\.Array\]')
    check 'T-334: keyExisted is required and must be a real boolean' ($peInvoke -match 'keyExistedProp\.Value\s+-isnot\s+\[bool\]')
    check 'T-334: a non-numeric ledger entry is refused rather than cast' ($peInvoke -match 'uint32\]::TryParse')
}
if ($peRestore) {
    check 'T-334: the restore CONSUMES the recorded key-existed flag' ($peRestore -match '\$state\.Existed')
    check 'T-334: a first-touch revert removes the key it created' ($peRestore -match 'Remove-Item -LiteralPath \$keyPath')
}

# ---- T-337 ---------------------------------------------------------------------
$revertLeg = Get-HandlerText $inst 'nothing to revert'
check 'T-337: the "nothing to revert" message exists' ($null -ne $revertLeg)
if ($revertLeg) {
    check 'T-337: that arm completes the dir-prestate snapshot it took' ($revertLeg -match 'Complete-DirPreState \$preDest')
}
# Every arm of the vscode extension revert must dispose the snapshot exactly once.
$completeCalls = ([regex]::Matches($inst, 'Complete-DirPreState \$preDest')).Count
$snapshotCalls = ([regex]::Matches($inst, '\$preDest\s*=\s*Save-DirPreState')).Count
check 'T-337: every dir-prestate snapshot has a matching completion' ($completeCalls -ge $snapshotCalls)

# ---- T-338 ---------------------------------------------------------------------
check 'T-338: the write-only $script:fbPreviewPending flag is gone' (-not ($gui -match 'fbPreviewPending'))
check 'T-338: the per-request record still carries the persistence decision' ($gui -match 'fbPreviewReq')

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
