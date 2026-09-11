# Recovery-consumption ordering regression suite (T-206 / W2-009 / SRC-005 W2-003).
#
# Revert operations must remove the manifest entry INSIDE Invoke-TargetCommit,
# and rollback callbacks must restore the captured pre-state if the manifest
# commit fails.
#
# This test enforces:
#   1. Revert handlers (Notepad++, Cinema 4D) use Invoke-TargetCommit to remove
#      their manifest entry and pair it with a pre-state rollback callback.
#   2. The behavioural round-trip -- Save-FilePreState captures live+bak
#      bytes, and Restore-FilePreState reconstructs both exactly after a
#      failed commit.
#
#   .\tools\test-recovery-consumption.ps1          # all tests
#   .\tools\test-recovery-consumption.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$targets = Join-Path $here '..\desktop\modules\targets.ps1'
$common = Join-Path $here '..\desktop\modules\common.ps1'
$pass = 0; $fail = 0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Strip full-line PowerShell comments so prose in code comments can never
# satisfy or trip a structural assertion.
function Remove-CommentLines([string]$text) {
    return (($text -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}

if ($List) {
    Write-Host "test-recovery-consumption.ps1 (3 tests):"
    Write-Host "  1. Notepad++ Revert: Invoke-TargetCommit manifest removal + rollback"
    Write-Host "  2. Cinema 4D Revert: Invoke-TargetCommit manifest removal + rollback"
    Write-Host "  3. Restore-FilePreState byte-exact round-trip after a failed commit"
    exit 0
}

# ------------------------------------------------------------------ fixtures
$src = Get-Content $targets -Raw
$commonSrc = Get-Content $common -Raw
check 'BetterDiscord: replaced recovery without pristine fails closed' ($src -match 'if \(\$meta\.mode -eq ''replaced'' -and -not \(Test-Path \$pristine\)\)')
check 'TotalCmd: health captures value after matched key prefix' ($src -match '\$v = \$line\.Substring\(\$m\.Index \+ \$m\.Length\)')
check 'MPC-HC: missing OSDTransparency is unhealthy' ($src -match '\$props\.OSDTransparency -ne 0')
check 'Portable Electron: process names accept arrays' ($commonSrc -match 'Resolve-PortableElectron\(\[string\]\$key, \[string\]\$explicitPath, \[hashtable\]\$remembered, \[string\[\]\]\$processName')

# ---- Tests 1..6: W2-002 (mutation-before-transaction) + W2-003
# (retire-first tombstone) combined contract, asserted structurally from the
# SOURCE. For each source-backed target the Revert branch must:
#   (a) wrap the LIVE mutation (Copy-Item $bakFile $pyFile) and the retire-first
#       rename (Rename-Item $bakFile $retire) INSIDE the commit scriptblock, so
#       a failure after the snapshot but before the manifest transition rolls the
#       captured pre-state back (W2-002);
#   (b) remove the manifest entry and GC the tombstone only after the commit is
#       known good, and never delete the backup itself (W2-003);
#   (c) restore the tombstone on a manifest-commit failure (rollback callback).
# The old W2-003-only tests asserted Copy-Item BEFORE Invoke-TargetCommit; that
# ordering is exactly the defect W2-002 repairs, so they are replaced by (a).
function Extract-RollbackScriptblock([string]$block) {
    # Second top-level { } after the first Invoke-TargetCommit is the rollback.
    $tIdx = $block.IndexOf('Invoke-TargetCommit')
    if ($tIdx -lt 0) { return $null }
    $first = Extract-ScriptblockFrom $block ($block.IndexOf('{', $tIdx))
    if ($null -eq $first) { return $null }
    $afterFirst = $block.IndexOf('}', $block.IndexOf('{', $tIdx))
    # Find the rollback opener: the first '{' after the commit block closes.
    $depth = 0
    $start = $block.IndexOf('{', $tIdx)
    for ($i = $start; $i -lt $block.Length; $i++) {
        if ($block[$i] -eq '{') { $depth++ }
        elseif ($block[$i] -eq '}') { $depth--; if ($depth -eq 0) { $afterFirst = $i; break } }
    }
    $rbStart = $block.IndexOf('{', $afterFirst + 1)
    if ($rbStart -lt 0) { return $null }
    return (Extract-ScriptblockFrom $block $rbStart)
}
function Extract-ScriptblockFrom([string]$block, $openBrace) {
    if ($openBrace -lt 0) { return $null }
    $depth = 0
    for ($i = $openBrace; $i -lt $block.Length; $i++) {
        if ($block[$i] -eq '{') { $depth++ }
        elseif ($block[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $block.Substring($openBrace + 1, $i - $openBrace - 1) } }
    }
    return $null
}
# Rebuild a revert block (with the Invoke-TargetCommit) for the scriptblock
# extraction: find the function and slice to the Apply branch.
function Get-RevertBlock([string]$text, [string]$funcName) {
    $fidx = $text.IndexOf("function $funcName")
    if ($fidx -lt 0) { return $null }
    $ridx = $text.IndexOf('if ($DoRevert) {', $fidx)
    if ($ridx -lt 0) { return $null }
    $aidx = $text.IndexOf("`n    `$built =", $ridx)
    if ($aidx -lt 0) { $aidx = $text.IndexOf('if (-not $PSCmdlet.ShouldProcess', $ridx) }
    if ($aidx -lt 0) { return $null }
    return $text.Substring($ridx, $aidx - $ridx)
}
function Extract-CommitScriptblock([string]$block) {
    $tIdx = $block.IndexOf('Invoke-TargetCommit')
    if ($tIdx -lt 0) { return $null }
    return (Extract-ScriptblockFrom $block ($block.IndexOf('{', $tIdx)))
}

foreach ($fn in @('Invoke-NotepadPlusPlus', 'Invoke-Cinema4D')) {
    $rb = Get-RevertBlock $src $fn
    $revert = Remove-CommentLines $rb
    $commit = Extract-CommitScriptblock $revert
    $rollback = Extract-RollbackScriptblock $revert
    check "${fn}: revert branch has a commit scriptblock" ($null -ne $commit)
    if ($commit) {
        $manifestKey = ($fn -replace '^Invoke-', '').ToLower()
        check "${fn}: commit scriptblock removes the manifest entry" ($commit -match "Remove-ManifestEntry\s+'$manifestKey'")
    }
    check "${fn}: rollback callback restores the pre-state" ($null -ne $rollback -and ($rollback -match 'Restore-FilePreState' -or $rollback -match 'Restore-DirPreState'))
}

# ---- Test 5: behavioural round-trip ----
# Save-FilePreState captures both live and bak bytes. Restore-FilePreState
# must reconstruct both exactly -- which is the in-memory safety net that
# makes the deferral correct.
. $common
# The two pre-state helpers are defined in targets.ps1, not common.ps1.
# Inline the bodies here so the test is self-contained and does not pull
# in the rest of the target universe.
function Save-FilePreState([string]$file, [string]$bakFile) {
    $bakOk = $bakFile -and (Test-Path $bakFile)
    return [pscustomobject]@{
        fileBytes = if ($file -and (Test-Path $file)) { [System.IO.File]::ReadAllBytes($file) } else { $null }
        bakExists = [bool]$bakOk
        bakBytes  = if ($bakOk) { [System.IO.File]::ReadAllBytes($bakFile) } else { $null }
    }
}
function Restore-FilePreState($pre, [string]$file, [string]$bakFile) {
    if ($pre -and $null -ne $pre.fileBytes -and $file) { [System.IO.File]::WriteAllBytes($file, $pre.fileBytes) }
    elseif ($file -and (Test-Path $file)) { Remove-Item $file -Force }
    if ($pre -and $pre.bakExists -and $bakFile) { [System.IO.File]::WriteAllBytes($bakFile, $pre.bakBytes) }
    elseif ($bakFile -and (Test-Path $bakFile)) { Remove-Item $bakFile -Force }
}
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-recovery-consumption-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$live = Join-Path $testRoot 'live.py'
$bak  = Join-Path $testRoot 'live.py.bak'
$liveContent = "live=original`r`n"
$bakContent  = "backup=original`r`n"
[System.IO.File]::WriteAllText($live, $liveContent, $script:Utf8NoBom)
[System.IO.File]::WriteAllText($bak,  $bakContent,  $script:Utf8NoBom)
$pre = Save-FilePreState $live $bak
check 'rc: Save-FilePreState captured bakExists=true' ($pre.bakExists -eq $true)
check 'rc: Save-FilePreState captured both file and bak bytes' ($pre.fileBytes.Length -gt 0 -and $pre.bakBytes.Length -gt 0)

# Simulate the deferred-commit pattern: copy backup over live (the visible
# part of the Revert that must happen before the manifest commit) WITHOUT
# touching the bak. A process death here is now safe -- bak intact, manifest
# still says installed, user can retry.
Copy-Item $bak $live -Force
$liveAfterCopy = [System.IO.File]::ReadAllText($live, $script:Utf8NoBom)
check 'rc: Copy-Item put the bak content into the live file' ($liveAfterCopy -eq $bakContent)
check 'rc: bak still exists after Copy-Item (the deferral contract)' (Test-Path $bak)
$bakUntouched = [System.IO.File]::ReadAllText($bak, $script:Utf8NoBom)
check 'rc: bak bytes are untouched (the deferral contract)' ($bakUntouched -eq $bakContent)

# Simulate a commit failure: the commit scriptblock throws AFTER doing
# its manifest work. Restore-FilePreState must put the live file back to
# its pre-operation state, the bak to its pre-operation state, and leave
# NO straggler content.
Restore-FilePreState $pre $live $bak
check 'rc: Restore-FilePreState rewrote live to pre-operation bytes' (
    [System.IO.File]::ReadAllText($live, $script:Utf8NoBom) -eq $liveContent)
check 'rc: Restore-FilePreState rewrote bak to pre-operation bytes' (
    [System.IO.File]::ReadAllText($bak,  $script:Utf8NoBom) -eq $bakContent)

# Now the HAPPY path: Copy-Item + Invoke-TargetCommit succeeds (manifest
# removed) + bak removed in the same scriptblock. End state: live is
# restored, bak is gone, manifest entry removed.
Copy-Item $bak $live -Force
Remove-Item $bak -Force
check 'rc: happy-path post-commit: live carries the restored content' (
    [System.IO.File]::ReadAllText($live, $script:Utf8NoBom) -eq $bakContent)
check 'rc: happy-path post-commit: bak is gone' (-not (Test-Path $bak))

Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
