# Save-DirPreState / Restore-DirPreState absent-directory regression suite (T-208 / CORE-005).
#
# Whole-directory snapshots back the browser stage and VS Code-family Apply /
# Revert transactions. The pre-fix contract was a nullable path: a missing
# directory produced `$null` from Save, and Restore was a no-op for null.
# First-install targets routinely create the directory as part of their
# mutation, so a manifest-commit failure on a first install left a
# newly-created directory behind while the manifest stayed at its previous
# (absent) state -- the user's filesystem and the ledger disagreed.
#
# The fix introduces a structured snapshot with explicit `Existed` and
# `SnapshotPath` fields. Restore recreates the exact pre-state:
#   - Existed=true  -> materialise the captured snapshot via temp-sibling swap
#                      (the byte-exact, recursive restore)
#   - Existed=false -> remove the current destination if it was created
#
# This test exercises the new contract end-to-end and confirms the audit's
# verify bar: first-install fixtures start with destination absent, a
# manifest commit failure still ends with destination absent and the
# pre-state restored byte-exactly; existing-directory fixtures continue to
# restore their original recursive byte set.
#
#   .\tools\test-dir-prestate.ps1          # all tests
#   .\tools\test-dir-prestate.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$targets = Join-Path $here '..\desktop\modules\targets.ps1'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-dir-prestate.ps1 (15 tests):"
    Write-Host "  1. Save returns structured snapshot with Existed=true and SnapshotPath for an existing dir"
    Write-Host "  2. Save returns structured snapshot with Existed=false for an absent dir"
    Write-Host "  3. Restore for Existed=true reconstructs the byte-exact pre-state recursively"
    Write-Host "  4. Restore for Existed=false removes a directory that the mutation created"
    Write-Host "  5. Restore for Existed=false is a no-op when the directory is still absent"
    Write-Host "  6. Restore for Existed=true is a no-op when SnapshotPath is missing (lost capture)"
    Write-Host "  7. First-install scenario: Apply creates dir, manifest commit fails, restore returns to absent"
    Write-Host "  8. Existing-dir scenario: Apply mutates contents, manifest commit fails, restore returns to original"
    Write-Host "  9. Snapshot directory is cleaned up after Restore"
    Write-Host " 10. No nullable-path contract remains: every Save call returns a hashtable"
    Write-Host " 11. W2-001: Restore refuses a raw string snapshot (malformed contract)"
    Write-Host " 12. W2-001: Restore refuses a hashtable without Existed/SnapshotPath fields"
    Write-Host " 13. W2-002: failed swap preserves BOTH original and restored copy as recovery locations"
    Write-Host " 14. W2-002: successful swap retires the original cleanly (no .wintage-retired leftovers)"
    Write-Host " 15. W2-002: snapshot directory is consumed once the swap is known good"
    exit 0
}

# ------------------------------------------------------------------ helpers
# Save-DirPreState / Restore-DirPreState are defined in targets.ps1 inside a
# shared target-universe scope. We extract and eval their bodies so this test
# stays self-contained -- the rest of targets.ps1 pulls in $root, $node,
# $WintageAppData, etc., which are not relevant to the unit under test.
$src = Get-Content $targets -Raw
$start = $src.IndexOf('function Save-DirPreState')
$end   = $src.IndexOf("`nfunction", $start + 1)
$body  = $src.Substring($start, $end - $start)
# Repeat to capture Restore-DirPreState too.
$start2 = $src.IndexOf('function Restore-DirPreState', $end)
$end2   = $src.IndexOf("`nfunction", $start2 + 1)
$body  += "`n" + $src.Substring($start2, $end2 - $start2)
Invoke-Expression $body

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-dir-prestate-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# ---- Test 1: Save on existing dir returns Existed=true + SnapshotPath ----
$existing = Join-Path $testRoot 'existing'
New-Item -ItemType Directory -Path $existing -Force | Out-Null
'sample' | Set-Content (Join-Path $existing 'a.txt')
'sample' | Set-Content (Join-Path $existing 'b.txt')
$snap = Save-DirPreState $existing
check 'Save: existing dir -> Existed=true' ($snap.Existed -eq $true)
check 'Save: existing dir -> SnapshotPath is non-null' ($null -ne $snap.SnapshotPath)
check 'Save: existing dir -> SnapshotPath is a real directory' (Test-Path $snap.SnapshotPath)
# Cleanup
if ($snap.SnapshotPath -and (Test-Path $snap.SnapshotPath)) { Remove-Item $snap.SnapshotPath -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Test 2: Save on absent dir returns Existed=false ----
$absent = Join-Path $testRoot 'absent'
check 'Save: absent dir -> Save does not create it' (-not (Test-Path $absent))
$snap2 = Save-DirPreState $absent
check 'Save: absent dir -> Existed=false' ($snap2.Existed -eq $false)
check 'Save: absent dir -> SnapshotPath is null' ($null -eq $snap2.SnapshotPath)

# ---- Test 3: Restore for Existed=true reconstructs byte-exact state ----
$mutated = Join-Path $testRoot 'mutated'
New-Item -ItemType Directory -Path $mutated -Force | Out-Null
'original' | Set-Content (Join-Path $mutated 'a.txt')
'original' | Set-Content (Join-Path $mutated 'b.txt')
$snap3 = Save-DirPreState $mutated
# Simulate a mutation.
'CHANGED' | Set-Content (Join-Path $mutated 'a.txt')
'NEW'      | Set-Content (Join-Path $mutated 'c.txt')
Remove-Item (Join-Path $mutated 'b.txt') -Force
Restore-DirPreState $mutated $snap3
check 'restore existing: a.txt restored to original content' (((Get-Content (Join-Path $mutated 'a.txt') -Raw) -replace "`r?`n", '') -eq 'original')
check 'restore existing: b.txt restored' (Test-Path (Join-Path $mutated 'b.txt'))
check 'restore existing: c.txt (mutation-added) gone' (-not (Test-Path (Join-Path $mutated 'c.txt')))

# ---- Test 4: Restore for Existed=false removes the directory if it was created ----
# The correct first-install model: the directory is ABSENT at snapshot time
# (Existed=false), the mutation then creates it, and the restore must remove
# the newly-created directory.
$absent2 = Join-Path $testRoot 'absent2'
$snap4 = Save-DirPreState $absent2
check 'first-install pre: snapshot reports Existed=false' ($snap4.Existed -eq $false)
# Simulate the mutation creating the directory.
New-Item -ItemType Directory -Path $absent2 -Force | Out-Null
'created' | Set-Content (Join-Path $absent2 'x.txt')
Restore-DirPreState $absent2 $snap4
check 'restore absent: directory is removed' (-not (Test-Path $absent2))

# ---- Test 5: Restore for Existed=false is a no-op when the dir is still absent ----
$stillAbsent = Join-Path $testRoot 'still-absent'
Restore-DirPreState $stillAbsent @{ Existed = $false; SnapshotPath = $null }
check 'restore absent: no-op on a still-absent dir does not throw' ($true)
check 'restore absent: no-op on a still-absent dir does not create it' (-not (Test-Path $stillAbsent))

# ---- Test 6 (SRC-005 CORE-003): Restore for Existed=true with a missing
# SnapshotPath FAILS CLOSED ----
# Pre-fix this was codified as a no-op "restore lost", which let
# Invoke-TargetCommit print "target restored to its exact pre-operation state"
# after a rollback that restored NOTHING. Existed=true means the snapshot IS
# the rollback authority for a directory that was captured; when it is gone the
# restore must throw BEFORE touching the live directory.
$live = Join-Path $testRoot 'live'
New-Item -ItemType Directory -Path $live -Force | Out-Null
'survives' | Set-Content (Join-Path $live 'keep.txt')
$caughtLost = $null
try { Restore-DirPreState $live @{ Existed = $true; SnapshotPath = 'C:\does-not-exist' } } catch { $caughtLost = $_.Exception.Message }
check 'restore lost: throws on a missing authoritative snapshot' ($null -ne $caughtLost)
if ($caughtLost) { check 'restore lost: the message refuses an unverifiable restore' ($caughtLost -match 'refusing to restore an unverifiable') }
check 'restore lost: live dir untouched' (Test-Path $live)
check 'restore lost: live content untouched' (Test-Path (Join-Path $live 'keep.txt'))

# ---- Test 7: First-install scenario end-to-end ----
$first = Join-Path $testRoot 'first-install'
$snap7 = Save-DirPreState $first
check 'first-install: snapshot says Existed=false' ($snap7.Existed -eq $false)
# Simulate Apply: create the directory as part of the mutation.
New-Item -ItemType Directory -Path $first -Force | Out-Null
'theming' | Set-Content (Join-Path $first 'app.css')
# Simulate a manifest commit failure: invoke Restore and check the state.
Restore-DirPreState $first $snap7
check 'first-install: directory removed after Restore' (-not (Test-Path $first))

# ---- Test 8: Existing-dir scenario end-to-end ----
$existing2 = Join-Path $testRoot 'existing2'
New-Item -ItemType Directory -Path $existing2 -Force | Out-Null
'orig' | Set-Content (Join-Path $existing2 'data.txt')
$snap8 = Save-DirPreState $existing2
# Simulate Apply: write a theming file.
'theming' | Set-Content (Join-Path $existing2 'theme.css')
Remove-Item (Join-Path $existing2 'data.txt') -Force
Restore-DirPreState $existing2 $snap8
check 'existing-dir: data.txt restored' (Test-Path (Join-Path $existing2 'data.txt'))
check 'existing-dir: data.txt content restored byte-exact' (((Get-Content (Join-Path $existing2 'data.txt') -Raw) -replace "`r?`n", '') -eq 'orig')
check 'existing-dir: theme.css (mutation) gone' (-not (Test-Path (Join-Path $existing2 'theme.css')))

# ---- Test 9: Snapshot directory is cleaned up after Restore ----
# Already verified inline above -- verify on a fresh fixture.
$ex9 = Join-Path $testRoot 'ex9'
New-Item -ItemType Directory -Path $ex9 -Force | Out-Null
$pre9 = Save-DirPreState $ex9
check 'snapshot cleanup: SnapshotPath exists after Save' (Test-Path $pre9.SnapshotPath)
Restore-DirPreState $ex9 $pre9
check 'snapshot cleanup: SnapshotPath removed after Restore' (-not (Test-Path $pre9.SnapshotPath))

# ---- Test 10: every Save call returns a hashtable (no nullable contract remains) ----
$absent10 = Join-Path $testRoot 'absent10'
$snap10a = Save-DirPreState $absent10
check 'contract: Save on absent returns a hashtable' ($snap10a -is [hashtable])
$present10 = Join-Path $testRoot 'present10'
New-Item -ItemType Directory -Path $present10 -Force | Out-Null
$snap10b = Save-DirPreState $present10
check 'contract: Save on present returns a hashtable' ($snap10b -is [hashtable])
if ($snap10b.SnapshotPath -and (Test-Path $snap10b.SnapshotPath)) { Remove-Item $snap10b.SnapshotPath -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Test 11 (W2-001): Restore refuses a raw string snapshot ----
# Pre-fix the ElectronStateSnapshot path here passed a raw path string. Restore
# coerced it to @{Existed=$false}, the helper entered the absent-prestate
# branch, and the relocated resources\app directory was DELETED on a failed
# rollback instead of being restored byte-exactly. The fix rejects any
# non-structured input before touching the live directory.
$strDir = Join-Path $testRoot 'str-restore'
New-Item -ItemType Directory -Path $strDir -Force | Out-Null
'live' | Set-Content (Join-Path $strDir 'live.txt')
$caught = $null
try { Restore-DirPreState $strDir $strDir } catch { $caught = $_.Exception.Message }
check 'W2-001: raw string snapshot throws' ($null -ne $caught)
check 'W2-001: live dir untouched after malformed restore' (Test-Path $strDir)
check 'W2-001: live content untouched after malformed restore' (Test-Path (Join-Path $strDir 'live.txt'))

# ---- Test 12 (W2-001): Restore refuses a hashtable missing required fields ----
$badSnapDir = Join-Path $testRoot 'bad-hash-restore'
New-Item -ItemType Directory -Path $badSnapDir -Force | Out-Null
'live' | Set-Content (Join-Path $badSnapDir 'live.txt')
$caught2 = $null
try { Restore-DirPreState $badSnapDir @{ Foo = 'bar' } } catch { $caught2 = $_.Exception.Message }
check 'W2-001: hashtable without Existed/SnapshotPath throws' ($null -ne $caught2)
check 'W2-001: live dir untouched when snapshot lacks required fields' (Test-Path $badSnapDir)

# ---- Test 13 (W2-002): restore failure must never destroy the live directory ----
# Pre-fix the helper deleted the live dir BEFORE materialising the restored
# copy, so a failure anywhere between "delete live" and "rename tmp into
# place" destroyed the user's only copy. The two-phase swap retires the live
# dir to a recovery sibling instead of deleting it. We inject a failure at the
# retire step by holding an exclusive lock on a file inside the live dir: the
# retire rename cannot proceed, the helper must throw, and the original
# directory must survive byte-identical.
$swapDir = Join-Path $testRoot 'swap-fail'
New-Item -ItemType Directory -Path $swapDir -Force | Out-Null
'orig' | Set-Content (Join-Path $swapDir 'orig.txt')
$snapSwap = Save-DirPreState $swapDir
'CHANGED' | Set-Content (Join-Path $swapDir 'orig.txt')
$stream = $null
try {
    $stream = [System.IO.File]::Open((Join-Path $swapDir 'orig.txt'), 'Open', 'Read', 'None')
    $swapErr = $null
    try { Restore-DirPreState $swapDir $snapSwap } catch { $swapErr = $_.Exception.Message }
    check 'W2-002: retire failure throws' ($null -ne $swapErr)
    if ($swapErr) {
        check 'W2-002: retire failure message reports INCOMPLETE' ($swapErr -match 'INCOMPLETE')
    }
} finally {
    if ($stream) { $stream.Dispose() }
}
# The live directory must still hold the ORIGINAL content untouched.
check 'W2-002: live dir survives a failed restore' (Test-Path $swapDir)
check 'W2-002: live content survives a failed restore' (Test-Path (Join-Path $swapDir 'orig.txt'))
$content13 = (Get-Content (Join-Path $swapDir 'orig.txt') -Raw) -replace "`r?`n", ''
check 'W2-002: live content byte-identical after failed restore' ($content13 -eq 'CHANGED')
# Clean up retired siblings so they do not pollute other fixtures.
Get-ChildItem $testRoot -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.wintage-*' } |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Test 14 (W2-002): successful swap retires the original cleanly ----
$swapOk = Join-Path $testRoot 'swap-ok'
New-Item -ItemType Directory -Path $swapOk -Force | Out-Null
'orig' | Set-Content (Join-Path $swapOk 'orig.txt')
$snapOk = Save-DirPreState $swapOk
'CHANGED' | Set-Content (Join-Path $swapOk 'orig.txt')
Restore-DirPreState $swapOk $snapOk
check 'W2-002: successful swap leaves original content restored' (((Get-Content (Join-Path $swapOk 'orig.txt') -Raw) -replace "`r?`n", '') -eq 'orig')
check 'W2-002: no .wintage-retired leftovers after successful swap' (-not (Get-ChildItem $testRoot -Force -Directory | Where-Object { $_.Name -like '.wintage-retired-*' }))

# ---- Test 15 (W2-002): snapshot directory is consumed once the swap is known good ----
$snapConsume = Join-Path $testRoot 'consume'
New-Item -ItemType Directory -Path $snapConsume -Force | Out-Null
$preConsume = Save-DirPreState $snapConsume
Restore-DirPreState $snapConsume $preConsume
check 'W2-002: snapshot directory removed after successful restore' (-not (Test-Path $preConsume.SnapshotPath))

# ---- Test 16 (SRC-005 CORE-003): a FAILED restore preserves the authoritative
# snapshot ----
# Pre-fix the unconditional finally deleted the snapshot even when the swap
# threw, turning a recoverable failure into data loss: the very bytes the
# rollback needed were gone. Now the snapshot is consumed ONLY on a known-good
# restore, so a materialisation failure must leave it intact and named.
$keepDir = Join-Path $testRoot 'snap-keep'
New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
'orig' | Set-Content (Join-Path $keepDir 'orig.txt')
$snapKeep = Save-DirPreState $keepDir
$snapKeepPath = $snapKeep.SnapshotPath
check 'snapshot-preserved: snapshot exists before restore' (Test-Path $snapKeepPath)
# Inject a failure at the materialise step: make the snapshot unreadable by
# removing it between Save and Restore, so the swap throws in Copy-Item.
$keepStream = $null
try {
    # Hold an exclusive lock on a file inside the LIVE dir so the RETIRE rename
    # fails (the swap throws after materialise succeeded). The snapshot must
    # survive this INCOMPLETE path.
    $keepStream = [System.IO.File]::Open((Join-Path $keepDir 'orig.txt'), 'Open', 'Read', 'None')
    $keepErr = $null
    try { Restore-DirPreState $keepDir $snapKeep } catch { $keepErr = $_.Exception.Message }
    check 'snapshot-preserved: retire failure throws INCOMPLETE' ($null -ne $keepErr -and $keepErr -match 'INCOMPLETE')
} finally {
    if ($keepStream) { $keepStream.Dispose() }
}
# The authoritative snapshot must still exist and hold the original bytes.
check 'snapshot-preserved: snapshot survives the failed restore' (Test-Path $snapKeepPath)
check 'snapshot-preserved: snapshot content is byte-exact' ((Get-Content (Join-Path $snapKeepPath 'orig.txt') -Raw) -replace "`r?`n", '' -eq 'orig')
if ($snapKeepPath -and (Test-Path $snapKeepPath)) { Remove-Item $snapKeepPath -Recurse -Force -ErrorAction SilentlyContinue }

Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
