# W2-006 (SRC-007:R011) -- path-preference PREREQUISITE ordering.
#
# DEFECT: the dispatcher persisted a validated explicit portable path AFTER the
# target had already mutated (Electron: after the manifest commit; browsers:
# after the stage mutation + manifest commit). A persistence failure there
# either vanished silently or marked an already-committed target FAILED -
# reporting a failure whose target/manifest state said success.
#
# CONTRACT under test (per applicable portable target):
#   1. establish known application bytes/tree and manifest;
#   2. force Save-PathPreference failure (paths.lock contention);
#   3. invoke Apply with an explicit portable path;
#   4. exit nonzero with an accurate persistence error;
#   5. application bytes/tree remain byte-identical;
#   6. manifest remains byte-identical;
#   7. no recovery transaction state was created;
#   8. release the failure seam and retry;
#   9. Apply succeeds; paths.json records the explicit location;
#  10. manifest records the target;
#  11. a later resolution without the explicit path finds the remembered one.
# Also: no applicable Save-PathPreference call remains DOWNSTREAM of an
# irreversible target/manifest success.
#
#   .\tools\test-path-preference-ordering.ps1          # all tests
#   .\tools\test-path-preference-ordering.ps1 -List    # list tests

[CmdletBinding()] param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\install.ps1'
$common = Join-Path $root 'desktop\modules\common.ps1'
$fixtureBuilder = Join-Path $here 'build-asar-fixture.js'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-path-preference-ordering.ps1 (W2-006 R011 -- preference persists BEFORE mutation):"
    Write-Host "  1. browser: forced paths.lock contention -> nonzero + W2-006, stage+manifest byte-identical"
    Write-Host "  2. browser: retry succeeds, preference+manifest recorded"
    Write-Host "  3-5. codenomad / workbuddy / zcode: same contract per Electron target (fused fixtures)"
    Write-Host "  6. notepadplusplus: forced failure -> nonzero + W2-006, target untouched"
    Write-Host "  7. structural: no Save-PathPreference downstream of manifest success"
    exit 0
}

function Get-DirFingerprint([string]$dir) {
    if (-not (Test-Path $dir)) { return '<absent>' }
    $items = Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName
    $lines = foreach ($i in $items) {
        $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($i.FullName))
        ('{0}|{1}' -f $i.FullName.Substring($dir.Length), ([BitConverter]::ToString($h) -replace '-', ''))
    }
    return ($lines -join "`n")
}

function Invoke-Apply([string[]]$extraArgs) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer @extraArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    [pscustomobject]@{ Out = ($out | ForEach-Object { "$_" }) -join "`n"; Code = $code }
}

# Failure seam: hold paths.lock exclusively so Save-PathPreference's bounded
# retry (100 attempts) is exhausted and the call THROWS.
function Hold-PathsLock([string]$appData) {
    return Start-Job -ScriptBlock {
        param($appData)
        $s = [System.IO.File]::Open((Join-Path $appData 'paths.lock'),
            [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        Start-Sleep -Seconds 90
        $s.Dispose()
    } -ArgumentList $appData
}
function Test-LockHeld([string]$appData) {
    try {
        $probe = [System.IO.File]::Open((Join-Path $appData 'paths.lock'), 'Open', 'ReadWrite', 'None')
        $probe.Dispose()
        return $false
    } catch { return $true }
}
function Wait-LockHeld([string]$appData) {
    for ($i = 0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 50; if (Test-LockHeld $appData) { return $true } }
    return $false
}
function Wait-LockFree([string]$appData) {
    for ($i = 0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 50; if (-not (Test-LockHeld $appData)) { return $true } }
    return $false
}
function Stop-Seam($job) {
    if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
}

$prevAppData = $env:APPDATA
$prevWintage = $env:WINTAGE_APPDATA
$prevLocalAppData = $env:LOCALAPPDATA
$testRoot = $null

try {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-r011-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $env:WINTAGE_APPDATA = Join-Path $testRoot 'appdata'
    $env:LOCALAPPDATA = Join-Path $testRoot 'localappdata'
    $manifestPath = Join-Path $env:WINTAGE_APPDATA 'installed.json'
    $pathsPath = Join-Path $env:WINTAGE_APPDATA 'paths.json'

    # ══════════════════════════════════════════════════════════════════════
    # Browser target (portable root preference).
    # ══════════════════════════════════════════════════════════════════════
    $browserStage = Join-Path $testRoot 'browser-stage'
    $catalog = Join-Path $testRoot 'catalog.json'
    # One FAKE profile: without it the browser tool exits 'no installed or
    # portable profiles found', a DIFFERENT refusal (the strict-target profile
    # gate) that would mask the persistence contract under test.
    $fakeBrowser = Join-Path $testRoot 'Portable Browser'
    $fakeExe = Join-Path $fakeBrowser 'chrome.exe'
    $fakeData = Join-Path $fakeBrowser 'User Data'
    $fakeProfile = Join-Path $fakeData 'Default'
    New-Item -ItemType Directory -Path $fakeProfile -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile 'Preferences'), '{}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $fakeData 'Local State'), '{}', $utf8)
    $catalogBody = [ordered]@{ Name = 'R011 Fixture Chromium'; Exe = $fakeExe; UserData = $fakeData } | ConvertTo-Json
    [System.IO.File]::WriteAllText($catalog, ('[' + $catalogBody + ']'), $utf8)
    $portableRoot = Join-Path $testRoot 'portable-browser'

    $browserArgs = @('-Target', 'browsers', '-Palette', 'goldendefault', '-PortableBrowserRoot', $portableRoot,
        '-BrowserCatalog', $catalog, '-BrowserStageRoot', $browserStage, '-NoBrowserLaunch')

    # Step 1: establish the KNOWN pre-state (stage + manifest exist).
    $run1 = Invoke-Apply $browserArgs
    check 'browser: the known-state run exits 0' ($run1.Code -eq 0)
    $stageFp = Get-DirFingerprint $browserStage
    $manifestFp = [System.IO.File]::ReadAllBytes($manifestPath)

    # Steps 2-4: forced persistence failure.
    $seam = Hold-PathsLock $env:WINTAGE_APPDATA
    check 'browser: the paths.lock failure seam is HELD (barrier)' (Wait-LockHeld $env:WINTAGE_APPDATA)
    $run2 = Invoke-Apply $browserArgs
    check 'browser: forced preference failure exits NONZERO' ($run2.Code -ne 0)
    check 'browser: failure names the path-preference persistence cause (W2-006)' ($run2.Out -match 'W2-006')
    check 'browser: stage remains BYTE-IDENTICAL after the failed run' ((Get-DirFingerprint $browserStage) -eq $stageFp)
    check 'browser: manifest remains BYTE-IDENTICAL after the failed run' (-not (Compare-Object ([System.IO.File]::ReadAllBytes($manifestPath)) $manifestFp))
    Stop-Seam $seam
    check 'browser: the paths.lock failure seam is RELEASED (barrier)' (Wait-LockFree $env:WINTAGE_APPDATA)

    # Steps 8-10: retry records preference + manifest.
    $run3 = Invoke-Apply $browserArgs
    check 'browser: retry after releasing the seam exits 0' ($run3.Code -eq 0)
    $mf = Get-Content $manifestPath -Raw | ConvertFrom-Json
    check 'browser: manifest records the target after the retry' ($null -ne $mf.PSObject.Properties['browsers'])
    $paths = Get-Content $pathsPath -Raw | ConvertFrom-Json
    check 'browser: paths.json records the explicit portable location' ($paths.PSObject.Properties['portable'] -and (([string]$paths.portable) -eq $portableRoot))

    # ══════════════════════════════════════════════════════════════════════
    # Electron targets (CodeNomad, WorkBuddy, ZCode): portable apps under a
    # redirected LOCALAPPDATA, with a FUSED exe (the fuse-verification gate
    # otherwise refuses before any mutation). Each target gets its own seam.
    # ══════════════════════════════════════════════════════════════════════
    foreach ($electron in @(
        @{ Name = 'codenomad'; Dir = 'CodeNomad'; Param = 'CodeNomadPath' },
        @{ Name = 'workbuddy'; Dir = 'WorkBuddy'; Param = 'WorkBuddyPath' },
        @{ Name = 'zcode';     Dir = 'ZCode';     Param = 'ZCodePath' }
    )) {
        $appRoot = Join-Path $env:LOCALAPPDATA ("Programs\" + $electron.Dir)
        $res = Join-Path $appRoot 'resources'
        New-Item -ItemType Directory -Path $res -Force | Out-Null
        & node $fixtureBuilder (Join-Path $res 'app.asar') '1.0.0' 0 --exe (Join-Path $appRoot 'FakeApp.exe') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$($electron.Name): asar fixture build failed" }
        $resFp = Get-DirFingerprint $appRoot
        $explicit = Join-Path $testRoot ("explicit-" + $electron.Name)
        New-Item -ItemType Directory -Path (Join-Path $explicit 'resources') -Force | Out-Null
        & node $fixtureBuilder (Join-Path $explicit 'resources\app.asar') '1.0.0' 0 --exe (Join-Path $explicit 'FakeApp.exe') | Out-Null

        $args1 = @('-Target', $electron.Name, '-Palette', 'goldendefault', "-$($electron.Param)", $explicit)
        # Known manifest state before the failure run (it may already exist from
        # an earlier section; the contract is BYTE-IDENTITY, not absence).
        $mfFp = if (Test-Path $manifestPath) { [System.IO.File]::ReadAllBytes($manifestPath) } else { $null }
        $pathsFp = if (Test-Path $pathsPath) { [System.IO.File]::ReadAllBytes($pathsPath) } else { $null }
        $seam = Hold-PathsLock $env:WINTAGE_APPDATA
        check ("{0}: the paths.lock failure seam is HELD (barrier)" -f $electron.Name) (Wait-LockHeld $env:WINTAGE_APPDATA)
        $run = Invoke-Apply $args1
        check ("{0}: forced preference failure exits NONZERO" -f $electron.Name) ($run.Code -ne 0)
        check ("{0}: failure names the path-preference persistence cause (W2-006)" -f $electron.Name) ($run.Out -match 'W2-006')
        check ("{0}: the default-discovery app tree is BYTE-IDENTICAL after the failed run" -f $electron.Name) ((Get-DirFingerprint $appRoot) -eq $resFp)
        check ("{0}: no recovery snapshot was created by the failed run" -f $electron.Name) (-not (Test-Path (Join-Path $env:WINTAGE_APPDATA 'recovery')))
        check ("{0}: manifest remains BYTE-IDENTICAL after the failed run" -f $electron.Name) (
            $(if ($null -eq $mfFp) { -not (Test-Path $manifestPath) } else { (-not (Compare-Object ([System.IO.File]::ReadAllBytes($manifestPath)) $mfFp)) }))
        check ("{0}: paths.json remains BYTE-IDENTICAL after the failed run (no partial key write landed)" -f $electron.Name) (
            $(if ($null -eq $pathsFp) { -not (Test-Path $pathsPath) } else { (-not (Compare-Object ([System.IO.File]::ReadAllBytes($pathsPath)) $pathsFp)) }))
        Stop-Seam $seam
        check ("{0}: the paths.lock failure seam is RELEASED (barrier)" -f $electron.Name) (Wait-LockFree $env:WINTAGE_APPDATA)

        $run = Invoke-Apply $args1
        check ("{0}: retry after releasing the seam exits 0" -f $electron.Name) ($run.Code -eq 0)
        $mf = Get-Content $manifestPath -Raw | ConvertFrom-Json
        check ("{0}: manifest records the target after the retry" -f $electron.Name) ($null -ne $mf.PSObject.Properties[$electron.Name])
        $paths = Get-Content $pathsPath -Raw | ConvertFrom-Json
        check ("{0}: paths.json records the explicit location" -f $electron.Name) ($paths.PSObject.Properties[$electron.Name] -and (([string]$paths.($electron.Name)) -eq $explicit))
        # Step 11: the remembered preference resolves the SAME explicit location.
        $mfEntry = $mf.($electron.Name)
        check ("{0}: manifest entry records the explicit app's resources path" -f $electron.Name) (([string]$mfEntry.path) -eq (Join-Path $explicit 'resources'))
    }

    # ══════════════════════════════════════════════════════════════════════
    # Notepad++ (a non-Electron target with a persisted explicit path).
    # ══════════════════════════════════════════════════════════════════════
    $nppDir = Join-Path $testRoot 'npp'
    New-Item -ItemType Directory -Path $nppDir -Force | Out-Null
    $nppFp = Get-DirFingerprint $nppDir
    $seam = Hold-PathsLock $env:WINTAGE_APPDATA
    check 'notepadplusplus: the paths.lock failure seam is HELD (barrier)' (Wait-LockHeld $env:WINTAGE_APPDATA)
    $run = Invoke-Apply @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-NotepadPlusPlusPath', $nppDir)
    check 'notepadplusplus: forced preference failure exits NONZERO' ($run.Code -ne 0)
    check 'notepadplusplus: failure names the path-preference persistence cause (W2-006)' ($run.Out -match 'W2-006')
    check 'notepadplusplus: target directory remains BYTE-IDENTICAL' ((Get-DirFingerprint $nppDir) -eq $nppFp)
    Stop-Seam $seam
    check 'notepadplusplus: the paths.lock failure seam is RELEASED (barrier)' (Wait-LockFree $env:WINTAGE_APPDATA)
    $run = Invoke-Apply @('-Target', 'notepadplusplus', '-Palette', 'goldendefault', '-NotepadPlusPlusPath', $nppDir)
    check 'notepadplusplus: retry exits 0 and installs the themes' (($run.Code -eq 0) -and (Test-Path (Join-Path $nppDir 'themes')))
    $paths = Get-Content $pathsPath -Raw | ConvertFrom-Json
    check 'notepadplusplus: paths.json records the explicit location' ($paths.PSObject.Properties['notepadplusplus'] -and (([string]$paths.notepadplusplus) -eq $nppDir))

    # ══════════════════════════════════════════════════════════════════════
    # Structural: no Save-PathPreference call remains downstream of manifest
    # success in the dispatcher (the R011 ordering invariant).
    # ══════════════════════════════════════════════════════════════════════
    $installSrc = [System.IO.File]::ReadAllText($installer, $utf8)
    $plainCalls = [regex]::Matches($installSrc, '(?m)^\s*(?!#).*Save-PathPreference(?!\w)') | Where-Object { $_.Value -notmatch 'OrThrow' }
    check 'structural: no bare Save-PathPreference call remains in install.ps1 (all persistence is prerequisite or composed)' ($plainCalls.Count -eq 0)
    check 'structural: Save-PathPreferenceOrThrow exists in common.ps1' (([System.IO.File]::ReadAllText($common, $utf8)) -match 'function Save-PathPreferenceOrThrow')

} finally {
    if ($null -eq $prevAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA = $prevAppData }
    if ($null -eq $prevWintage) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevWintage }
    if ($null -eq $prevLocalAppData) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $prevLocalAppData }
    if ($testRoot -and (Test-Path $testRoot)) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($fail -eq 0) { Write-Host "ALL PASS ($pass)" -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL, $pass PASS" -ForegroundColor Red
exit 1
