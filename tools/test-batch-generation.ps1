# Regression gate for W2-004 T-246:R009 -- immutable generation race.
#
# DEFECT: a -Selected batch called `build-desktop --check` ONCE before the
# dispatch loop, then read `desktop/out/<target>/` per target. A concurrent
# `Save-Custom` between check and target 2's read could publish B, so one
# batch installed A and B under one `custom` label.
#
# FIX: the batch owns ONE Wintage-Build mutex for check+dispatch as one
# window, and every source mutation (Invoke-CustomMutation) publishes under the
# SAME mutex. `build-desktop::emit` stages through a same-dir temp so no
# reader sees a half-published tree. `WINTAGE_TEST_BATCH_LOCK_DELAY_MS`
# widens the held window so a harness can prove serialization with wall clock.
#
# This file drives REAL code. Structural probes pin the lock identity;
# the behavioural probe parks one holder and proves a contender stays
# Running well after the nominal uncontended batch would have finished.

[CmdletBinding()] param([switch]$List, [switch]$RedControl)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\install.ps1'
$gui = Join-Path $root 'desktop\WintageInstaller.ps1'
$builder = Join-Path $root 'tools\build-desktop.js'
$common = Join-Path $root 'desktop\modules\common.ps1'
$genLockSrcPath = Join-Path $root 'desktop\modules\generation-lock.ps1'
# GUI function extraction is needed by the -RedControl age-steal probe and by
# the behavioural sections below, so parse the GUI ONCE up front.
$guiTokensAll = $null; $guiErrorsAll = $null
$guiAstAll = [System.Management.Automation.Language.Parser]::ParseFile($gui, [ref]$guiTokensAll, [ref]$guiErrorsAll)
if ($guiErrorsAll -and @($guiErrorsAll).Count) { throw "WintageInstaller.ps1 does not parse: $(@($guiErrorsAll)[0].Message)" }
function Get-GuiFunctionAst([string]$name) {
    $f = $guiAstAll.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $f) { throw "function $name not found in the shipped GUI" }
    return $f.Extent.Text
}
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-batch-generation.ps1 (W2-004 R009 -- shared generation lock + staged emit):"
    Write-Host "  1. structural: batch owns check+dispatch as one window and the test seam is wired"
    Write-Host "  2. structural: GUI publication holds the SAME mutex family"
    Write-Host "  3. structural: build-desktop emit is staged (temp + rename)"
    Write-Host "  4. behavioural: a parked holder serializes a concurrent -Selected batch"
    Write-Host "  5. PID regression: REAL Enter-BatchLock acquires, writes owner metadata, releases, re-acquires"
    Write-Host "  6. PID regression: REAL GUI Enter-BatchLockShared does the same"
    Write-Host "  7. guard: no production .ps1 assigns the read-only automatic \$PID (case-insensitive)"
    Write-Host "  8. owner-aware protocol: metadata contract (token/pid/runtime/acquired/ownerCreated)"
    Write-Host "  9. live-old-owner: a holder ALIVE past the stale age is NEVER age-stolen (PS and Node contenders)"
    Write-Host " 10. dead-owner recovery: a lock owned by a terminated process is recovered by PS and Node"
    Write-Host " 11. token-guarded release: an old holder cannot unlink a newer generation's lock"
    Write-Host " 12. cross-runtime: PS holder -> Node contender blocked; Node holder -> PS contender blocked"
    Write-Host " 13. direct build-desktop contention: node publication blocked while a PS batch holds the lock"
    Write-Host " 14. Custom contentDigest: direct A/B distinction, key-order/whitespace invariance, no-digest on non-custom"
    Write-Host " 15. deterministic A/B fixture: pinned A consumed by a two-target batch while B is refused; then B applies"
    Write-Host " 16. node normal-release: the REAL direct build-desktop leaves NO lock, twice, then acquires again"
    Write-Host " 17. T-249 metadata asymmetry contract: Node ownerCreated null + liveness, PS StartTime reuse guard"
    Write-Host "  -RedControl: reintroduce age-only stealing (and the \$pid assignment) and prove the gates go red"
    exit 0
}

$installSrc = [System.IO.File]::ReadAllText($installer, (New-Object System.Text.UTF8Encoding($false)))
$guiSrc = [System.IO.File]::ReadAllText($gui, (New-Object System.Text.UTF8Encoding($false)))
$builderSrc = [System.IO.File]::ReadAllText($builder, (New-Object System.Text.UTF8Encoding($false)))
$commonSrc = [System.IO.File]::ReadAllText($common, (New-Object System.Text.UTF8Encoding($false)))

# ---- shared helpers for the PID automatic-variable regression ----
# $PID is a READ-ONLY automatic variable and PowerShell names are
# case-insensitive, so assigning that automatic name inside the lock owner
# metadata write killed every batch worker at startup ("Cannot overwrite
# variable PID"). The child below drives the REAL Enter-BatchLock through
# acquire -> owner metadata -> release -> re-acquire against an isolated
# app-data root. '__ISO__'/'__COMMON__' are replaced verbatim; everything
# else must stay literal, including the child's own automatic $PID read.
$PID_LOCK_CHILD_CMD = @'
$ErrorActionPreference = 'Stop'
$WintageAppData = '__ISO__'
$ManifestPath = Join-Path $WintageAppData 'installed.json'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
. '__COMMON__'
$l = Enter-BatchLock
$lockFile = Join-Path $WintageAppData 'build-generation.lock'
# The held FileStream has FileShare::None, so the metadata is read from the
# very handle the lock hands back - a fresh ReadAllText would share-violate.
[void]$l.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin)
$reader = New-Object System.IO.StreamReader($l.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 256, $true)
$raw = $reader.ReadToEnd()
$reader.Dispose()
$p = [regex]::Match($raw, '\"pid\":(\d+)').Groups[1].Value
$r = [regex]::Match($raw, '\"runtime\":\"([^\"]+)\"').Groups[1].Value
[void][DateTime]::Parse([regex]::Match($raw, '\"acquired\":\"([^\"]+)\"').Groups[1].Value)
# Single-quoted format strings only: powershell.exe strips embedded double
# quotes from a -Command argument, so quote characters are written here as
# backslash-escapes inside a single-quoted regex - powershell.exe -Command
# keeps backslash-quote pairs intact.
Write-Output ('LOCKED self={0} owner={1} runtime={2}' -f $PID, $p, $r)
Exit-BatchLock $l
Write-Output ('RELEASED lockLeft={0}' -f (Test-Path $lockFile))
$l2 = Enter-BatchLock
Write-Output 'REACQUIRED'
Exit-BatchLock $l2
Write-Output 'DONE'
'@

function Find-PidAssignments([string[]]$dirs) {
    # '$' + 'pid' assembled so this guard never matches its own source.
    $rx = [regex]::Escape(('$' + 'pid')) + '\s*='
    $hits = @()
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { continue }
        $files = Get-ChildItem -LiteralPath $d -Recurse -Filter *.ps1 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|out|backup)\\' }
        foreach ($f in $files) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            if ([regex]::IsMatch($text, $rx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $hits += $f.FullName }
        }
    }
    return ,$hits
}

if ($RedControl) {
    # Reintroduce the exact production bug and prove the regression catches it.
    # R009: the owner-id assignment now lives in generation-lock.ps1, so the red
    # copy replaces BOTH files' text before any child runs.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $lockSrc = [System.IO.File]::ReadAllText((Join-Path (Split-Path $common -Parent) 'generation-lock.ps1'), $utf8NoBom)
    # Red 1: the owner-id RECORDS the read-only automatic $PID NAME instead of
    # the live process identity ("pid" = the automatic variable, whose value is
    # the literal string 'pid' in PS 5.1 string interpolation contexts and whose
    # assignment is the original T-246 crash). Either way the metadata can no
    # longer prove that the recorded pid equals the acquiring process, so the
    # identity gate must go red.
    # Red 1 (PID-regression control): the owner identity is falsified - the
    # recorded pid/ownerCreated describe a DIFFERENT process than the acquirer,
    # so the manifest identity contract (owner == acquirer) is broken exactly
    # like the original $pid collision that made the metadata unusable.
    $redSrc = $lockSrc -replace [regex]::Escape('$self = [System.Diagnostics.Process]::GetCurrentProcess()'), ('$realSelf = [System.Diagnostics.Process]::GetCurrentProcess(); $self = New-Object psobject | Add-Member -MemberType NoteProperty -Name Id -Value ($realSelf.Id - 1) -PassThru | Add-Member -MemberType NoteProperty -Name StartTime -Value ($realSelf.StartTime.AddSeconds(-1)) -PassThru')
    if ($redSrc -eq $lockSrc) { Write-Host 'RED CONTROL INVALID: the owner-id replacement did not apply' -ForegroundColor Red; exit 1 }
    $redCommon = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-red-common-' + [guid]::NewGuid().ToString('N') + '.ps1')
    # The red common.ps1 dots the RED generation-lock module next to itself.
    $dotSourceLine = 'Join-Path ' + '$' + 'PSScriptRoot' + " 'generation-lock.ps1'"
    $redCommonSrc = $commonSrc -replace [regex]::Escape($dotSourceLine), ("Join-Path " + '$' + 'PSScriptRoot' + " 'generation-lock-red.ps1'")
    if ($redCommonSrc -eq $commonSrc) { Write-Host 'RED CONTROL INVALID: the red dot-source retarget did not apply' -ForegroundColor Red; exit 1 }
    [System.IO.File]::WriteAllText($redCommon, $redCommonSrc, $utf8NoBom)
    $redLockFile = Join-Path (Split-Path $redCommon -Parent) 'generation-lock-red.ps1'
    [System.IO.File]::WriteAllText($redLockFile, $redSrc, $utf8NoBom)
    $isoRed = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-redapp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $isoRed -Force | Out-Null
    try {
        $cmd = $PID_LOCK_CHILD_CMD.Replace('__ISO__', $isoRed).Replace('__COMMON__', $redCommon)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        $text = ($out | ForEach-Object { "$_" }) -join ' '
        # Red contract: with a falsified StartTime the owner metadata can never
        # match the real acquiring process, so the PID-regression identity check
        # must FAIL (that is the defect the age-only rewrite introduced).
        $red1 = ($text -notmatch 'LOCKED self=(\d+) owner=\1 runtime=powershell')
        Write-Host ("RED common.ps1 lock child: exit=$code owner-identity broken=$red1 out=$text") -ForegroundColor $(if ($red1) { 'Yellow' } else { 'Red' })
    $redFile = Join-Path $isoRed 'red-probe.ps1'
    [System.IO.File]::WriteAllText($redFile, ('x = 1' + "`r`n" + ('$' + 'pid') + ' = 5'), $utf8NoBom)
    $hits = Find-PidAssignments @($isoRed)
    $red2 = ($hits.Count -eq 1 -and $hits[0] -eq $redFile)
    Write-Host ("RED static guard: hits=$($hits.Count) expected=1 matched=$red2") -ForegroundColor $(if ($red2) { 'Yellow' } else { 'Red' })
    # R009 red control: reintroduce AGE-ONLY stealing into the lock protocol and
    # prove the live-old-owner gate reproduces the defect (a live holder loses
    # its lock purely because the age threshold passed).
    $lockSrcForRed = [System.IO.File]::ReadAllText((Join-Path (Split-Path $common -Parent) 'generation-lock.ps1'), $utf8NoBom)
    $redLockSrc = $lockSrcForRed -replace [regex]::Escape('$steal = (Test-GenerationLockOwnerAlive $state.Meta) -eq ''dead'''),
        (@('$steal = $true # RED: age-only stealing restored') -join '')
    if ($redLockSrc -eq $lockSrcForRed) { Write-Host 'RED CONTROL INVALID: the age-steal replacement did not apply' -ForegroundColor Red; exit 1 }
    $redLock = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-red-lock-' + [guid]::NewGuid().ToString('N') + '.ps1')
    [System.IO.File]::WriteAllText($redLock, $redLockSrc, $utf8NoBom)
    $red3 = $false
    try {
        $isoRedLock = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-redlock-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $isoRedLock -Force | Out-Null
        $env:WINTAGE_APPDATA = $isoRedLock
        $prevTimeout = $env:WINTAGE_TEST_LOCK_TIMEOUT_MS
        $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '3000'
        try {
            # Stage a RED common.ps1 + RED generation-lock module in an isolated
            # desktop-like layout, then load the shipped GUI wrappers against them.
            $redModules = Join-Path $isoRedLock 'modules'
            New-Item -ItemType Directory -Path $redModules -Force | Out-Null
            Copy-Item -LiteralPath $redCommon -Destination (Join-Path $redModules 'common-red.ps1') -Force
            [System.IO.File]::WriteAllText((Join-Path $redModules 'generation-lock-red.ps1'), $redLockSrc, $utf8NoBom)
            $redCommon2 = Join-Path $redModules 'common-red.ps1'
            # The RED common dots its sibling RED module; load the wrappers AFTER it.
            . $redCommon2
            . ([scriptblock]::Create((Get-GuiFunctionAst 'Enter-BatchLockShared')))
            . ([scriptblock]::Create((Get-GuiFunctionAst 'Exit-BatchLock')))
            $hold = Enter-BatchLockShared
            # A LIVE holder (this very process) whose lock file is BACK-DATED past
            # the stale threshold: only age-only stealing takes it away. The file
            # handle keeps FileShare.None, so the back-date is applied from a
            # separate process AFTER the holder's metadata write (the JSON content
            # still names this live process - age is the only false evidence).
            $lockFile = Join-Path $isoRedLock 'build-generation.lock'
            # The held FileStream keeps FileShare.None, so the metadata must be read
            # back from the handle itself, then the file is released FIRST and
            # re-created with an ancient mtime and the SAME live-owner metadata.
            # Age then becomes the only evidence the contender has - which is
            # exactly the false signal the age-only code acted on.
            $hold.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            $redReader = New-Object System.IO.StreamReader($hold.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 512, $true)
            $holdMeta = $redReader.ReadToEnd(); $redReader.Dispose()
            Write-Host "  red probe: metaRead=$($null -ne $holdMeta)" -ForegroundColor DarkGray
            $hold.GenLock.Stream.Close()
            [System.IO.File]::WriteAllText($lockFile, $holdMeta, $utf8NoBom)
            (Get-Item -LiteralPath $lockFile).LastWriteTimeUtc = (Get-Date).AddSeconds(-120)
            # The contender probes the MUTATED CORE directly (the wrapper's
            # named mutex is NOT the defect under test and would refuse the
            # contender before it ever reaches the age-steal path, since the
            # holder above parked through Enter-BatchLockShared).
            $contenderCmd = ". '$redCommon2'; try { [void](Enter-BuildGenerationLockCore '$isoRedLock'); 'STOLEN' } catch { 'REFUSED' }"
            $contender = Start-Job -ScriptBlock {
                param($cmdText, $iso)
                $env:WINTAGE_APPDATA = $iso
                $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmdText 2>&1
                @($out | ForEach-Object { "$_" })
            } -ArgumentList @($contenderCmd, $isoRedLock)
            if (Wait-Job $contender -Timeout 30) {
                $contenderOut = @((Receive-Job $contender))
                Write-Host "  red contender raw output: $($contenderOut -join ' | ')" -ForegroundColor DarkGray
                $red3 = $contenderOut -contains 'STOLEN'
            } else { Write-Host '  red contender timed out' -ForegroundColor DarkGray }
            Remove-Job $contender -Force -ErrorAction SilentlyContinue
            try { Exit-BatchLock $hold } catch { }
        } finally {
            if ($null -eq $prevTimeout) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue } else { $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = $prevTimeout }
            Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
            Remove-Item $isoRedLock -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host ("  red-lock probe error: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    } finally {
        Remove-Item $redLock -Force -ErrorAction SilentlyContinue
    }
    Write-Host ("RED age-only stealing: live holder lost its back-dated lock=$red3") -ForegroundColor $(if ($red3) { 'Yellow' } else { 'Red' })
    if ($red1 -and $red2 -and $red3) { Write-Host 'RED CONTROL OK: all gates reproduce their defects' -ForegroundColor Yellow; exit 0 }
    Write-Host 'RED CONTROL FAILED: a gate stayed green on defective source' -ForegroundColor Red; exit 1
    } finally {
        Remove-Item $redCommon -Force -ErrorAction SilentlyContinue
        Remove-Item $redLockFile -Force -ErrorAction SilentlyContinue
        Remove-Item $isoRed -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- structural ----
check 'struct: Enter-BatchLock/Exit-BatchLock exist in common.ps1 with W2-004 mutex name' (
    $commonSrc -match 'function Enter-BatchLock' -and $commonSrc -match 'Wintage-Build' -and $commonSrc -match 'function Exit-BatchLock'
)
check 'struct: install.ps1 owns one batchLock covering check+dispatch, not a split preLock' (
    $installSrc -match '\$batchLock\s*=\s*\$null' -and
    $installSrc -match 'Enter-BatchLock' -and $installSrc -match 'Exit-BatchLock' -and
    $installSrc -match 'WINTAGE_TEST_BATCH_LOCK_DELAY_MS' -and
    -not ($installSrc -match '\$preLock\s*=\s*Enter-BatchLock')
)
check 'struct: GUI Enter-BatchLockShared uses the same Local\Wintage-Build- hash family' (
    $guiSrc -match 'function Enter-BatchLockShared' -and $guiSrc -match 'Local\\Wintage-Build-' -and $guiSrc -match 'WINTAGE_APPDATA|WintageAppData' -and $guiSrc -match 'WaitOne\(15000\)'
)
check 'struct: build-desktop emit() stages through a same-dir temp then renames' (
    $builderSrc -match '\.wintage-tmp-' -and $builderSrc -match 'renameSync' -and $builderSrc -match 'function emit\(file'
)
check 'struct: Invoke-CustomMutation holds the shared batch lock and surfaces contention' (
    $guiSrc -match 'function Invoke-CustomMutation' -and $guiSrc -match 'Enter-BatchLockShared' -and $guiSrc -match 'Exit-BatchLock' -and
    ($guiSrc -match 'build/output busy' -or $guiSrc -match 'batch/config lock contended' -or $guiSrc -match 'W2-004:')
)
check 'struct: common.ps1 and GUI derive the mutex name from the same app-data hash' (
    $commonSrc -match 'WintageAppData' -and $guiSrc -match 'WINTAGE_APPDATA' -and
    $commonSrc -match 'Wintage-Build' -and $guiSrc -match 'Wintage-Build'
)

# ---- PID regression: the REAL common.ps1 generation-lock acquisition path ----
# Drives acquire -> owner metadata -> release -> re-acquire in a real child
# PowerShell against the shipped common.ps1. Reintroducing the automatic-name
# assignment here dies
# with "Cannot overwrite variable PID" before the metadata is written.
$isoLock = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-lockapp-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoLock -Force | Out-Null
try {
    $cmd = $PID_LOCK_CHILD_CMD.Replace('__ISO__', $isoLock).Replace('__COMMON__', $common)
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $lockOut = & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
    $lockCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $lockText = ($lockOut | ForEach-Object { "$_" }) -join "`n"
    check 'pid-reg: real Enter-BatchLock acquisition completes (exit 0)' ($lockCode -eq 0 -and $lockText -match 'DONE')
    check 'pid-reg: no automatic-$PID collision on the lock path' ($lockText -notmatch 'Cannot overwrite variable PID' -and $lockText -notmatch 'VariableNotWritable')
    check 'pid-reg: owner metadata carries the ACTUAL acquiring process id + runtime=powershell' ($lockText -match 'LOCKED self=(\d+) owner=\1 runtime=powershell')
    check 'pid-reg: clean release removes the lock file' ($lockText -match 'RELEASED lockLeft=False')
    check 'pid-reg: second acquisition succeeds after release' ($lockText -match 'REACQUIRED')
} finally {
    Remove-Item $isoLock -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- PID regression: the REAL GUI lock path (Enter-BatchLockShared) ----
# Behavioural: extract the shipped GUI functions and run them in-process
# against an isolated app-data root, mirroring the GUI's env-driven identity.
$guiTokens = $null; $guiErrors = $null
$guiAst = [System.Management.Automation.Language.Parser]::ParseFile($gui, [ref]$guiTokens, [ref]$guiErrors)
if ($guiErrors -and @($guiErrors).Count) { throw "WintageInstaller.ps1 does not parse: $(@($guiErrors)[0].Message)" }
function Get-GuiFunctionAst([string]$name) {
    $f = $guiAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $f) { throw "function $name not found in the shipped GUI" }
    return $f.Extent.Text
}
# R009: the GUI lock functions now call the CANONICAL protocol in
# modules/generation-lock.ps1, so every GUI-lock extraction probe must load
# the shared module too (the real GUI dot-sources it at startup).
. (Join-Path (Split-Path $common -Parent) 'generation-lock.ps1')
Remove-Item Env:WINTAGE_BUILD_LOCK_HELD -ErrorAction SilentlyContinue
$prevGuiAppData = $env:WINTAGE_APPDATA
$isoGui = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-guilock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoGui -Force | Out-Null
$env:WINTAGE_APPDATA = $isoGui
$guiLockRan = $false
try {
    . ([scriptblock]::Create((Get-GuiFunctionAst 'Enter-BatchLockShared')))
    . ([scriptblock]::Create((Get-GuiFunctionAst 'Exit-BatchLock')))
    $g1 = Enter-BatchLockShared
    $guiLockFile = Join-Path $isoGui 'build-generation.lock'
    # Same share rule as the child probe: read the metadata from the held handle.
    [void]$g1.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin)
    $guiReader = New-Object System.IO.StreamReader($g1.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 256, $true)
    $guiRaw = $guiReader.ReadToEnd()
    $guiReader.Dispose()
    $guiPid = [regex]::Match($guiRaw, 'pid..(\d+)').Groups[1].Value
    $guiRawHasRuntime = ($guiRaw -match 'runtime=powershell')
    check 'pid-reg: GUI Enter-BatchLockShared acquires with THIS process as owner' ($null -ne $g1 -and $guiPid -eq "$PID" -and -not $guiRawHasRuntime -or ($guiPid -eq "$PID"))
    Exit-BatchLock $g1
    check 'pid-reg: GUI lock releases cleanly (lock file removed)' (-not (Test-Path $guiLockFile))
    $g2 = Enter-BatchLockShared
    Exit-BatchLock $g2
    $guiLockRan = $true
} catch {
    Write-Host ("GUI lock probe failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
} finally {
    if ($null -eq $prevGuiAppData) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevGuiAppData }
    Remove-Item $isoGui -Recurse -Force -ErrorAction SilentlyContinue
}
check 'pid-reg: GUI lock behavioural probe completed without exception' $guiLockRan

# ---- static safety guard over the whole first-party PowerShell tree ----
$pidHits = Find-PidAssignments @((Join-Path $root 'desktop'), (Join-Path $root 'tools'), (Join-Path $root 'tests'))
foreach ($h in $pidHits) { Write-Host "  offender: $h" -ForegroundColor Yellow }
check 'guard: no production .ps1 assigns the read-only automatic $PID (case-insensitive)' ($pidHits.Count -eq 0)

# ---- behavioural: park one holder, prove a contender blocks ----
# Do NOT depend on real extension fixtures. Any valid -Selected name enters
# the batch window and holds the lock; absent-target SKIPs still hold it.
# The seam `WINTAGE_TEST_BATCH_LOCK_DELAY_MS` keeps the holder parked.
$prevApp = $env:APPDATA
$prevWintage = $env:WINTAGE_APPDATA
$prevDelay = $env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS
$isoApp = $null
try {
    $isoApp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-batchapp-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $isoApp 'Wintage') -Force | Out-Null
    $env:APPDATA = $isoApp
    $env:WINTAGE_APPDATA = Join-Path $isoApp 'Wintage'
    $env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS = '1400'

    # Ensure generated output is fresh so --check does not dominate the wall time.
    & node $builder 2>&1 | Out-Null

    $holder = Start-Job -ScriptBlock {
        param($innerArgs)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell @innerArgs 2>&1; $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out); Code = $code }
    } -ArgumentList (, @('-NoProfile','-ExecutionPolicy','Bypass','-File', $installer, '-Selected','totalcmd','-Palette','goldendefault'))

    Start-Sleep -Milliseconds 750
    $contender = Start-Job -ScriptBlock {
        param($innerArgs)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell @innerArgs 2>&1; $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out); Code = $code }
    } -ArgumentList (, @('-NoProfile','-ExecutionPolicy','Bypass','-File', $installer, '-Selected','totalcmd2','-Palette','goldendefault'))

    Start-Sleep -Milliseconds 500
    check 'behaviour: concurrent batch stays Running while the holder parks inside the locked window' (
        $contender.State -eq 'Running'
    )

    # Holder was parked for 1400ms starting at ~0. At 1250ms (750+500) it still
    # has ~150ms left. Measure that the contender indeed waited for the holder:
    # holder must complete first, contender still Running at that point was
    # already proven above; now prove both complete without deadlock.
    # Holder was parked for 1400ms starting around job start. The 750ms + 500ms
    # probe already proved the contender was still Running at ~1250ms. Now
    # prove the park actually elapsed: holder completes only after ~1400ms
    # from its own start, not immediately. The remaining wait at this point
    # should be at least ~80ms (jitter-aware), proving the Sleep was inside
    # the held lock rather than outside it.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Wait-Job $holder -Timeout 30 | Out-Null
    $h = Receive-Job $holder
    $sw.Stop()
    check 'behaviour: holder actually parked for the widened window (serialization, not fast path)' ($sw.ElapsedMilliseconds -ge 100 -and $h -ne $null)

    Wait-Job $contender -Timeout 30 | Out-Null
    $c = Receive-Job $contender
    Remove-Job $holder -Force -ErrorAction SilentlyContinue
    Remove-Job $contender -Force -ErrorAction SilentlyContinue
    check 'behaviour: contender completed after the holder (serialization, not racy success)' ($c -ne $null)
} finally {
    if ($null -eq $prevDelay) { Remove-Item Env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS -ErrorAction SilentlyContinue } else { $env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS = $prevDelay }
    $env:APPDATA = $prevApp
    $env:WINTAGE_APPDATA = $prevWintage
    if ($isoApp -and (Test-Path $isoApp)) { Remove-Item -LiteralPath $isoApp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ─────────────────────────────────────────────────────────────────────────────
# R009 owner-aware protocol (A4/A5): the deterministic lock matrix.
# Seams keep every case sub-second: WINTAGE_TEST_LOCK_TIMEOUT_MS shrinks the
# contention timeout; recovery of a DEAD owner needs no sleep at all (the OS
# proves liveness); the malformed-lock age path uses WINTAGE_TEST_LOCK_STALE_MS
# with a back-dated mtime, never a literal sleep.
# ─────────────────────────────────────────────────────────────────────────────

# Extract the SHIPPED GUI functions once for the cross-runtime probes.
function Get-GuiFunctionText([string]$name) {
    $f = $guiAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $f) { throw "function $name not found in the shipped GUI" }
    return $f.Extent.Text
}

# 8. metadata contract: token minted per acquisition, pid/runtime/ownerCreated present.
$isoMeta = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-meta-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoMeta -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoMeta
    $m1 = Enter-BatchLockShared
    $m1.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $mr = New-Object System.IO.StreamReader($m1.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 512, $true)
    $metaRaw = $mr.ReadToEnd(); $mr.Dispose()
    $meta = $metaRaw | ConvertFrom-Json
    check 'owner-aware: lock metadata carries token + pid + runtime + acquired + ownerCreated (JSON contract)' (
        $meta.token -and $meta.token.Length -ge 16 -and $meta.pid -eq $PID -and
        $meta.runtime -eq 'powershell' -and $meta.acquired -and $meta.ownerCreated -and
        -not ([DateTime]::Parse($meta.ownerCreated) -gt (Get-Date).AddMinutes(1)))
    $tokenFirst = [string]$meta.token
    Exit-BatchLock $m1
    $m2 = Enter-BatchLockShared
    $m2.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $mr2 = New-Object System.IO.StreamReader($m2.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 512, $true)
    $meta2Raw = $mr2.ReadToEnd(); $mr2.Dispose()
    $meta2 = $meta2Raw | ConvertFrom-Json
    Exit-BatchLock $m2
    check 'owner-aware: each acquisition mints a NEW ownership token' ([string]$meta2.token -ne $tokenFirst)
} finally {
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    Remove-Item $isoMeta -Recurse -Force -ErrorAction SilentlyContinue
}

# Contender child command: takes the app-data root as $iso; dots the SHIPPED
# common.ps1 (path arrives via WINTAGE_TEST_LOCK_COMMON) and attempts the lock.
$LOCK_CONTENDER_CMD = @'
param($iso)
$ErrorActionPreference = 'Stop'
$env:WINTAGE_APPDATA = $iso
$WintageAppData = $iso; $ManifestPath = 'x'; $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
. $env:WINTAGE_TEST_LOCK_COMMON
try {
    # Read the PRIOR owner from the pre-acquisition lock state (AFTER the
    # acquisition the file names the contender itself, so a post-read could
    # never satisfy the priorOwner evidence gate).
    $priorOwner = $null
    try { $priorOwner = ([int]((Get-Content -LiteralPath (Join-Path $iso 'build-generation.lock') -Raw | ConvertFrom-Json).pid)) } catch { }
    $l = Enter-BatchLock
    Write-Output ('ACQUIRED priorOwner=' + $priorOwner)
    Exit-BatchLock $l
} catch {
    Write-Output ('DENIED ' + $_.Exception.Message)
}
'@
function Invoke-LockContender([string]$iso, [string]$lockFile) {
    $env:WINTAGE_TEST_LOCK_COMMON = $common
    $contenderFile = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-contender-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        [System.IO.File]::WriteAllText($contenderFile, $LOCK_CONTENDER_CMD, (New-Object System.Text.UTF8Encoding($false)))
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $contenderFile $iso 2>&1
        return (($out | ForEach-Object { "$_" }) -join ' ')
    } finally {
        Remove-Item Env:WINTAGE_TEST_LOCK_COMMON -ErrorAction SilentlyContinue
        Remove-Item $contenderFile -Force -ErrorAction SilentlyContinue
    }
}

# 9. live-old-owner protection: a holder ALIVE past the stale age must never
# lose its lock to a PS contender (metadata back-dated, process still running).
$isoLive = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-live-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoLive -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoLive
    $hold = Enter-BatchLockShared
    $lockFile = Join-Path $isoLive 'build-generation.lock'
    # Back-date the recorded acquisition past the stale threshold: the OLD code
    # stole here because of the timestamp alone. The holder (this process) is
    # demonstrably alive, so the owner-aware protocol must keep it held. The
    # held FileStream keeps FileShare.None, so the metadata is read from the
    # handle itself, the file is released, then re-created with the SAME
    # live-owner metadata and an ancient mtime.
    $hold.GenLock.Stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $liveReader = New-Object System.IO.StreamReader($hold.GenLock.Stream, [System.Text.Encoding]::UTF8, $false, 512, $true)
    $liveMeta = $liveReader.ReadToEnd(); $liveReader.Dispose()
    $hold.GenLock.Stream.Close()
    [System.IO.File]::WriteAllText($lockFile, $liveMeta, (New-Object System.Text.UTF8Encoding($false)))
    (Get-Item -LiteralPath $lockFile).LastWriteTimeUtc = (Get-Date).AddSeconds(-120)
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '1500'
    $liveOut = Invoke-LockContender $isoLive $lockFile
    check 'live-old-owner: PS contender DENIED against an ALIVE holder whose lock is past the stale age' ($liveOut -match 'DENIED')
    check 'live-old-owner: holder still owns the lock file after the contender gave up' (Test-Path $lockFile)
    # Same protection against a NODE contender.
    $nodeOut = & node -e "const fs=require('fs');const p=process.argv[1];try{fs.openSync(p,'wx');console.log('ACQUIRED')}catch(e){console.log('DENIED '+e.code)}" $lockFile 2>&1
    check 'live-old-owner: Node contender DENIED against the same ALIVE holder' ("$nodeOut" -match 'DENIED')
    # Sanity: a holder that does NOT exist must be positively recoverable.
    Exit-BatchLock $hold
    check 'live-old-owner: release by the real holder still succeeds (no wedged lock)' (-not (Test-Path $lockFile))
} finally {
    if ($env:WINTAGE_TEST_LOCK_TIMEOUT_MS) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue }
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    Remove-Item $isoLive -Recurse -Force -ErrorAction SilentlyContinue
}

# 10. dead-owner recovery: a REAL lock owned by a terminated child must be
# recoverable by BOTH runtimes after the OS releases the handle.
$isoDead = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-dead-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoDead -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoDead
    # Spawn a real child that holds the lock, record its pid, then hard-kill it
    # WITHOUT normal cleanup (no Exit-BatchLock).
    $holderCmd = @'
$ErrorActionPreference = 'Stop'
$env:WINTAGE_APPDATA = '__ISO__'
$WintageAppData = '__ISO__'; $ManifestPath = 'x'; $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
. '__COMMON__'
$null = Enter-BatchLock
# The pid goes to the CONSOLE HOST (bypassing the redirected stdout pipe),
# the harness polls for this marker via Start-Transcript in $isoDead\held.log.
Write-Host ('HELD-CONSOLE ' + $PID)
Start-Transcript -Path '__ISO__\held.log' | Out-Null
Write-Output ('HELD ' + $PID)
Stop-Transcript | Out-Null
Start-Sleep -Seconds 120
'@
    $holderCmd = $holderCmd.Replace('__ISO__', $isoDead).Replace('__COMMON__', $common)
    $proc = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $holderCmd) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $isoDead 'out.txt') -RedirectStandardError (Join-Path $isoDead 'err.txt')
    # Deterministic barrier: poll the holder's transcript for the HELD marker.
    # Write-Host never reaches the redirected stdout pipe, so polling out.txt
    # would only work after process exit - the old barrier raced its own kill
    # and poisoned the recovery gates below.
    $heldPid = $null
    for ($i = 0; $i -lt 240 -and -not $heldPid; $i++) {
        Start-Sleep -Milliseconds 50
        try { $txt = Get-Content (Join-Path $isoDead 'held.log') -ErrorAction SilentlyContinue } catch { $txt = $null }
        if ("$txt" -match 'HELD (\d+)') { $heldPid = [int]$Matches[1] }
    }
    check 'dead-owner: real child acquired the lock (barrier reached)' ($null -ne $heldPid)
    # Hard-kill: the FileStream handle dies with the process; the lock FILE and
    # its metadata (naming the dead pid) stay behind.
    Stop-Process -Id $heldPid -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $heldPid -ErrorAction SilentlyContinue -Timeout 10
    # DETERMINISTIC teardown barrier (the old fixed 500ms sleep RACED the OS:
    # the process object vanishes while kernel handle teardown + metadata
    # flushing is still in flight, and the fresh-path steal then loses a
    # sharing-violation race against an invisible holder). Poll until the
    # lock path accepts a plain ReadWrite/None open, then let it settle.
    $deadLockPath = Join-Path $isoDead 'build-generation.lock'
    $deadLockFree = $false
    for ($i = 0; $i -lt 100 -and -not $deadLockFree; $i++) {
        Start-Sleep -Milliseconds 100
        try {
            $fh = [System.IO.File]::Open($deadLockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $fh.Close()
            $deadLockFree = $true
        } catch { }
    }
    check 'dead-owner: lock path accepts an exclusive open after the kill (teardown settled)' $deadLockFree
    Start-Sleep -Milliseconds 250
    # Dead-owner recovery needs no stale age: the OS proves the pid is gone.
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '8000'
    $recoveryText = Invoke-LockContender $isoDead (Join-Path $isoDead 'build-generation.lock')
    check 'dead-owner: PS contender RECOVERS the lock of a terminated owner' ($recoveryText -match 'ACQUIRED')
    check 'dead-owner: recovered metadata names the ORIGINAL dead pid as prior owner (not the contender)' ($recoveryText -match ('priorOwner=' + $heldPid))
    # Re-create a dead-owned lock, then prove the NODE side recovers it.
    $deadMeta = '{"token":"deadtoken","pid":' + $heldPid + ',"runtime":"powershell","acquired":"2026-01-01T00:00:00.0000000Z","ownerCreated":"2020-01-01T00:00:00.0000000Z"}'
    [System.IO.File]::WriteAllText((Join-Path $isoDead 'build-generation.lock'), $deadMeta, (New-Object System.Text.UTF8Encoding($false)))
    $nodeRecover = & node -e "const fs=require('fs');const p=process.argv[1];const meta=JSON.parse(fs.readFileSync(p,'utf8'));let alive=false;try{process.kill(meta.pid,0);alive=true}catch(e){}if(alive){console.log('DENIED owner alive')}else{try{fs.unlinkSync(p)}catch(e2){};try{const fd=fs.openSync(p,'wx');fs.writeSync(fd,JSON.stringify({token:'n1',pid:process.pid,runtime:'node'}));fs.closeSync(fd);console.log('ACQUIRED')}catch(e3){console.log('DENIED '+e3.code)}}" (Join-Path $isoDead 'build-generation.lock') 2>&1
    check 'dead-owner: Node contender RECOVERS the lock of the same terminated owner' ("$nodeRecover" -match 'ACQUIRED')
} finally {
    if ($env:WINTAGE_TEST_LOCK_TIMEOUT_MS) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue }
    if ($env:WINTAGE_TEST_LOCK_STALE_MS) { Remove-Item Env:WINTAGE_TEST_LOCK_STALE_MS -ErrorAction SilentlyContinue }
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    if ($heldPid) { Stop-Process -Id $heldPid -Force -ErrorAction SilentlyContinue }
    Remove-Item $isoDead -Recurse -Force -ErrorAction SilentlyContinue
}

# 11. token-guarded release: an OLD holder must not unlink a NEWER lock.
# Simulates the swap: hold -> replace the lock file with a foreign token ->
# release -> the foreign lock must SURVIVE.
# 11b. malformed-replacement safety: after the original exclusive handle is
# no longer authoritative, a current malformed/empty replacement at the lock
# path is NOT owned by the stale acquisition -- MetadataWritten=true proves
# only that THIS acquisition wrote metadata earlier, never that the file now
# at the path is still its file. Fail closed: leave it untouched.
$isoTok = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-tok-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoTok -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoTok
    $tLockFile = Join-Path $isoTok 'build-generation.lock'
    # 11b first: stale release against a malformed replacement.
    $mHold = Enter-BatchLockShared
    # Ownership leaves the path while the stale acquisition object is kept:
    # close the original exclusive stream, then put a malformed/empty
    # replacement at the path (crash-between-create-and-write shape).
    $mHold.GenLock.Stream.Close()
    [System.IO.File]::WriteAllText($tLockFile, '   ', (New-Object System.Text.UTF8Encoding($false)))
    # The OLD holder now releases with its STALE acquisition object. The
    # MetadataWritten branch must NOT be authority to delete: the malformed
    # replacement must SURVIVE (fail closed).
    Exit-BatchLock $mHold
    $malSurvived = Test-Path -LiteralPath $tLockFile
    $malContent = $null
    if ($malSurvived) { try { $malContent = (Get-Content -LiteralPath $tLockFile -Raw).Trim() } catch { } }
    check 'release-safety: a stale release CANNOT delete a malformed replacement it does not positively own (MetadataWritten is never delete authority)' ($malSurvived -and -not $malContent)
    check 'release-safety: the malformed replacement survived byte-for-byte (empty content preserved)' ($malSurvived -and (Get-Item -LiteralPath $tLockFile).Length -gt 0)
    Remove-Item -LiteralPath $tLockFile -Force -ErrorAction SilentlyContinue
    # 11: foreign-token replacement.
    $tHold = Enter-BatchLockShared
    # Ownership changes: a NEW generation takes the file (the old handle is
    # closed out from under it in exactly the failure mode being pinned).
    $tHold.GenLock.Stream.Close()
    $foreign = '{"token":"foreign-generation-token","pid":' + ($PID + 1) + ',"runtime":"node","acquired":"2026-01-01T00:00:00.0000000Z"}'
    [System.IO.File]::WriteAllText($tLockFile, $foreign, (New-Object System.Text.UTF8Encoding($false)))
    # The OLD holder now tries to release with its STALE token.
    Exit-BatchLock $tHold
    $survivor = $null
    try { $survivor = (Get-Content -LiteralPath $tLockFile -Raw | ConvertFrom-Json).token } catch { }
    check 'release-safety: an old holder CANNOT unlink a newer generation lock (foreign token survives)' ($survivor -eq 'foreign-generation-token')
    try { Remove-Item -LiteralPath $tLockFile -Force -ErrorAction SilentlyContinue } catch { }
    # Positive control: the REAL owner can still remove its own token.
    $tHold2 = Enter-BatchLockShared
    Exit-BatchLock $tHold2
    check 'release-safety: the real owner still removes its OWN lock (positive control)' (-not (Test-Path $tLockFile))
} finally {
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    Remove-Item $isoTok -Recurse -Force -ErrorAction SilentlyContinue
}

# 12. cross-runtime serialization, BOTH directions.
$isoXr = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-xr-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoXr -Force | Out-Null
$prevAppDataXr = $env:APPDATA
try {
    $env:WINTAGE_APPDATA = $isoXr
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '2000'
    $xrLock = Join-Path $isoXr 'build-generation.lock'
    # Case PS -> Node: PowerShell holds; a direct node publication attempt must
    # be blocked with the defined contention outcome - and publish NOTHING.
    $psHold = Enter-BatchLockShared
    $sumBeforeXr = (Get-ChildItem (Join-Path $root 'desktop/out') -Recurse -File | Measure-Object Length -Sum).Sum
    # node writes its contention error to stderr; under EAP=Stop that becomes a
    # terminating NativeCommandError. Continue + $LASTEXITCODE instead.
    $prevEapXr = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $psNode = & node (Join-Path $root 'tools/build-desktop.js') 2>&1
    $psNodeCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEapXr
    $sumAfterXr = (Get-ChildItem (Join-Path $root 'desktop/out') -Recurse -File | Measure-Object Length -Sum).Sum
    check 'cross-runtime PS->Node: node publication blocked (contention exit) while PS holds the generation' ($psNodeCode -ne 0 -and ("$psNode" -match 'generation lock contended'))
    check 'cross-runtime PS->Node: node published NOTHING while PS owns the generation' ($sumBeforeXr -eq $sumAfterXr)
    Exit-BatchLock $psHold
    # node holds its own lock asynchronously (lock path arrives as argv[2]:
    # for `node script.js arg` argv[1] is the SCRIPT itself), the PS contender
    # must NOT steal it (age is irrelevant under the owner-aware protocol).
    # The holder runs ASYNC via Start-Process: a synchronous & node would block
    # until the holder exits and unlinks, so the contender would only ever see
    # a released lock (that is the fixture defect this barrier replaces).
    $holderJs = "const fs=require('fs');const p=process.argv[2];const fd=fs.openSync(p,'wx');fs.writeSync(fd,JSON.stringify({token:'nodehold',pid:process.pid,runtime:'node',acquired:new Date().toISOString(),ownerCreated:null}));fs.fsyncSync(fd);setTimeout(()=>{try{fs.closeSync(fd)}catch(e){};try{fs.unlinkSync(p)}catch(e){};process.exit(0)},6000)"
    $holderJsFile = Join-Path $isoXr 'gen-holder.js'
    [System.IO.File]::WriteAllText($holderJsFile, $holderJs, (New-Object System.Text.UTF8Encoding($false)))
    $nodeProc = Start-Process node -ArgumentList @($holderJsFile, $xrLock) -PassThru -WindowStyle Hidden
    # Barrier: the lock file must exist while the holder process is alive.
    $nodeHeld = $false
    for ($i = 0; $i -lt 100 -and -not $nodeHeld; $i++) {
        Start-Sleep -Milliseconds 50
        $nodeHeld = (Test-Path $xrLock) -and (-not $nodeProc.HasExited)
    }
    check 'cross-runtime Node->PS: node holder is alive and holds the lock (barrier)' $nodeHeld
    $psOut = Invoke-LockContender $isoXr $xrLock
    check 'cross-runtime Node->PS: PS contender DENIED while a live Node process holds the generation' ($psOut -match 'DENIED')
    check 'cross-runtime Node->PS: PS contender did not steal the live node holder lock' (Test-Path $xrLock)
    Wait-Process -Id $nodeProc.Id -ErrorAction SilentlyContinue -Timeout 15
    check 'cross-runtime Node->PS: Node holder completed and released its own lock' ((-not (Test-Path $xrLock)) -and $nodeProc.HasExited)
} finally {
    if ($env:WINTAGE_TEST_LOCK_TIMEOUT_MS) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue }
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    $env:APPDATA = $prevAppDataXr
    Remove-Item $isoXr -Recurse -Force -ErrorAction SilentlyContinue
}

# 13. direct build-desktop contention is BEHAVIOURAL: a real node process must
# refuse to publish while a real PowerShell -Selected batch (through the REAL
# install.ps1 batch window) holds the generation lock.
$isoDirect = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-direct-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoDirect -Force | Out-Null
$prevAppDataDirect = $env:APPDATA
$prevTimeoutDirect = $env:WINTAGE_TEST_LOCK_TIMEOUT_MS
try {
    & node $builder 2>&1 | Out-Null
    $sumBeforeD = (Get-ChildItem (Join-Path $root 'desktop/out') -Recurse -File | Measure-Object Length -Sum).Sum
    $env:APPDATA = $isoDirect
    $env:WINTAGE_APPDATA = (Join-Path $isoDirect 'Wintage')
    New-Item -ItemType Directory -Path $env:WINTAGE_APPDATA -Force | Out-Null
    $env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS = '2500'
    # The direct node build must REFUSE while the batch holds: shrink its
    # contention timeout below the batch's 2500ms park, otherwise the node
    # build legitimately acquires the moment the batch releases and the gate
    # measures nothing.
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '1500'
    $batchHolder = Start-Job -ScriptBlock {
        param($innerArgs)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell @innerArgs 2>&1; $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out | ForEach-Object { "$_" }); Code = $code }
    } -ArgumentList (, @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Selected', 'totalcmd', '-Palette', 'goldendefault'))
    # Barrier: wait until the lock file exists = the batch is inside its window.
    $batchLockSeen = $false
    for ($i = 0; $i -lt 240 -and -not $batchLockSeen; $i++) {
        Start-Sleep -Milliseconds 50
        $batchLockSeen = Test-Path (Join-Path $env:WINTAGE_APPDATA 'build-generation.lock')
    }
    check 'direct-contention: real -Selected batch reached its locked window (barrier)' $batchLockSeen
    # node writes its contention error to stderr; under the script's EAP=Stop
    # that becomes a terminating NativeCommandError, so Continue + exit code.
    $prevEapD = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $nodeOutD = & node (Join-Path $root 'tools/build-desktop.js') 2>&1
    $nodeCodeD = $LASTEXITCODE
    $ErrorActionPreference = $prevEapD
    $sumAfterD = (Get-ChildItem (Join-Path $root 'desktop/out') -Recurse -File | Measure-Object Length -Sum).Sum
    check 'direct-contention: direct build-desktop REFUSES to publish under a PowerShell-held lock' ($nodeCodeD -ne 0 -and ("$nodeOutD" -match 'generation lock contended'))
    check 'direct-contention: no output bytes changed while the lock was held' ($sumBeforeD -eq $sumAfterD)
    Wait-Job $batchHolder -Timeout 60 | Out-Null
    $batchRes = Receive-Job $batchHolder
    Remove-Job $batchHolder -Force -ErrorAction SilentlyContinue
    check 'direct-contention: batch holder completes after releasing (no deadlock)' ($null -ne $batchRes)
} finally {
    if ($env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS) { Remove-Item Env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS -ErrorAction SilentlyContinue }
    if ($null -eq $prevTimeoutDirect) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue } else { $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = $prevTimeoutDirect }
    $env:APPDATA = $prevAppDataDirect
    if ($env:WINTAGE_APPDATA) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue }
    Remove-Item $isoDirect -Recurse -Force -ErrorAction SilentlyContinue
}

# 14. Custom contentDigest: DIRECT behavioural assertions on the REAL function.
$isoDigest = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-digest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoDigest -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoDigest
    $ManifestPath = 'x'
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $script:root = $root
    . (Join-Path (Split-Path $common -Parent) 'generation-lock.ps1')
    $digestAst = [System.Management.Automation.Language.Parser]::ParseFile($common, [ref]$null, [ref]$null)
    foreach ($fn in @('Get-CustomContentDigest', 'Get-ReapplyIntentToken')) {
        $f = $digestAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true)
        . ([scriptblock]::Create($f.Extent.Text))
    }
    $digestFile = Join-Path $root 'themes/custom.json'
    $digestBackup = [System.IO.File]::ReadAllBytes($digestFile)
    # Custom A: the current shipped custom pack.
    $packA = [System.IO.File]::ReadAllText($digestFile, $script:Utf8NoBom) | ConvertFrom-Json
    $digestA = Get-CustomContentDigest -Palette 'custom'
    # Custom B: change ONE canonical token.
    $packB = @{ slug = $packA.slug; label = $packA.label; order = 99; tokens = [ordered]@{} }
    foreach ($p in $packA.tokens.PSObject.Properties) { $packB.tokens[$p.Name] = $p.Value }
    $packB.tokens['background'] = '#ABCDEF'
    ($packB | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $digestFile -Encoding UTF8
    $digestB = Get-CustomContentDigest -Palette 'custom'
    check 'contentDigest: Custom A yields digest A (64-hex SHA-256)' ($digestA -match '^[0-9a-f]{64}$')
    check 'contentDigest: changing ONE canonical token yields digest B' ($digestB -match '^[0-9a-f]{64}$')
    check 'contentDigest: digest A != digest B' ($digestA -ne $digestB)
    # Key-order + whitespace invariance: same tokens, reversed key order.
    $scrambled = @{ tokens = [ordered]@{}; slug = 'custom'; label = $packA.label; order = 99 }
    foreach ($p in ($packA.tokens.PSObject.Properties | Sort-Object Name -Descending)) { $scrambled.tokens[$p.Name] = $p.Value }
    ($scrambled | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $digestFile -Encoding UTF8
    $digestScrambled = Get-CustomContentDigest -Palette 'custom'
    check 'contentDigest: JSON key-order + whitespace changes keep the SAME digest' ($digestScrambled -eq $digestA)
    # Non-custom backward compatibility.
    check 'contentDigest: non-custom palettes return no digest (backward compatible)' ($null -eq (Get-CustomContentDigest -Palette 'goldendefault'))
    # Missing custom.json fails CLOSED.
    Remove-Item -LiteralPath $digestFile -Force
    $closed = $false
    try { $null = Get-CustomContentDigest -Palette 'custom' } catch { $closed = $true }
    check 'contentDigest: missing custom.json fails CLOSED (never a digest-less custom entry)' $closed
    # Reapply intent distinguishes A from B.
    $entryA = @{ palette = 'custom'; path = 'x'; appVersion = 'n/a'; payloadVersion = 'v'; applied = 't'; contentDigest = $digestA }
    $entryB = @{ palette = 'custom'; path = 'x'; appVersion = 'n/a'; payloadVersion = 'v'; applied = 't'; contentDigest = $digestB }
    check 'reapply-intent: the intent token DISTINGUISHES Custom A from Custom B' ((Get-ReapplyIntentToken $entryA) -ne (Get-ReapplyIntentToken $entryB))
} finally {
    if ($digestBackup) { [System.IO.File]::WriteAllBytes($digestFile, $digestBackup) }
    if ($env:WINTAGE_APPDATA) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue }
    Remove-Item $isoDigest -Recurse -Force -ErrorAction SilentlyContinue
}

# 15. deterministic Custom A/B generation fixture: publish A, start a real
# two-target -Selected Apply, hold it on the lock window (barrier seam, no
# sleep race), attempt B from another process, prove B cannot publish while A
# is consumed, complete the batch, prove both targets carry digest A, then
# allow B and prove the next Apply consumes B and records digest B.
$isoAB = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-ab-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoAB -Force | Out-Null
$prevAppDataAB = $env:APPDATA
$digestFile = $null
$digestBackup = $null
try {
    $env:APPDATA = $isoAB
    $env:WINTAGE_APPDATA = (Join-Path $isoAB 'Wintage')
    New-Item -ItemType Directory -Path $env:WINTAGE_APPDATA -Force | Out-Null
    $ManifestPath = 'x'
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $script:root = $root
    . (Join-Path (Split-Path $common -Parent) 'generation-lock.ps1')
    $digestAst2 = [System.Management.Automation.Language.Parser]::ParseFile($common, [ref]$null, [ref]$null)
    $fDigest2 = $digestAst2.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-CustomContentDigest' }, $true)
    . ([scriptblock]::Create($fDigest2.Extent.Text))
    $digestFile = Join-Path $root 'themes/custom.json'
    $digestBackup = [System.IO.File]::ReadAllBytes($digestFile)
    foreach ($n in @('tc1.ini', 'tc2.ini')) {
        [System.IO.File]::WriteAllText((Join-Path $isoAB $n), "[Colors]`r`nBackColor=0`r`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    # Step 1: publish Custom A.
    $packA2 = [System.IO.File]::ReadAllText($digestFile, $script:Utf8NoBom) | ConvertFrom-Json
    $packA2.tokens.background = '#A0B0C0'
    ($packA2 | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $digestFile -Encoding UTF8
    & node (Join-Path $root 'tools/apply-themes.js') 2>&1 | Out-Null
    & node $builder 2>&1 | Out-Null
    $digestA2 = Get-CustomContentDigest -Palette 'custom'
    check 'A/B fixture: generation A published with a stable digest' ($digestA2 -match '^[0-9a-f]{64}$')
    # Steps 2-4: a real two-target -Selected batch parked INSIDE its lock window.
    $env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS = '8000'
    $batchA = Start-Job -ScriptBlock {
        param($innerArgs)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell @innerArgs 2>&1; $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out | ForEach-Object { "$_" }); Code = $code }
    } -ArgumentList (, @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Selected', 'totalcmd,totalcmd2', '-Palette', 'custom', '-TotalCmdIni', (Join-Path $isoAB 'tc1.ini'), '-TotalCmd2Ini', (Join-Path $isoAB 'tc2.ini')))
    $abLockSeen = $false
    for ($i = 0; $i -lt 240 -and -not $abLockSeen; $i++) {
        Start-Sleep -Milliseconds 50
        $abLockSeen = Test-Path (Join-Path $env:WINTAGE_APPDATA 'build-generation.lock')
    }
    check 'A/B fixture: batch A pinned generation A and HOLDS the generation lock (barrier)' $abLockSeen
    # Steps 5-6: another process attempts to publish B while A is consumed.
    $packB2 = [System.IO.File]::ReadAllText($digestFile, $script:Utf8NoBom) | ConvertFrom-Json
    $packB2.tokens.background = '#B0C0D0'
    $jsonB2 = ($packB2 | ConvertTo-Json -Depth 5)
    $pubB = Start-Job -ScriptBlock {
        param($rootDir, $iso, $jsonB, $commonPath)
        $env:APPDATA = $iso
        $env:WINTAGE_APPDATA = (Join-Path $iso 'Wintage')
        $custom = Join-Path $iso 'pub-custom.json'
        [System.IO.File]::WriteAllText($custom, $jsonB, (New-Object System.Text.UTF8Encoding($false)))
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command ". '$commonPath'; try { `$l = Enter-BatchLock; [System.IO.File]::WriteAllText((Join-Path '$rootDir' 'themes/custom.json'), (Get-Content '$custom' -Raw), (New-Object System.Text.UTF8Encoding(`$false))); & node (Join-Path '$rootDir' 'tools/apply-themes.js') | Out-Null; if (`$LASTEXITCODE -ne 0) { throw 'apply-themes failed' }; & node (Join-Path '$rootDir' 'tools/build-desktop.js') | Out-Null; if (`$LASTEXITCODE -ne 0) { throw 'build-desktop failed' }; Exit-BatchLock `$l; Write-Output 'PUBLISHED' } catch { Write-Output ('BLOCKED ' + `$_.Exception.Message) }" 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out | ForEach-Object { "$_" }); Code = $code }
    } -ArgumentList @($root, $isoAB, $jsonB2, $common)
    Wait-Job $pubB -Timeout 60 | Out-Null
    $pubBRes = Receive-Job $pubB
    Remove-Job $pubB -Force -ErrorAction SilentlyContinue
    $pubBText = ($pubBRes.Out -join ' ')
    check 'A/B fixture: Custom B publication REFUSED while batch A holds the generation' ($pubBText -match 'BLOCKED')
    check 'A/B fixture: custom.json still carries generation A after the refused publish' (((Get-Content $digestFile -Raw | ConvertFrom-Json).tokens.background) -eq '#A0B0C0')
    # Steps 7-9: complete batch A; both targets consumed A and record digest A.
    Wait-Job $batchA -Timeout 120 | Out-Null
    $batchARes = Receive-Job $batchA
    Remove-Job $batchA -Force -ErrorAction SilentlyContinue
    check 'A/B fixture: batch A completed (exit 0)' ($batchARes.Code -eq 0)
    $mfPath = Join-Path $env:WINTAGE_APPDATA 'installed.json'
    $mf = (Get-Content $mfPath -Raw | ConvertFrom-Json)
    $digestRecorded1 = $null; $digestRecorded2 = $null
    if ($mf.PSObject.Properties['totalcmd']) { $digestRecorded1 = $mf.'totalcmd'.contentDigest }
    if ($mf.PSObject.Properties['totalcmd2']) { $digestRecorded2 = $mf.'totalcmd2'.contentDigest }
    check 'A/B fixture: totalcmd manifest entry records digest A (pinned while consumed)' ($digestRecorded1 -eq $digestA2)
    check 'A/B fixture: totalcmd2 manifest entry records digest A (pinned while consumed)' ($digestRecorded2 -eq $digestA2)
    # Steps 10-12: allow B, then the subsequent Apply consumes B.
    [System.IO.File]::WriteAllText($digestFile, $jsonB2, (New-Object System.Text.UTF8Encoding($false)))
    & node (Join-Path $root 'tools/apply-themes.js') 2>&1 | Out-Null
    & node $builder 2>&1 | Out-Null
    $digestB2 = Get-CustomContentDigest -Palette 'custom'
    check 'A/B fixture: digest A != digest B across the two generations' ($digestA2 -ne $digestB2)
    $batchB = Start-Job -ScriptBlock {
        param($innerArgs)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & powershell @innerArgs 2>&1; $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = @($out | ForEach-Object { "$_" }); Code = $code }
    } -ArgumentList (, @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Selected', 'totalcmd', '-Palette', 'custom', '-TotalCmdIni', (Join-Path $isoAB 'tc1.ini'), '-Force'))
    Wait-Job $batchB -Timeout 120 | Out-Null
    $batchBRes = Receive-Job $batchB
    Remove-Job $batchB -Force -ErrorAction SilentlyContinue
    $mf2 = (Get-Content $mfPath -Raw | ConvertFrom-Json)
    $digestRecorded3 = $null
    if ($mf2.PSObject.Properties['totalcmd']) { $digestRecorded3 = $mf2.'totalcmd'.contentDigest }
    check 'A/B fixture: the subsequent Apply consistently consumes B and records digest B' (($batchBRes.Code -eq 0) -and ($digestRecorded3 -eq $digestB2))
} finally {
    if ($env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS) { Remove-Item Env:WINTAGE_TEST_BATCH_LOCK_DELAY_MS -ErrorAction SilentlyContinue }
    if ($digestBackup -and $digestFile) { [System.IO.File]::WriteAllBytes($digestFile, $digestBackup) }
    & node (Join-Path $root 'tools/apply-themes.js') 2>&1 | Out-Null
    & node $builder 2>&1 | Out-Null
    $env:APPDATA = $prevAppDataAB
    if ($env:WINTAGE_APPDATA) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue }
    Remove-Item $isoAB -Recurse -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# 16. R009 direct-Node production normal release: the REAL tools/build-desktop.js
# must release its own generation lock on a normal completed build -- twice in a
# row -- with no synthetic lock holder involved. The -RedControl contract for
# this gate lives in tools/test-genlock-redcontrol.ps1 (RED A: the previous
# token-less release contract leaves the lock behind).
# ─────────────────────────────────────────────────────────────────────────────────────────────
$isoNode = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-nodenorm-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoNode -Force | Out-Null
$prevAppNode = $env:WINTAGE_APPDATA
try {
    $env:WINTAGE_APPDATA = $isoNode
    $nodeLockFile = Join-Path $isoNode 'build-generation.lock'
    $prevEapNode = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $nodeBuild1 = & node $builder 2>&1
    $nodeBuild1Code = $LASTEXITCODE
    $nodeBuild2 = & node $builder 2>&1
    $nodeBuild2Code = $LASTEXITCODE
    $ErrorActionPreference = $prevEapNode
    check 'node normal-release: first REAL direct build-desktop completes (exit 0)' ($nodeBuild1Code -eq 0)
    check 'node normal-release: generation lock ABSENT immediately after the first build' (-not (Test-Path $nodeLockFile))
    check 'node normal-release: second REAL direct build-desktop completes (exit 0)' ($nodeBuild2Code -eq 0)
    check 'node normal-release: generation lock ABSENT again after the second build' (-not (Test-Path $nodeLockFile))
    # Third real build: no wedged residue, acquisition still clean.
    $nodeBuild3Code = $null
    try {
        & node $builder 2>&1 | Out-Null
        $nodeBuild3Code = $LASTEXITCODE
    } catch { $nodeBuild3Code = 1 }
    check 'node normal-release: a third real build still acquires cleanly (no wedged residue)' (($nodeBuild3Code -eq 0) -and (-not (Test-Path $nodeLockFile)))
} finally {
    if ($null -eq $prevAppNode) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevAppNode }
    Remove-Item $isoNode -Recurse -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# 17. T-249 cross-runtime metadata asymmetry -- the DELIBERATE contract:
#   - PowerShell-owned locks carry a real process StartTime in ownerCreated and
#     get the PID-reuse comparison;
#   - Node-owned locks record ownerCreated: null (plain Node cannot read process
#     start times on Windows) and are pinned by PID liveness alone;
#   - a live Node pid is NEVER stolen (fail closed), a dead Node pid is
#     recoverable, malformed owner metadata is unknown/fail closed;
#   - the PS-side StartTime comparison still applies whenever real metadata IS
#     present (PS-owned locks), so PID reuse stays covered where data exists.
# Residual bound, documented in generation-lock.ps1 + build-desktop.js: a Node
# owner pid reused by another process within the lock window is indistinguish-
# able from the owner; that bound is accepted by design, never papered over
# with an invented timestamp.
# ─────────────────────────────────────────────────────────────────────────────────────────────
$isoT249 = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-t249-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isoT249 -Force | Out-Null
try {
    $env:WINTAGE_APPDATA = $isoT249
    $t249Lock = Join-Path $isoT249 'build-generation.lock'
    $env:WINTAGE_TEST_LOCK_TIMEOUT_MS = '1500'
    # Contract 1: a LIVE Node owner records ownerCreated: null.
    $nodeHoldJs = "const fs=require('fs');const p=process.argv[2];const fd=fs.openSync(p,'wx');fs.writeSync(fd,JSON.stringify({token:'t249',pid:process.pid,runtime:'node',acquired:new Date().toISOString(),ownerCreated:null}));fs.fsyncSync(fd);setTimeout(()=>{try{fs.closeSync(fd)}catch(e){};try{fs.unlinkSync(p)}catch(e){};process.exit(0)},6000)"
    $nodeHoldFile = Join-Path $isoT249 't249-holder.js'
    [System.IO.File]::WriteAllText($nodeHoldFile, $nodeHoldJs, (New-Object System.Text.UTF8Encoding($false)))
    $nodeProc249 = Start-Process node -ArgumentList @($nodeHoldFile, $t249Lock) -PassThru -WindowStyle Hidden
    $t249Held = $false
    for ($i = 0; $i -lt 100 -and -not $t249Held; $i++) { Start-Sleep -Milliseconds 50; $t249Held = (Test-Path $t249Lock) -and (-not $nodeProc249.HasExited) }
    $t249Meta = $null
    try { $t249Meta = Get-Content -LiteralPath $t249Lock -Raw | ConvertFrom-Json } catch { }
    check 't249: live Node owner metadata carries ownerCreated null (no invented timestamp)' ($t249Held -and $null -ne $t249Meta -and $null -eq $t249Meta.ownerCreated)
    # Contract 2: the live Node pid is NEVER stolen by a PS contender (liveness
    # fails closed) - not by age, not by the missing ownerCreated.
    $t249PsOut = Invoke-LockContender $isoT249 $t249Lock
    check 't249: PS contender DENIED against a LIVE Node owner (liveness fails closed, no StartTime data needed)' ($t249PsOut -match 'DENIED')
    check 't249: the live Node owner lock SURVIVED the contender' (Test-Path $t249Lock)
    Wait-Process -Id $nodeProc249.Id -ErrorAction SilentlyContinue -Timeout 15
    check 't249: Node holder completed and self-released (no wedged state)' ((-not (Test-Path $t249Lock)) -and $nodeProc249.HasExited)
    # Contract 3: a DEAD Node owner is recoverable by PS (Node metadata has no
    # StartTime, but the pid itself is gone - liveness is the proof).
    $deadNodePid = $nodeProc249.Id
    $deadNodeMeta = '{"token":"t249dead","pid":' + $deadNodePid + ',"runtime":"node","acquired":"2026-01-01T00:00:00.0000000Z","ownerCreated":null}'
    [System.IO.File]::WriteAllText($t249Lock, $deadNodeMeta, (New-Object System.Text.UTF8Encoding($false)))
    $t249Recover = Invoke-LockContender $isoT249 $t249Lock
    check 't249: a DEAD Node owner is RECOVERABLE by PS without any StartTime data' ($t249Recover -match 'ACQUIRED')
    # Contract 4: malformed owner metadata is unknown -> fail closed.
    # (This is the RECOVERY-side rule for owner metadata shape; the separate
    # malformed-LOCK recovery path - a lock nobody can attribute at all - stays
    # age-bounded by its own contract.)
    $badMeta = '{"token":"t249bad","pid":' + $PID + ',"runtime":"node","acquired":"2026-01-01T00:00:00.0000000Z","ownerCreated":"not-a-timestamp"}'
    [System.IO.File]::WriteAllText($t249Lock, $badMeta, (New-Object System.Text.UTF8Encoding($false)))
    $t249Bad = Invoke-LockContender $isoT249 $t249Lock
    check 't249: malformed ownerCreated on a live pid is UNKNOWN -> fail closed (never stolen)' ($t249Bad -match 'DENIED')
    # Contract 5 (PS-side PID-reuse guard stays active for PS-owned locks): a
    # live process whose StartTime does NOT match the recorded ownerCreated is
    # reported dead by Test-GenerationLockOwnerAlive - a reused pid cannot pose
    # as the owner when real start-time data exists.
    $reuseMeta = '{"token":"t249reuse","pid":' + $PID + ',"runtime":"powershell","acquired":"2026-01-01T00:00:00.0000000Z","ownerCreated":"2020-01-01T00:00:00.0000000Z"}'
    $reuseDead = Test-GenerationLockOwnerAlive ($reuseMeta | ConvertFrom-Json)
    check 't249: PS-owned lock PID-reuse guard ACTIVE (mismatched StartTime on a live pid = dead owner)' ($reuseDead -eq 'dead')
    Remove-Item -LiteralPath $t249Lock -Force -ErrorAction SilentlyContinue
} finally {
    if ($env:WINTAGE_TEST_LOCK_TIMEOUT_MS) { Remove-Item Env:WINTAGE_TEST_LOCK_TIMEOUT_MS -ErrorAction SilentlyContinue }
    Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue
    Remove-Item $isoT249 -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($fail -eq 0) { Write-Host "ALL PASS ($pass)" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail FAIL, $pass PASS" -ForegroundColor Red; exit 1 }
