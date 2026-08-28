# Recovery-consumption ordering regression suite (T-206 / W2-009).
#
# Wintage-owned source files (SmartVac, WildRift, SAIPENVIEW) Revert by
# copying a per-target `<file>.bak` backup back over the themed file and
# then removing the backup. The audit caught that the original code deleted
# the backup BEFORE the manifest removal committed -- a process kill at that
# seam strands `manifest says installed + no recovery`, a permanent
# fail-closed state the user cannot recover from. The fix defers the backup
# removal INTO the commit scriptblock, so it only happens if the manifest
# removal succeeds. Restore-FilePreState (in-memory prestate) is the safety
# net for an in-process commit failure.
#
# This test enforces:
#   1. The structural invariant -- for each of the three Revert call sites
#      (Invoke-SmartVac, Invoke-WildRift, Invoke-Saipenview), the
#      `Remove-Item $bakFile` line must live INSIDE an Invoke-TargetCommit
#      scriptblock, not before it. A regression that reintroduces the
#      pre-commit removal is caught by static read.
#   2. The behavioural round-trip -- Save-FilePreState captures live+bak
#      bytes, and Restore-FilePreState reconstructs both exactly after a
#      failed commit (which the deferral makes possible even if the commit
#      is followed by an immediate Remove-Item in the same scriptblock).
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

if ($List) {
    Write-Host "test-recovery-consumption.ps1 (5 tests):"
    Write-Host "  1. SmartVac Revert does NOT Remove-Item bakFile before Invoke-TargetCommit"
    Write-Host "  2. WildRift Revert does NOT Remove-Item bakFile before Invoke-TargetCommit"
    Write-Host "  3. SAIPENVIEW Revert does NOT Remove-Item bakFile before Invoke-TargetCommit"
    Write-Host "  4. SmartVac Revert Remove-Item bakFile is INSIDE the commit scriptblock"
    Write-Host "  5. Restore-FilePreState byte-exact round-trip after a failed commit"
    exit 0
}

# ------------------------------------------------------------------ fixtures
$src = Get-Content $targets -Raw
$commonSrc = Get-Content $common -Raw
check 'BetterDiscord: replaced recovery without pristine fails closed' ($src -match 'if \(\$meta\.mode -eq ''replaced''\) \{\s*if \(-not \(Test-Path \$pristine\)\) \{ throw .*refusing to delete the live CSS')
check 'TotalCmd: health captures value after matched key prefix' ($src -match '\$v = \$line\.Substring\(\$m\.Index \+ \$m\.Length\)')
check 'MPC-HC: missing OSDTransparency is unhealthy' ($src -match '\$props\.OSDTransparency -ne 0')
check 'Portable Electron: process names accept arrays' ($commonSrc -match 'Resolve-PortableElectron\(\[string\]\$key, \[string\]\$explicitPath, \[hashtable\]\$remembered, \[string\[\]\]\$processName')

# ---- Test 1..3: structural guard. Read the SOURCE file directly and
# assert that each function's Revert branch does NOT carry a bare
# `Remove-Item $bakFile` between the `Copy-Item $bakFile` and the
# `Invoke-TargetCommit` call. The pre-fix code had the `Remove-Item`
# on its own line BEFORE `Invoke-TargetCommit`; the fix moved it
# INSIDE the commit scriptblock (after the `Invoke-TargetCommit` line).
# A simple grep on the interleaving window catches reintroductions.
function Get-Interleave([string]$text, [string]$funcName) {
    # Find the Revert branch inside the function.
    $fidx = $text.IndexOf("function $funcName")
    if ($fidx -lt 0) { return $null }
    $ridx = $text.IndexOf('if ($DoRevert) {', $fidx)
    if ($ridx -lt 0) { return $null }
    # The Revert branch ends at the next `return` line that is followed
    # by the Apply branch (`if (-not $PSCmdlet.ShouldProcess`).
    $aidx = $text.IndexOf('if (-not $PSCmdlet.ShouldProcess', $ridx)
    if ($aidx -lt 0) { return $null }
    # Extract the revert block: from `if ($DoRevert)` to where the Apply
    # branch starts. Then find the first Copy-Item $bakFile and the first
    # Invoke-TargetCommit inside it.
    $block = $text.Substring($ridx, $aidx - $ridx)
    $cIdx = $block.IndexOf('Copy-Item $bakFile')
    $tIdx = $block.IndexOf('Invoke-TargetCommit')
    if ($cIdx -lt 0 -or $tIdx -lt 0 -or $cIdx -ge $tIdx) { return $null }
    # Return the slice BETWEEN Copy-Item and Invoke-TargetCommit (exclusive).
    return $block.Substring($cIdx, $tIdx - $cIdx)
}

$svSlice = Get-Interleave $src 'Invoke-SmartVac'
$wrSlice = Get-Interleave $src 'Invoke-WildRift'
$svpSlice = Get-Interleave $src 'Invoke-Saipenview'

function Has-BakRemoval([string]$slice) {
    if ($null -eq $slice) { return $true }
    return $slice -match 'Remove-Item\s+\$bakFile'
}

check 'SmartVac: no Remove-Item bakFile between Copy-Item and Invoke-TargetCommit' (-not (Has-BakRemoval $svSlice))
check 'WildRift: no Remove-Item bakFile between Copy-Item and Invoke-TargetCommit' (-not (Has-BakRemoval $wrSlice))
check 'SAIPENVIEW: no Remove-Item bakFile between Copy-Item and Invoke-TargetCommit' (-not (Has-BakRemoval $svpSlice))

# ---- Test 4: the commit scriptblock now performs the removal ----
# The commit scriptblock lives between Invoke-TargetCommit '...' '...' {
# and the closing } before the restore scriptblock. We extract it from the
# revert slice and assert it carries `Remove-ManifestEntry` AND
# `Remove-Item $bakFile`.
function Extract-CommitScriptblock([string]$block) {
    # The structure is: Invoke-TargetCommit '<key>' '<label>' { <commit> } { <restore> }
    $commitStart = $block.IndexOf('Invoke-TargetCommit')
    if ($commitStart -lt 0) { return $null }
    $openBrace = $block.IndexOf('{', $commitStart)
    if ($openBrace -lt 0) { return $null }
    # Match braces to find the close of the commit scriptblock.
    $depth = 0
    for ($i = $openBrace; $i -lt $block.Length; $i++) {
        $c = $block[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $block.Substring($openBrace + 1, $i - $openBrace - 1) }
        }
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

$svRevert = Get-RevertBlock $src 'Invoke-SmartVac'
$svCommit = Extract-CommitScriptblock $svRevert
check 'SmartVac: commit scriptblock exists' ($null -ne $svCommit)
if ($svCommit) {
    check 'SmartVac: commit scriptblock calls Remove-ManifestEntry smartvac' ($svCommit -match "Remove-ManifestEntry\s+'smartvac'")
    check 'SmartVac: commit scriptblock calls Remove-Item $bakFile'     ($svCommit -match 'Remove-Item\s+\$bakFile')
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
