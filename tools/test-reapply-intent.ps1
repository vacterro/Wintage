# SRC-006:R005 -- Reapply intent revalidation under the target lock.
#
# DEFECT: the -Reapply parent plans work from a manifest snapshot, then a
# child process re-does the work after acquiring the target mutation lock.
# The lock serializes the MUTATION, not the INTENT: a Revert or an explicit
# palette change that lands between the parent's read and the child's lock
# was blindly overwritten by the stale plan.
#
# CONTRACT under test:
#  - The parent stamps every Reapply child with an intent fingerprint of the
#    manifest entry it planned from (palette, path, appVersion, payloadVersion,
#    applied, canonical sorted item set).
#  - The child re-computes the fingerprint from the LIVE manifest UNDER the
#    target lock. A missing or changed entry means ZERO target mutation, ZERO
#    recovery mutation, ZERO manifest mutation, reported through the dedicated
#    STALE exit code ($REAPPLY_STALE_EXIT = 3); the -Reapply parent maps that
#    to SKIPPED and the overall run still exits 0. The child NEVER reports a
#    stale skip as a re-apply and the parent never books one as a mutation.
#  - A corrupt manifest still fails closed (pre-existing P0#1 gate, exit != 0
#    and != 3).
#  - Sibling targets gate independently, and a current-intent child must
#    PROVABLY run (the fixture tampers the sibling first, so a no-op child
#    cannot pass).
#  - Explicit custom-path overrides (-NotepadPlusPlusPath/-Cinema4DPath) reach
#    the child, so the parent never validates one path while the child mutates
#    another.
#
# Determinism: no fixture decides correctness by sleeping. The low-level race
# parks the child on a held target lock; the integration races use the
# TEST-ONLY parent seam (WINTAGE_TEST_REAPPLY_PARENT_SEAM) that pauses the
# -Reapply parent between planning a target and dispatching its child, so a
# REAL install.ps1 Apply/Revert can complete inside the window.
#
# Red controls (-RedControl A|B|C): run the suite against a deliberately
# broken installer copy and REQUIRE the expected assertions to fail.
#   A: child-side intent revalidation disabled -> the real Revert race fails.
#   B: pre-fix blind parent reporting restored (every exit-0 child is
#      "re-applied successfully", a stale child reads as FAILED) -> the
#      reporting fixtures fail.
#   C: the current-intent sibling child replaced by a no-op -> the sibling
#      fixture fails.
# A red control exits 0 only when its critical assertions actually went red;
# a green run against a broken copy exits 1 (the test would be blind).

[CmdletBinding()]
param(
    [switch]$List,
    [string]$InstallerPath,
    [ValidateSet('', 'A', 'B', 'C')]
    [string]$RedControl = '',
    [string]$Only = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = if ($InstallerPath) { $InstallerPath } else { Join-Path $root 'desktop\install.ps1' }
$common = Join-Path $root 'desktop\modules\common.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

function Bytes-Differ($a, $b) {
    # NEVER use `-ne` to compare byte arrays: on an array LHS it is a FILTER
    # (it selects differing elements), so any single differing byte makes the
    # whole expression truthy - the comparison could never prove identity OR
    # difference. Red control C exists because exactly that tautology stayed
    # green while a no-op child left the target damaged.
    @(Compare-Object @($a) @($b)).Count -gt 0
}

if ($List) {
    Write-Host "test-reapply-intent.ps1 (11 fixtures covering the 9-case R005 matrix):"
    Write-Host "  case 1  current intent: unhealthy target, token matches, child REALLY repairs"
    Write-Host "  case 2  entry removed: stale child exits 3 (STALE), zero mutation anywhere"
    Write-Host "  case 3  palette changed: stale A child skips, B remains byte/state correct"
    Write-Host "  case 4  corrupt manifest: child fails closed (nonzero, not 3), no mutation"
    Write-Host "  case 5  LOW-LEVEL race: planned Reapply vs manifest entry removal, child parked on the target lock"
    Write-Host "  case 6  sibling independence: A stale skips while damaged B is provably repaired"
    Write-Host "  case 7  structured parent reporting: APPLIED / SKIPPED / FAILED each reported truthfully"
    Write-Host "  case 8  quiet mode: a stale skip is no failure; real failures stay observable"
    Write-Host "  case 9  custom path forwarding: -NotepadPlusPlusPath/-Cinema4DPath reach the child"
    Write-Host "  case 10 REAL Revert race: seam-paused Reapply vs a real install.ps1 -Revert"
    Write-Host "  case 11 REAL palette race: seam-paused Reapply (A) vs a real explicit Apply (B)"
    Write-Host "Red controls: -RedControl A (no child revalidation), B (blind parent reporting), C (no-op sibling child)"
    exit 0
}

# ---- Red-control setup: build the broken installer copy BEFORE anything runs ----
$setupInstaller = $installer
$fixtureInstaller = $installer
$redCritical = @()
$redPatchCopies = @()
if ($RedControl) {
    $patch = ''
    $patchWith = ''
    switch ($RedControl) {
        'A' {
            # Disable ONLY the child-side intent revalidation gate.
            $patch = '        if ($ExpectedIntent) {'
            $patchWith = "        if (`$false) { # RED CONTROL A: child-side intent revalidation disabled"
            $redCritical = @(
                'case-5 race: tampered target NOT re-themed by the stale child',
                'case-10 realrevert: target remains reverted (pristine restored)'
            )
            $Only = '5,10'
        }
        'B' {
            # Restore the pre-fix parent: no STALE mapping, every exit-0 child
            # reported as "re-applied successfully", a stale child read as FAILED.
            $patch = 'elseif ($childCode -eq $REAPPLY_STALE_EXIT) {'
            $patchWith = "elseif (`$false) { # RED CONTROL B: pre-fix blind parent reporting restored"
            $redCritical = @(
                'case-5 race: parent exits 0 (stale child skipped, not failed)',
                'case-7 report: stale-skip run exits 0'
            )
            $Only = '5,7'
        }
        'C' {
            # Replace the current-intent cinema4d child with a no-op. SETUP keeps
            # using the real installer; only the fixture's child calls hit the copy.
            $patch = "    if (`$name -eq 'cinema4d') { Invoke-Cinema4D -DoRevert:`$Revert -PaletteSlug `$Palette; continue }"
            $patchWith = "    if (`$name -eq 'cinema4d') { continue } # RED CONTROL C: sibling child replaced by a no-op"
            $redCritical = @(
                'case-6 siblings: cinema4d repaired (repaired marker matches goldendefault)'
            )
            $Only = '6'
        }
    }
    $src = [System.IO.File]::ReadAllText($setupInstaller)
    $count = ([regex]::Matches($src, [regex]::Escape($patch))).Count
    if ($count -ne 1) { throw "red control $RedControl`: anchor matched $count time(s) (expected exactly 1) - the installer shape changed; fix the control anchor." }
    $patched = $src.Replace($patch, $patchWith)
    $copyPath = Join-Path $root "desktop\_red-control-$RedControl.ps1"
    [System.IO.File]::WriteAllText($copyPath, $patched, $utf8)
    $redPatchCopies += $copyPath
    $fixtureInstaller = $copyPath
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-reapply-intent-" + [guid]::NewGuid().ToString('N'))
$appData = Join-Path $testRoot 'appdata'
$nppDir = Join-Path $testRoot 'notepadplusplus'
$nppThemes = Join-Path $nppDir 'themes'
$nppTheme = Join-Path $nppThemes 'Wintage.xml'
$nppMarker = Join-Path $nppThemes '.wintage-npp-palette'

$c4dDir = Join-Path $testRoot 'cinema4d'
$c4dSchemes = Join-Path $c4dDir 'resource\modules\c4d_base\schemes'
$c4dScheme = Join-Path $c4dSchemes 'Wintage'
$c4dCol = Join-Path $c4dScheme 'wintage.col'
$c4dRes = Join-Path $c4dScheme 'wintage.res'
$c4dMarker = Join-Path $c4dScheme '.wintage-c4d-palette'

New-Item -ItemType Directory -Path $appData, $nppThemes, $c4dSchemes -Force | Out-Null

$prevAppData = $env:WINTAGE_APPDATA
$env:WINTAGE_APPDATA = $appData

$manifestPath = Join-Path $appData 'installed.json'

function Run-Installer([string[]]$argsList, [string]$which = 'fixture') {
    $exe = if ($which -eq 'setup') { $script:setupInstaller } else { $script:fixtureInstaller }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $exe @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}

function Read-TestManifest {
    if (-not (Test-Path $manifestPath)) { return $null }
    $o = [System.IO.File]::ReadAllText($manifestPath, $utf8) | ConvertFrom-Json
    $ht = @{}
    foreach ($p in $o.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    return $ht
}

function Write-TestManifest($ht) {
    [System.IO.File]::WriteAllText($manifestPath, (($ht | ConvertTo-Json -Depth 5) + "`n"), $utf8)
}

function Reset-Fixture {
    if (Test-Path $appData) { Remove-Item $appData -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $nppDir) { Remove-Item $nppDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $c4dDir) { Remove-Item $c4dDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $appData, $nppThemes, $c4dSchemes -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $appData 'paths.json'), (@{ notepadplusplus = $nppDir; cinema4d = $c4dDir } | ConvertTo-Json), $utf8)
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault') 'setup'
    if ($r.Code -ne 0) { throw "fixture apply (notepadplusplus) failed: $($r.Out)" }
    $r = Run-Installer @('-Target', 'cinema4d', '-Palette', 'goldendefault') 'setup'
    if ($r.Code -ne 0) { throw "fixture apply (cinema4d) failed: $($r.Out)" }
}

function Get-EntryToken([string]$target) {
    . $common
    $m = Read-Manifest
    $entry = if ($m.ContainsKey($target)) { $m[$target] } else { $null }
    return Get-ReapplyIntentToken $entry
}

function Tamper-NotepadPlusPlus {
    [System.IO.File]::WriteAllText($nppMarker, "tampered`r`n", $utf8)
}

function Break-NotepadPlusPlusShape {
    Remove-Item $nppThemes -Recurse -Force -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllText($nppThemes, "blocking file", $utf8)
}

function Tamper-Cinema4D {
    [System.IO.File]::WriteAllText($c4dMarker, "tampered`r`n", $utf8)
}

function Start-ReapplyParent([string]$extraArgs = '') {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:fixtureInstaller + '" -Reapply' + $extraArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Wait-ChildWithToken($parent, [string]$token, [int]$seconds = 60) {
    # Deterministic: poll until the child process carrying THIS intent token
    # exists (it is parked on the held target lock), or the parent dies.
    for ($i = 0; $i -lt ($seconds * 10); $i++) {
        if ($parent.HasExited) { return $false }
        $hit = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($token) }
        if ($hit) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Wait-SeamFile([string]$path, $parent, [int]$seconds = 90) {
    for ($i = 0; $i -lt ($seconds * 10); $i++) {
        if ($parent.HasExited) { return $false }
        if (Test-Path $path) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Finish-Parent($parent, [int]$seconds = 180) {
    if (-not $parent.WaitForExit($seconds * 1000)) { $parent.Kill(); throw 'reapply parent did not finish in time' }
    return $parent.StandardOutput.ReadToEnd() + $parent.StandardError.ReadToEnd()
}

function Select-Fixture([string]$id) {
    return (-not $script:Only -or @($script:Only -split ',') -contains $id)
}

# . $common needs the same script-scope variables install.ps1 provides
# ($script:Utf8NoBom is initialized by install.ps1, not by common.ps1).
$WintageAppData = $appData
$ManifestPath = $manifestPath
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {

# ---- case 1: CURRENT INTENT -- unhealthy target, matching token, REAL repair ----
if (Select-Fixture '1') {
    Reset-Fixture
    $tok1 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-ExpectedIntent', $tok1)
    $repaired1 = [System.IO.File]::ReadAllText($nppMarker, $utf8).Trim()
    check 'case-1 current: child exits 0 (APPLIED)' ($r.Code -eq 0)
    check 'case-1 current: no stale-skip reported' ($r.Out -notmatch 'stale Reapply intent skipped')
    check 'case-1 current: the expected goldendefault palette marker is restored' ($repaired1 -eq 'goldendefault')
    check 'case-1 current: manifest entry still present with the applied palette' (((Read-TestManifest)['notepadplusplus'].palette) -eq 'goldendefault')
}

# ---- case 2: ENTRY REMOVED -- stale child skips with zero mutation ----
if (Select-Fixture '2') {
    Reset-Fixture
    $tok2 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    $m = Read-TestManifest
    $m.Remove('notepadplusplus')   # the end state a concurrent Revert leaves behind
    Write-TestManifest $m
    $before2 = [System.IO.File]::ReadAllText($nppMarker, $utf8)
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-ExpectedIntent', $tok2)
    check 'case-2 removed: child exits 3 (the dedicated STALE_SKIPPED outcome)' ($r.Code -eq 3)
    check 'case-2 removed: stale skip reported' ($r.Out -match 'stale Reapply intent skipped')
    check 'case-2 removed: target bytes untouched' ([System.IO.File]::ReadAllText($nppMarker, $utf8) -eq $before2)
    check 'case-2 removed: manifest still has no entry (zero manifest mutation)' (-not (Read-TestManifest).ContainsKey('notepadplusplus'))
}

# ---- case 3: PALETTE CHANGED -- stale A child skips, B remains correct ----
if (Select-Fixture '3') {
    Reset-Fixture
    $tok3 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    $m = Read-TestManifest
    $m['notepadplusplus'].palette = 'dracula'   # an explicit user change to palette B
    Write-TestManifest $m
    $before3 = [System.IO.File]::ReadAllText($nppMarker, $utf8)
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-ExpectedIntent', $tok3)
    check 'case-3 palette-B: child exits 3 (STALE_SKIPPED)' ($r.Code -eq 3)
    check 'case-3 palette-B: stale skip reported' ($r.Out -match 'stale Reapply intent skipped')
    check 'case-3 palette-B: manifest still records palette B' (((Read-TestManifest)['notepadplusplus'].palette) -eq 'dracula')
    check 'case-3 palette-B: target not re-themed behind the user''s back' ([System.IO.File]::ReadAllText($nppMarker, $utf8) -eq $before3)
}

# ---- case 4: CORRUPT MANIFEST -- fail closed, nonzero, no mutation ----
if (Select-Fixture '4') {
    Reset-Fixture
    $tok4 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    [System.IO.File]::WriteAllText($manifestPath, '{ this is not json', $utf8)
    $before4 = [System.IO.File]::ReadAllText($nppMarker, $utf8)
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-ExpectedIntent', $tok4)
    check 'case-4 corrupt: child exits NONZERO (fail closed)' ($r.Code -ne 0)
    check 'case-4 corrupt: a corrupt manifest is a FAILURE, never a stale skip (not 3)' ($r.Code -ne 3)
    check 'case-4 corrupt: target untouched' ([System.IO.File]::ReadAllText($nppMarker, $utf8) -eq $before4)
    check 'case-4 corrupt: manifest not overwritten' ([System.IO.File]::ReadAllText($manifestPath, $utf8) -eq '{ this is not json')
}

# ---- case 5: LOW-LEVEL RACE -- planned Reapply vs concurrent manifest entry removal ----
# Synchronization: the TEST holds the notepadplusplus target lock BEFORE the parent
# starts, so the parent plans (health fires on the tampered file) and its
# child then BLOCKS on the lock. Waiting for the child process to exist is
# the deterministic seam -- no fixed sleeps. While the child is blocked the
# "concurrent Revert" completes (the manifest entry disappears), then the
# lock is released and the child must skip.
if (Select-Fixture '5') {
    Reset-Fixture
    $tok5 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    . $common
    $heldLock = Enter-TargetLock 'notepadplusplus'
    $parent = Start-ReapplyParent
    try {
        $childSeen = Wait-ChildWithToken $parent $tok5
        check 'case-5 race: reapply child spawned and is parked on the target lock' ($childSeen)
        if ($childSeen) {
            # The concurrent Revert completes while the child waits for the lock.
            $m = Read-TestManifest
            $m.Remove('notepadplusplus')
            Write-TestManifest $m
        }
    } finally {
        Exit-TargetLock $heldLock
    }
    $parentText = Finish-Parent $parent
    if ($parent.ExitCode -ne 0) { Write-Host "---- parent output (failure diagnostic) ----`n$parentText" -ForegroundColor Yellow }
    check 'case-5 race: parent exits 0 (stale child skipped, not failed)' ($parent.ExitCode -eq 0)
    check 'case-5 race: parent reports the target as SKIPPED, not re-applied' (($parentText -match 'notepadplusplus: SKIPPED') -and ($parentText -notmatch 'notepadplusplus: re-applied successfully'))
    check 'case-5 race: tampered target NOT re-themed by the stale child' ([System.IO.File]::ReadAllText($nppMarker, $utf8).Trim() -eq 'tampered')
    check 'case-5 race: manifest still has no notepadplusplus entry' (-not (Read-TestManifest).ContainsKey('notepadplusplus'))
}

# ---- case 6: SIBLING INDEPENDENCE -- A stale skips while damaged B is REALLY repaired ----
# The cinema4d sibling is deliberately damaged FIRST, so the assertion can
# only stay green if the current-intent child actually ran and repaired it:
# a no-op child leaves the damaged bytes in place and fails the fixture
# (proven by red control C).
if (Select-Fixture '6') {
    Reset-Fixture
    $tokNpp = Get-EntryToken 'notepadplusplus'
    $tokC4d = Get-EntryToken 'cinema4d'
    Tamper-NotepadPlusPlus
    # Stale the notepadplusplus intent only: its manifest entry changes to palette B.
    $m = Read-TestManifest
    $m['notepadplusplus'].palette = 'dracula'
    Write-TestManifest $m
    $nppMarkerBefore = [System.IO.File]::ReadAllText($nppMarker, $utf8)
    Tamper-Cinema4D
    $rNpp = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-ExpectedIntent', $tokNpp)
    $rC4d = Run-Installer @('-Target', 'cinema4d', '-Palette', 'goldendefault', '-ExpectedIntent', $tokC4d)
    $c4dMarkerRepaired = [System.IO.File]::ReadAllText($c4dMarker, $utf8).Trim()
    check 'case-6 siblings: stale notepadplusplus child reported the skip (exit 3)' (($rNpp.Code -eq 3) -and ($rNpp.Out -match 'stale Reapply intent skipped'))
    check 'case-6 siblings: stale notepadplusplus target untouched' ([System.IO.File]::ReadAllText($nppMarker, $utf8) -eq $nppMarkerBefore)
    check 'case-6 siblings: current-intent cinema4d child exits 0 (APPLIED)' ($rC4d.Code -eq 0)
    check 'case-6 siblings: cinema4d repaired (repaired marker matches goldendefault)' ($c4dMarkerRepaired -eq 'goldendefault')
}

# ---- case 7: STRUCTURED PARENT REPORTING -- APPLIED / STALE_SKIPPED / FAILED ----
if (Select-Fixture '7') {
    # Run A: one parked-stale target (notepadplusplus) plus one really-applied
    # sibling (cinema4d), through ONE real -Reapply parent run.
    Reset-Fixture
    $tok7 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    Tamper-Cinema4D
    . $common
    $heldLock7 = Enter-TargetLock 'notepadplusplus'
    $parent7 = Start-ReapplyParent
    try {
        $childSeen7 = Wait-ChildWithToken $parent7 $tok7
        check 'case-7 report: stale child spawned and parked' ($childSeen7)
        if ($childSeen7) {
            # A palette change wins the race while the child is parked.
            $m = Read-TestManifest
            $m['notepadplusplus'].palette = 'dracula'
            Write-TestManifest $m
        }
    } finally {
        Exit-TargetLock $heldLock7
    }
    $text7 = Finish-Parent $parent7
    check 'case-7 report: stale-skip run exits 0' ($parent7.ExitCode -eq 0)
    check 'case-7 report: APPLIED is reported as applied (cinema4d)' ($text7 -match 'cinema4d: re-applied successfully')
    check 'case-7 report: STALE_SKIPPED is reported as skipped (notepadplusplus)' ($text7 -match 'notepadplusplus: SKIPPED')
    check 'case-7 report: SKIPPED is NEVER reported as re-applied successfully' ($text7 -notmatch 'notepadplusplus: re-applied successfully')
    check 'case-7 report: the applied sibling really runs (goldendefault on cinema4d)' ([System.IO.File]::ReadAllText($c4dMarker, $utf8).Trim() -eq 'goldendefault')
    check 'case-7 report: the stale target keeps palette B in the manifest' (((Read-TestManifest)['notepadplusplus'].palette) -eq 'dracula')

    # Run B: a genuinely failing child must stay a failure.
    Reset-Fixture
    Break-NotepadPlusPlusShape
    $rFail7 = Run-Installer @('-Reapply') 'fixture'
    check 'case-7 report: FAILED child makes the run exit nonzero' ($rFail7.Code -ne 0)
    check 'case-7 report: FAILED is reported as a failure' (($rFail7.Out -match 'notepadplusplus: FAILED') -and ($rFail7.Out -match 'Reapply incomplete'))
}

# ---- case 8: QUIET MODE -- a stale skip is no failure; failures stay visible ----
if (Select-Fixture '8') {
    Reset-Fixture
    $tok8 = Get-EntryToken 'notepadplusplus'
    Tamper-NotepadPlusPlus
    . $common
    $heldLock8 = Enter-TargetLock 'notepadplusplus'
    $parent8 = Start-ReapplyParent ' -Quiet'
    try {
        $childSeen8 = Wait-ChildWithToken $parent8 $tok8
        check 'case-8 quiet: the stale child spawned and parked' ($childSeen8)
        if ($childSeen8) {
            $m = Read-TestManifest
            $m.Remove('notepadplusplus')
            Write-TestManifest $m
        }
    } finally {
        Exit-TargetLock $heldLock8
    }
    $text8 = Finish-Parent $parent8
    check 'case-8 quiet: a stale skip creates NO false failure (exit 0)' ($parent8.ExitCode -eq 0)
    check 'case-8 quiet: no FAILED noise for the skipped target' (-not ($text8 -match 'FAILED'))

    Reset-Fixture
    Break-NotepadPlusPlusShape
    $rQ = Run-Installer @('-Reapply', '-Quiet')
    check 'case-8 quiet: a real failure still exits nonzero under -Quiet' ($rQ.Code -ne 0)
    check 'case-8 quiet: a real failure remains OBSERVABLE under -Quiet' ($rQ.Out -match 'FAILED')
}

# ---- case 9: CUSTOM PATH FORWARDING -- the child gets the parent's path authority ----
# The decoy paths live in paths.json; the EXPLICIT parameter is the parent's
# authority. If the child lost the explicit override it would fall back to the
# decoy: the explicit target would stay broken and the decoy would get themed
# - exactly the validate-one-path/mutate-another defect this case forbids.
if (Select-Fixture '9') {
    Reset-Fixture
    $nppExplicit = Join-Path $testRoot 'npp-explicit'
    $nppDecoy = Join-Path $testRoot 'npp-decoy'
    $c4dExplicit = Join-Path $testRoot 'c4d-explicit'
    $c4dDecoy = Join-Path $testRoot 'c4d-decoy'
    foreach ($d in @($nppExplicit, (Join-Path $nppExplicit 'themes'), $nppDecoy, (Join-Path $nppDecoy 'themes'),
                    (Join-Path $c4dExplicit 'resource\modules\c4d_base\schemes'),
                    (Join-Path $c4dDecoy 'resource\modules\c4d_base\schemes'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    # Notepad++: apply with the EXPLICIT path, damage the result, reapply.
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-NotepadPlusPlusPath', $nppExplicit)
    check 'case-9 npp: apply with the explicit path exits 0' ($r.Code -eq 0)
    check 'case-9 npp: apply recorded the EXPLICIT path in the manifest' (((Read-TestManifest)['notepadplusplus'].path) -eq $nppExplicit)
    Remove-Item (Join-Path $nppExplicit 'themes\Wintage.xml') -Force
    $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-NotepadPlusPlusPath', $nppExplicit, '-ExpectedIntent', (Get-EntryToken 'notepadplusplus'))
    check 'case-9 npp: reapply with the explicit path exits 0' ($r.Code -eq 0)
    check 'case-9 npp: the child repaired the EXPLICIT path (theme reinstated)' (Test-Path (Join-Path $nppExplicit 'themes\Wintage.xml'))
    check 'case-9 npp: the child did NOT mutate the decoy path instead' (-not (Test-Path (Join-Path $nppDecoy 'themes\Wintage.xml')))
    check 'case-9 npp: the manifest still names the EXPLICIT path' (((Read-TestManifest)['notepadplusplus'].path) -eq $nppExplicit)
    # Cinema 4D: same contract for the v1.35.0 target.
    $r = Run-Installer @('-Target', 'cinema4d', '-Palette', 'goldendefault', '-Cinema4DPath', $c4dExplicit)
    check 'case-9 c4d: apply with the explicit path exits 0' ($r.Code -eq 0)
    Remove-Item (Join-Path $c4dExplicit 'resource\modules\c4d_base\schemes\Wintage\wintage.col') -Force
    $r = Run-Installer @('-Target', 'cinema4d', '-Palette', 'goldendefault', '-Cinema4DPath', $c4dExplicit, '-ExpectedIntent', (Get-EntryToken 'cinema4d'))
    check 'case-9 c4d: reapply with the explicit path exits 0' ($r.Code -eq 0)
    check 'case-9 c4d: the child repaired the EXPLICIT path (scheme reinstated)' (Test-Path (Join-Path $c4dExplicit 'resource\modules\c4d_base\schemes\Wintage\wintage.col'))
    check 'case-9 c4d: the child did NOT mutate the decoy path instead' (-not (Test-Path (Join-Path $c4dDecoy 'resource\modules\c4d_base\schemes\Wintage\wintage.col')))
}

# ---- case 10: REAL REVERT RACE -- a real install.ps1 -Revert wins the plan->child race ----
# Integration seam: the parent plans the notepadplusplus child and PAUSES at the
# TEST-ONLY seam before dispatching it; the test then runs a REAL
# install.ps1 -Target notepadplusplus -Revert to completion, releases the seam, and
# the stale child must skip. Recovery lifecycle must match a normal Revert.
if (Select-Fixture '10') {
    Reset-Fixture
    Tamper-NotepadPlusPlus   # unhealthy, so the parent really plans a child
    $seamDir10 = Join-Path $testRoot 'seam-revert'
    New-Item -ItemType Directory -Force -Path $seamDir10 | Out-Null
    $env:WINTAGE_TEST_REAPPLY_PARENT_SEAM = "notepadplusplus|$seamDir10"
    try {
        $parent10 = Start-ReapplyParent
        $planned = Wait-SeamFile (Join-Path $seamDir10 'planned') $parent10
        check 'case-10 realrevert: the parent planned the target and paused at the seam' ($planned)
        if ($planned) {
            # The REAL Revert runs to completion inside the plan->child window.
            $r = Run-Installer @('-Target', 'notepadplusplus', '-Revert')
            check 'case-10 realrevert: the REAL Revert completed normally (exit 0)' ($r.Code -eq 0)
            Set-Content -LiteralPath (Join-Path $seamDir10 'resume') -Value 'go'
        }
        $text10 = Finish-Parent $parent10
        if ($parent10.ExitCode -ne 0) { Write-Host "---- parent output (failure diagnostic) ----`n$text10" -ForegroundColor Yellow }
        check 'case-10 realrevert: the stale Reapply parent exits 0' ($parent10.ExitCode -eq 0)
        check 'case-10 realrevert: the parent reported the target as SKIPPED' ($text10 -match 'notepadplusplus: SKIPPED')
        check 'case-10 realrevert: the parent NEVER reported re-applied successfully' ($text10 -notmatch 'notepadplusplus: re-applied successfully')
        check 'case-10 realrevert: target remains reverted (theme xml removed)' (-not (Test-Path $nppTheme))
        check 'case-10 realrevert: manifest entry remains absent' (-not (Read-TestManifest).ContainsKey('notepadplusplus'))
    } finally {
        $env:WINTAGE_TEST_REAPPLY_PARENT_SEAM = $null
    }
}

# ---- case 11: REAL PALETTE RACE -- a real explicit Apply to palette B wins ----
if (Select-Fixture '11') {
    Reset-Fixture
    $seamDir11 = Join-Path $testRoot 'seam-palette'
    New-Item -ItemType Directory -Force -Path $seamDir11 | Out-Null
    Tamper-NotepadPlusPlus
    $env:WINTAGE_TEST_REAPPLY_PARENT_SEAM = "notepadplusplus|$seamDir11"
    try {
        $parent11 = Start-ReapplyParent
        $planned = Wait-SeamFile (Join-Path $seamDir11 'planned') $parent11
        check 'case-11 palette: the parent planned the stale goldendefault child and paused' ($planned)
        if ($planned) {
            # The user explicitly applies palette B while the old plan is parked.
            $r = Run-Installer @('-Target', 'notepadplusplus', '-Palette', 'dracula')
            check 'case-11 palette: the explicit user Apply to palette B completed (exit 0)' ($r.Code -eq 0)
            Set-Content -LiteralPath (Join-Path $seamDir11 'resume') -Value 'go'
        }
        $text11 = Finish-Parent $parent11
        if ($parent11.ExitCode -ne 0) { Write-Host "---- parent output (failure diagnostic) ----`n$text11" -ForegroundColor Yellow }
        check 'case-11 palette: the stale Reapply parent exits 0' ($parent11.ExitCode -eq 0)
        check 'case-11 palette: the parent reported the target as SKIPPED' ($text11 -match 'notepadplusplus: SKIPPED')
        check 'case-11 palette: the parent NEVER reported re-applied successfully' ($text11 -notmatch 'notepadplusplus: re-applied successfully')
        $final11 = [System.IO.File]::ReadAllText($nppMarker, $utf8).Trim()
        check 'case-11 palette: the target remains palette B (dracula, not goldendefault)' ($final11 -eq 'dracula')
        check 'case-11 palette: the manifest remains palette B' (((Read-TestManifest)['notepadplusplus'].palette) -eq 'dracula')
    } finally {
        $env:WINTAGE_TEST_REAPPLY_PARENT_SEAM = $null
    }
}

} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    $env:WINTAGE_TEST_REAPPLY_PARENT_SEAM = $null
    foreach ($copy in $redPatchCopies) { Remove-Item $copy -Force -ErrorAction SilentlyContinue }
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($RedControl) {
    # Red-control verdict: the broken copy MUST fail, and the critical
    # assertions specifically must be among the failures. A green run here
    # means the fixture is blind to the defect it claims to test.
    $missing = @($redCritical | Where-Object { $_ -notin $script:failedLabels })
    if ($script:fail -eq 0 -or $missing.Count) {
        $why = if ($missing.Count) { "critical assertions stayed green: $($missing -join ' | ')" } else { "the broken copy passed everything" }
        Write-Host "RED CONTROL $RedControl NOT PROVEN: $($script:fail) assertion(s) failed - $why" -ForegroundColor Red
        exit 1
    }
    Write-Host "RED CONTROL $RedControl PROVEN: $($script:fail) assertion(s) failed against the broken copy (all critical assertions red)." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
