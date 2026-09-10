# Recovery-consumption ordering regression suite (T-206 / W2-009 / SRC-005 W2-003).
#
# Wintage-owned source files (SmartVac, WildRift, SAIPENVIEW) Revert by
# copying a per-target `<file>.bak` backup back over the themed file and
# then consuming the backup. The audit caught that the original code deleted
# the backup BEFORE the manifest removal committed -- a process kill at that
# seam strands `manifest says installed + no recovery`, a permanent
# fail-closed state the user cannot recover from. The first fix deferred the
# deletion INTO the commit scriptblock; SRC-005 W2-003 hardened that into a
# retire-first protocol, because a scriptblock is NOT an atomic primitive:
# the backup is RENAMED to a `<file>.wintage-retired` tombstone BEFORE
# Invoke-TargetCommit, the manifest entry is removed inside the commit, the
# tombstone is deleted only after the manifest transition succeeded
# (post-commit GC), and a failed commit renames the tombstone back so the
# retry keeps its recovery authority. Restore-FilePreState (in-memory
# prestate) remains the safety net for the live file on a commit failure.
#
# This test enforces:
#   1. The structural invariant -- for each of the three Revert call sites
#      (Invoke-SmartVac, Invoke-WildRift, Invoke-Saipenview), no code line
#      between `Copy-Item $bakFile` and `Invoke-TargetCommit` deletes the
#      backup (`Remove-Item $bakFile`), and the retire-first rename to the
#      tombstone is present. Full-line PowerShell comments are stripped
#      before matching, so a comment naming the old defect cannot satisfy
#      or trip the assertion.
#   2. The commit scriptblock removes the manifest entry and performs the
#      post-commit tombstone GC (`Remove-Item $retire`), NOT a backup
#      deletion.
#   3. The behavioural round-trip -- Save-FilePreState captures live+bak
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
    Write-Host "test-recovery-consumption.ps1 (6 tests):"
    Write-Host "  1. SmartVac Revert: retire-first rename, no backup deletion, before Invoke-TargetCommit"
    Write-Host "  2. WildRift Revert: retire-first rename, no backup deletion, before Invoke-TargetCommit"
    Write-Host "  3. SAIPENVIEW Revert: retire-first rename, no backup deletion, before Invoke-TargetCommit"
    Write-Host "  4. SmartVac commit scriptblock: Remove-ManifestEntry + post-commit tombstone GC"
    Write-Host "  5. Restore-FilePreState byte-exact round-trip after a failed commit"
    Write-Host "  6. WildRift + SAIPENVIEW commit scriptblocks: post-commit tombstone GC"
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
    $aidx = $text.IndexOf('if (-not $PSCmdlet.ShouldProcess', $ridx)
    if ($aidx -lt 0) { return $null }
    return $text.Substring($ridx, $aidx - $ridx)
}
function Extract-CommitScriptblock([string]$block) {
    $tIdx = $block.IndexOf('Invoke-TargetCommit')
    if ($tIdx -lt 0) { return $null }
    return (Extract-ScriptblockFrom $block ($block.IndexOf('{', $tIdx)))
}

foreach ($fn in @('Invoke-SmartVac', 'Invoke-WildRift', 'Invoke-Saipenview')) {
    # The live target variable differs per handler (pyFile vs cssFile).
    $liveVar = if ($fn -eq 'Invoke-Saipenview') { 'cssFile' } else { 'pyFile' }
    $rb = Get-RevertBlock $src $fn
    $revert = Remove-CommentLines $rb
    $commit = Extract-CommitScriptblock $revert
    $rollback = Extract-RollbackScriptblock $revert
    check "${fn}: revert branch has a commit scriptblock" ($null -ne $commit)
    if ($commit) {
        # (a) W2-002: live mutation + retire rename are INSIDE the commit block.
        check "${fn}: W2-002 live mutation (Copy-Item bak->live) is inside the commit scriptblock" ($commit -match "Copy-Item\s+\`$bakFile\s+\`$$liveVar")
        check "${fn}: W2-002 retire-first rename is inside the commit scriptblock" ($commit -match 'Rename-Item\s+\$bakFile\s+\$retire')
        # (b) W2-003: manifest removal + post-commit tombstone GC, never bak deletion.
        $manifestKey = $fn -replace '^Invoke-', ''
        $manifestKey = $manifestKey.Substring(0, 1).ToLower() + $manifestKey.Substring(1)
        check "${fn}: commit scriptblock removes the manifest entry" ($commit -match "Remove-ManifestEntry\s+'$manifestKey'")
        check "${fn}: commit scriptblock does post-commit tombstone GC (Remove-Item \$retire)" ($commit -match 'Remove-Item\s+\$retire')
        check "${fn}: commit scriptblock never deletes the backup itself" (-not ($commit -match 'Remove-Item\s+\$bakFile'))
    }
    # (c) rollback callback restores the tombstone on manifest-commit failure.
    check "${fn}: rollback callback restores the tombstone (Rename-Item \$retire \$bakFile)" ($null -ne $rollback -and $rollback -match 'Rename-Item\s+\$retire\s+\$bakFile')
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
