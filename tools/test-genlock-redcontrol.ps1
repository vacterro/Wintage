# Dedicated RedControl suite for W2-004 / SRC-007:R009.
#
# Drives the REAL tools/build-desktop.js and the REAL generation-lock.ps1 from
# mutated copies in isolated temp layouts and proves each regression gate
# reproduces its defect:
#   RED A -- the direct-Node production leak: releaseGenLock ran with no
#            acquisition token available, so a successful build left
#            build-generation.lock behind forever.
#   RED B -- the PowerShell malformed-release ownership hole: a stale release
#            whose MetadataWritten=true deleted a current malformed replacement
#            it could not positively own.
#   RED C -- age-only stealing: a live holder lost its lock to an age
#            threshold alone (the R009 liveness contract).
#
# The mutated Node builder is written to tools/build-desktop-REDTEST.js INSIDE
# the repo (temporarily) so the builder's __dirname-rooted THEME_DIR/DESKTOP
# resolve exactly as in production. The copy is removed in finally.
#
#   .\tools\test-genlock-redcontrol.ps1           (all red, exit 0)
#   .\tools\test-genlock-redcontrol.ps1 -List
#
# Note: this suite intentionally REPORTS defects as found. Every gate must be
# red for exit 0; a green "red control" gate means the regression matrix is
# blind and the suite FAILS.

[CmdletBinding()] param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$builder = Join-Path $root 'tools\build-desktop.js'
$lockModule = Join-Path $root 'desktop\modules\generation-lock.ps1'
$common = Join-Path $root 'desktop\modules\common.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-genlock-redcontrol.ps1 (R009 red controls -- each must reproduce its defect):"
    Write-Host "  A. Node red control: the broken token-less release contract leaves the generation lock behind"
    Write-Host "  B. PS red control: stale release with MetadataWritten=true deletes a malformed replacement"
    Write-Host "  C. PS red control: age-only stealing removes a live holder's lock"
    exit 0
}

# ───────────────────────────── RED A ─────────────────────────────
# Broken production contract: acquireGenLock returned only the fd and
# releaseGenLock ran with no acquisition token available. Restored here onto a
# copy of the REAL builder, then the real normal-release gate's own child
# command must FAIL: the lock survives the build.
Write-Host 'RED A: Node release without the acquisition token'
$redBuilder = Join-Path $root 'tools\build-desktop-REDTEST.js'
try {
    $builderSrc = [System.IO.File]::ReadAllText($builder, $utf8)
    # Restore the shipped defect: acquisition returns no token object and
    # release runs token-less (the original leak -- current state 'ok' with a
    # foreign token short-circuits to 'return', leaving the lock on disk).
    $red = $builderSrc.Replace("return Object.freeze({ fd: fd, token: token, path: GEN_LOCK });", 'return Object.freeze({ fd: fd, token: null, path: GEN_LOCK });')
    if ($red -eq $builderSrc) { throw 'red A replacement did not apply' }
    [System.IO.File]::WriteAllText($redBuilder, $red, $utf8)
    $iso = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-rednode-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $iso -Force | Out-Null
    $prevApp = $env:WINTAGE_APPDATA
    $env:WINTAGE_APPDATA = $iso
    try {
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & node $redBuilder 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        $left = Test-Path (Join-Path $iso 'build-generation.lock')
        check 'red A: the broken release contract leaves the lock behind after a real build' ($code -eq 0 -and $left)
        check 'red A: the REAL builder is not the mutated copy' ((Split-Path $redBuilder -Leaf) -ne (Split-Path $builder -Leaf))
    } finally {
        if ($null -eq $prevApp) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevApp }
        Remove-Item $iso -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item $redBuilder -Force -ErrorAction SilentlyContinue
}

# ───────────────────────────── RED B ─────────────────────────────
# The MetadataWritten malformed-release deletion branch (the historical W2-004
# stale-release delete race): a stale acquisition A (its exclusive handle
# closed, ownership replaced) releases against a current malformed replacement
# and DELETES it because A once wrote metadata. The production module no longer
# carries that branch, so the red control INJECTS it into a TEMPORARY mutated
# copy: the complete fixed release body is replaced with an explicitly
# defective historical body, anchored on text that EXISTS in the fixed source.
# The shipped module is never modified, and the defective branch is asserted
# STRUCTURALLY before the behavioural probe runs.
Write-Host 'RED B: stale PowerShell release deletes a malformed replacement via MetadataWritten'
$redDirB = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-redps-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $redDirB -Force | Out-Null
try {
    $lockSrc = [System.IO.File]::ReadAllText($lockModule, $utf8)
    # Anchor on the FIXED token-verified release body (present in the current
    # source, absent from nothing): the matching-token branch plus the trailing
    # fail-closed comment. The replacement restores the HISTORICAL defective
    # release shape verbatim-in-spirit: close the handle, then delete whenever
    # this acquisition once wrote metadata -- ownership never re-verified.
    $anchor = @"
        if (`$state.State -eq 'ok' -and [string]`$state.Meta.token -eq [string]`$genLock.Token) {
            Remove-Item -LiteralPath `$genLock.Path -Force -ErrorAction SilentlyContinue
        }
"@
    $defective = @"
        if (`$state.State -eq 'malformed' -and `$genLock.MetadataWritten) {
            Remove-Item -LiteralPath `$genLock.Path -Force -ErrorAction SilentlyContinue
        }
        if (`$state.State -eq 'ok' -and [string]`$state.Meta.token -eq [string]`$genLock.Token) {
            Remove-Item -LiteralPath `$genLock.Path -Force -ErrorAction SilentlyContinue
        }
"@
    $red = $lockSrc.Replace($anchor, $defective)
    if ($red -eq $lockSrc) { throw 'red B replacement did not apply (the fixed release anchor was not found)' }
    # STRUCTURAL assertion: the defective branch must actually exist in the
    # mutated copy before any behavioural claim is derived from it, and it
    # must sit INSIDE the release function body (after its declaration).
    $defectMarker = "if (`$state.State -eq 'malformed' -and `$genLock.MetadataWritten) {"
    $fnStart = $red.IndexOf('function Exit-BuildGenerationLockCore')
    if (-not $red.Contains($defectMarker)) { throw 'red B structural assertion failed: the injected defective MetadataWritten branch is absent from the mutated copy' }
    if ($red.IndexOf($defectMarker) -le $fnStart) { throw 'red B structural assertion failed: the defective branch landed outside the release function' }
    $redLock = Join-Path $redDirB 'generation-lock-red.ps1'
    [System.IO.File]::WriteAllText($redLock, $red, $utf8)

    # The acquisition itself is runtime-agnostic; a raw core acquire/release
    # reproduces the hole exactly (no GUI wrappers needed). The malformed
    # replacement is kept under a second handle with FileShare DELETE so a
    # deletion attempt always succeeds (no transient sharing race) -- the RED
    # module deletes it, the fixed module never touches it.
    $probe = @'
param($redLock, $iso)
$ErrorActionPreference = 'Stop'
$env:WINTAGE_APPDATA = $iso
. '__REDLOCK__'
$A = Enter-BuildGenerationLockCore $iso
# Ownership is replaced after A's handle is no longer authoritative for the
# current path content: the original exclusive stream is closed, a malformed
# replacement is written at the path, THEN A releases with its stale acquisition.
$A.Stream.Close()
$lp = Join-Path $iso 'build-generation.lock'
[System.IO.File]::WriteAllText($lp, '   ', (New-Object System.Text.UTF8Encoding($false)))
$keeper = [System.IO.File]::Open($lp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read -bor [System.IO.FileShare]::Write -bor [System.IO.FileShare]::Delete)
Exit-BuildGenerationLockCore $A
$still = Test-Path -LiteralPath $lp
$keeper.Dispose()
if (-not $still) { Write-Output 'DELETED' } else { Write-Output 'SURVIVED' }
'@
    $probe = $probe.Replace('__REDLOCK__', $redLock)
    $probeFile = Join-Path $redDirB 'probe.ps1'
    [System.IO.File]::WriteAllText($probeFile, $probe, $utf8)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeFile $redLock $redDirB 2>&1
    $text = ($out | ForEach-Object { "$_" }) -join ' '
    check 'red B: the MetadataWritten release branch DELETES the malformed replacement (defect reproduced)' ($text -match 'DELETED')
    check 'red B: the SHIPPED module was not the file under test' ($redLock -ne $lockModule)
} finally {
    Remove-Item $redDirB -Recurse -Force -ErrorAction SilentlyContinue
}

# ───────────────────────────── RED C ─────────────────────────────
# Age-only stealing (the original R009 defect): a live holder whose lock file
# is back-dated past the stale threshold loses the lock to a contender that
# has no liveness evidence at all.
Write-Host 'RED C: age-only stealing removes a live holder''s lock'
$redDirC = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-redage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $redDirC -Force | Out-Null
try {
    $lockSrcC = [System.IO.File]::ReadAllText($lockModule, $utf8)
    $anchorC = "                    `$steal = (Test-GenerationLockOwnerAlive `$state.Meta) -eq 'dead'"
    $redC = $lockSrcC.Replace($anchorC, '                    $steal = $true # RED: age-only stealing restored')
    if ($redC -eq $lockSrcC) { throw 'red C replacement did not apply' }
    $redLockC = Join-Path $redDirC 'generation-lock-red.ps1'
    [System.IO.File]::WriteAllText($redLockC, $redC, $utf8)
    $isoC = Join-Path $redDirC 'appdata'
    New-Item -ItemType Directory -Path $isoC -Force | Out-Null
    $prevApp = $env:WINTAGE_APPDATA
    $prevTimeout = $env:WINTAGE_TEST_LOCK_TIMEOUT_MS
    $env:WINTAGE_APPDATA = $isoC
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '3000'
    try {
        . $redLockC
        $hold = Enter-BuildGenerationLockCore $isoC
        # Ownership is replaced while the live-holder metadata stays identical:
        # the exclusive handle is closed, the SAME live-owner metadata is
        # re-written at the path and back-dated past the stale threshold. The
        # contender then has age as the ONLY evidence - exactly the false
        # signal the age-only code acted on (the owner is demonstrably alive:
        # it is this very process).
        $hold.Stream.Close()
        $lockFileC = Join-Path $isoC 'build-generation.lock'
        $metaText = 'placeholder'
        try {
            $readerC = New-Object System.IO.StreamReader($lockFileC, [System.Text.Encoding]::UTF8, $false, 256, $true)
            $metaText = $readerC.ReadToEnd(); $readerC.Dispose()
        } catch { }
        [System.IO.File]::WriteAllText($lockFileC, $metaText, (New-Object System.Text.UTF8Encoding($false)))
        (Get-Item -LiteralPath $lockFileC).LastWriteTimeUtc = (Get-Date).AddSeconds(-120)
        $contender = Start-Job -ScriptBlock {
            param($redLockPath, $iso, $commonPath)
            $ErrorActionPreference = 'Stop'
            $env:WINTAGE_APPDATA = $iso
            $WintageAppData = $iso; $ManifestPath = 'x'
            . $commonPath
            # The RED core module loads AFTER common.ps1 so the red
            # Enter-BuildGenerationLockCore overrides the shipped one while the
            # shipped Enter-BatchLock wrapper (mutex family) stays real.
            . $redLockPath
            try { $null = Enter-BatchLock; 'STOLEN' } catch { 'REFUSED' }
        } -ArgumentList @($redLockC, $isoC, $common)
        if (Wait-Job $contender -Timeout 30) {
            $cOut = (Receive-Job $contender) -join ' '
            check 'red C: age-only stealing STOLE the back-dated live holder lock (defect reproduced)' ($cOut -match 'STOLEN')
        } else {
            check 'red C: age-only stealing STOLE the back-dated live holder lock (defect reproduced)' $false
            Write-Host '  red C contender timed out' -ForegroundColor Yellow
        }
        Remove-Job $contender -Force -ErrorAction SilentlyContinue
        try { $hold.Stream.Close() } catch { }
    } finally {
        if ($null -eq $prevTimeout) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue } else { $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = $prevTimeout }
        if ($null -eq $prevApp) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevApp }
    }
} finally {
    Remove-Item $redDirC -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host "RED CONTROL PROVEN: all $pass defect reproductions red" -ForegroundColor Yellow; exit 0 }
Write-Host "RED CONTROL NOT PROVEN: $fail gate(s) stayed green on defective source - the matrix is blind" -ForegroundColor Red
exit 1
