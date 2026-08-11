# Reapply + manifest + SmartVac regression suite (T-187).
#
# Everything here runs against a UNIQUE temp app-data root injected through
# WINTAGE_APPDATA. The live %APPDATA%\Wintage\installed.json is never read or
# written, even transiently -- that isolation is itself one of the tests.
#
#   .\tools\test-reapply.ps1          # all tests
#   .\tools\test-reapply.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $here '..\desktop\install.ps1'
$common = Join-Path $here '..\desktop\modules\common.ps1'
$pass = 0; $fail = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-reapply.ps1:"
    Write-Host "  1. semver-compare-is-semantic-not-string"
    Write-Host "  2. up-to-date-payload-is-skipped"
    Write-Host "  3. outdated-payload-is-detected-under-whatif"
    Write-Host "  4. empty-manifest-reports-nothing-to-do"
    Write-Host "  5. corrupt-manifest-is-not-overwritten"
    Write-Host "  6. manifest-atomic-round-trip"
    Write-Host "  7. rediscovery-finds-moved-target"
    Write-Host "  8. child-failure-bubbles-to-exit-code"
    Write-Host "  9. smartvac-apply-repaint-revert-byte-identical"
    Write-Host " 10. zero-anchor-source-fails-hard-and-recovers"
    Write-Host " 11. full-chain-apply-reapply-repaint-revert"
    Write-Host " 12. corrupt-manifest-status-reports-clearly"
    Write-Host " 13. electron-helper-failure-bubbles-and-dryrun"
    exit 0
}

# ------------------------------------------------------------------ fixture
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-reapply-test-" + [guid]::NewGuid().ToString('N'))
$appData = Join-Path $testRoot 'appdata'
$svDirA = Join-Path $testRoot 'smartvac-a'
$svDirB = Join-Path $testRoot 'smartvac-b'
$wrDir = Join-Path $testRoot 'wildrift'
New-Item -ItemType Directory -Path $appData, $svDirA, $wrDir -Force | Out-Null

$prevAppData = $env:WINTAGE_APPDATA
$env:WINTAGE_APPDATA = $appData

# A realistic SMART VAC CLEANER source: every anchor this target patches, each
# appearing EXACTLY once. Any missing anchor must make apply fail hard.
$svSource = @'
import os

WIN95_BG           = '#010203'
WIN95_BG_SOFT      = '#010203'
WIN95_SURFACE      = '#010203'
WIN95_SURFACE_RAISED = '#010203'
WIN95_SURFACE_ALT  = '#010203'
WIN95_BEVEL_HI     = '#010203'
WIN95_BEVEL_SH     = '#010203'
WIN95_BORDER_MUTED = '#010203'
WIN95_TEXT         = '#010203'
WIN95_TEXT_DIM     = '#010203'
WIN95_TEXT_MUTED   = '#010203'
WIN95_GOLD         = '#010203'
WIN95_GOLD_LIGHT   = '#010203'
WIN95_GOLD_DIM     = '#010203'
WIN95_GOLD_DARK    = '#010203'
WIN95_RED          = '#010203'
WIN95_DANGER       = '#010203'
WIN95_GREEN        = '#010203'
WIN95_BUTTON       = '#010203'
WIN95_BUTTON_HOVER = '#010203'
WIN95_ENTRY        = '#010203'
WIN95_SCROLL       = '#010203'
WIN95_SCROLL_HOVER = '#010203'
'@

$wrSource = @'
TOKENS = {
    "keep": "#010203",
}
'@

function Write-PathsJson($map) {
    [System.IO.File]::WriteAllText((Join-Path $appData 'paths.json'), ($map | ConvertTo-Json), $utf8NoBom)
}

function Read-TestManifest {
    $mPath = Join-Path $appData 'installed.json'
    if (-not (Test-Path $mPath)) { return @{} }
    $o = ([System.IO.File]::ReadAllText($mPath, $utf8NoBom)) | ConvertFrom-Json
    $ht = @{}
    foreach ($prop in $o.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
    $ht
}

function Clean-TestState {
    if (Test-Path $appData) { Remove-Item $appData -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $appData -Force | Out-Null
}

# Every smartvac fixture must start from a PRISTINE source with no leftover
# backup -- a stray .bak from a previous fixture would poison the revert
# byte-identity assertion.
function Reset-SmartVacDir([string]$dir = $svDirB) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir '_SMART_VAC_CLEANER.py'), $svSource, $utf8NoBom)
}

try {

# ---- Test 1: version comparison is semantic, never string ----
. $common
check 'semver 1.9.0 is OLDER than 1.26.3 (needs reapply)' (-not (Test-PayloadUpToDate '1.9.0' '1.26.3'))
check 'semver 1.10.0 is NEWER than 1.9.0 (up to date)' (Test-PayloadUpToDate '1.10.0' '1.9.0')
check 'semver equal versions are up to date' (Test-PayloadUpToDate '1.26.3' '1.26.3')
check 'semver malformed recorded version is never up to date' (-not (Test-PayloadUpToDate 'garbage' '1.26.3'))
check 'semver malformed current version is never up to date' (-not (Test-PayloadUpToDate '1.26.3' 'garbage'))
check 'semver missing recorded version is never up to date' (-not (Test-PayloadUpToDate '' '1.26.3'))

# ---- Test 2: up-to-date payload is skipped ----
Clean-TestState
@{windows=@{palette='goldendefault';path='C:\nonexistent';appVersion='n/a';payloadVersion='99.99.99';applied='2026-01-01T00:00:00Z'}} | ConvertTo-Json |
    ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'up-to-date version is skipped' ($out -match 'up to date')
check 'reapply of an up-to-date manifest exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 3: outdated version is detected under -WhatIf ----
Clean-TestState
@{windows=@{palette='goldendefault';path='C:\nonexistent';appVersion='n/a';payloadVersion='1.9.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
    ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
check 'outdated version is detected via -WhatIf' ($out -match 'What if')
check '-WhatIf reapply exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 4: empty manifest reports nothing to do ----
Clean-TestState
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'empty manifest reports nothing to do' ($out -match 'Nothing to do')
check 'empty-manifest reapply exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 5: corrupt manifest is NOT overwritten by a mutation ----
Clean-TestState
$mPath = Join-Path $appData 'installed.json'
$garbage = '{ this is not json at all'
[System.IO.File]::WriteAllText($mPath, $garbage, $utf8NoBom)
$script:WintageAppData = $appData
$script:ManifestPath = $mPath
$script:PathsPath = Join-Path $appData 'paths.json'
$script:Utf8NoBom = $utf8NoBom
$threw = $false
try { Set-ManifestEntry 'windows' 'golden' 'C:\x' 'n/a' '1.0.0' } catch { $threw = $true }
check 'Set-ManifestEntry refuses to work on a corrupt manifest' $threw
check 'corrupt manifest bytes survive untouched' ([System.IO.File]::ReadAllText($mPath, $utf8NoBom) -eq $garbage)

# ---- Test 6: manifest atomic round-trip ----
Clean-TestState
$threw = $false
try {
    Set-ManifestEntry 'roundtrip' 'golden' 'C:\rt' '1.0' '2.0'
    $m1 = Read-Manifest
    $ok1 = $m1.Count -eq 1 -and $m1['roundtrip'].palette -eq 'golden'
    Remove-ManifestEntry 'roundtrip'
    $m2 = Read-Manifest
    $ok2 = $m2.Count -eq 0
    $noTmp = -not (Test-Path ($mPath + '.tmp'))
    check 'manifest set+remove round-trip' ($ok1 -and $ok2)
    check 'atomic write leaves no .tmp behind' $noTmp
} catch { check 'manifest atomic round-trip' $false; check 'atomic write leaves no .tmp behind' $false }

# ---- Test 7: rediscovery finds the MOVED target, not the stale manifest path ----
Clean-TestState
$svFileA = Join-Path $svDirA '_SMART_VAC_CLEANER.py'
[System.IO.File]::WriteAllText($svFileA, $svSource, $utf8NoBom)
Write-PathsJson @{ smartvac = $svDirA }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac 2>&1 | Out-Null
check 'initial smartvac apply exits 0' ($LASTEXITCODE -eq 0)
$mAfterApply = Read-TestManifest
check 'initial apply records path A in the manifest' ($mAfterApply.smartvac.path -eq $svFileA)

# Simulate the app moving: A is gone, B is where it lives now. The manifest still
# says A. The user's remembered path (paths.json) is updated to B. A payload bump
# makes the recorded version outdated, which is what triggers -Reapply.
Copy-Item $svDirA $svDirB -Recurse -Force
Remove-Item $svDirA -Recurse -Force
Write-PathsJson @{ smartvac = $svDirB }
$mStale = Read-TestManifest
$mStale.smartvac.payloadVersion = '1.9.0'
$mStale | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'reapply after move exits 0' ($LASTEXITCODE -eq 0)
$mAfterReapply = Read-TestManifest
check 'reapply records the NEW path B, not the stale manifest path A' ($mAfterReapply.smartvac.path -eq (Join-Path $svDirB '_SMART_VAC_CLEANER.py'))
$themedB = [System.IO.File]::ReadAllText((Join-Path $svDirB '_SMART_VAC_CLEANER.py'), $utf8NoBom)
$pack = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
check 'the moved target file at B is actually themed' ($themedB -match [regex]::Escape($pack.tokens.background))

# ---- Test 8: a failing child bubbles to a nonzero exit, a sibling still applies ----
Clean-TestState
Reset-SmartVacDir
$wrFile = Join-Path $wrDir 'theme.py'
if (Test-Path ($wrFile + '.bak')) { Remove-Item ($wrFile + '.bak') -Force }
[System.IO.File]::WriteAllText($wrFile, $wrSource, $utf8NoBom)
Write-PathsJson @{ smartvac = $svDirB; wildrift = $wrDir }
# smartvac requests a palette that does not exist -> its child MUST fail hard.
# wildrift is valid -> it must still be applied (siblings preserved).
@{ smartvac = @{ palette = 'nosuchpalette'; path = (Join-Path $svDirB '_SMART_VAC_CLEANER.py'); appVersion = 'n/a'; payloadVersion = '1.9.0'; applied = '2020-01-01T00:00:00Z' }
   wildrift = @{ palette = 'goldendefault'; path = $wrFile; appVersion = 'n/a'; payloadVersion = '1.9.0'; applied = '2020-01-01T00:00:00Z' } } |
    ConvertTo-Json -Depth 3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'reapply with one failing child exits NONZERO' ($LASTEXITCODE -ne 0)
check 'the failing target is named in the output' ($out -match 'FAILED' -and $out -match 'nosuchpalette')
$wrThemed = [System.IO.File]::ReadAllText($wrFile, $utf8NoBom)
check 'the successful sibling is still applied' ($wrThemed -match [regex]::Escape($pack.tokens.background))
$mAfterFail = Read-TestManifest
# The failed target's manifest entry must NOT have been refreshed: a failed child
# never writes, so its recorded version stays the stale one.
check 'failed target manifest entry is NOT refreshed' ($mAfterFail.smartvac.payloadVersion -eq '1.9.0')
# The successful sibling's entry IS refreshed to the current payload version.
$currentVer = (([System.IO.File]::ReadAllText((Join-Path $root 'wintage.user.js'), $utf8NoBom) -split "`n") | Where-Object { $_ -match '// @version\s+(\S+)' } | Select-Object -First 1) -replace '.*@version\s+(\S+).*', '$1'
check 'successful sibling manifest entry IS refreshed' ($mAfterFail.wildrift.palette -eq 'goldendefault' -and $mAfterFail.wildrift.payloadVersion -eq $currentVer)

# ---- Test 9: SmartVac apply -> repaint -> revert is byte-identical to the original ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$original = [System.IO.File]::ReadAllBytes((Join-Path $svDirB '_SMART_VAC_CLEANER.py'))
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'smartvac apply A exits 0' ($LASTEXITCODE -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette dracula 2>&1 | Out-Null
check 'smartvac apply B (repaint) exits 0' ($LASTEXITCODE -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Revert 2>&1 | Out-Null
check 'smartvac revert exits 0' ($LASTEXITCODE -eq 0)
$after = [System.IO.File]::ReadAllBytes((Join-Path $svDirB '_SMART_VAC_CLEANER.py'))
check 'smartvac A->B->revert restores the original byte-for-byte' (-not (Compare-Object $original $after))
check 'smartvac revert consumed the backup' (-not (Test-Path (Join-Path $svDirB '_SMART_VAC_CLEANER.py.bak')))

# ---- Test 10: a zero-anchor source must FAIL hard, write nothing, touch no backup ----
Clean-TestState
Reset-SmartVacDir
$svBroken = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
[System.IO.File]::WriteAllText($svBroken, "WIN95_BG = '#010203'`n", $utf8NoBom)
$brokenBefore = [System.IO.File]::ReadAllBytes($svBroken)
Write-PathsJson @{ smartvac = $svDirB }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
check 'zero-anchor smartvac apply exits NONZERO' ($LASTEXITCODE -ne 0)
check 'zero-anchor source file is left byte-unchanged' (-not (Compare-Object $brokenBefore ([System.IO.File]::ReadAllBytes($svBroken))))
check 'zero-anchor apply creates no backup' (-not (Test-Path ($svBroken + '.bak')))
check 'zero-anchor apply writes no manifest entry' (-not (Read-TestManifest).ContainsKey('smartvac'))
# Recovery remains possible: with a healthy source the same target applies fine.
[System.IO.File]::WriteAllText($svBroken, $svSource, $utf8NoBom)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
check 'recovery apply after the failed patch exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 11: full chain apply -> reapply(noop) -> repaint -> revert, byte-identical ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$chainOriginal = [System.IO.File]::ReadAllBytes((Join-Path $svDirB '_SMART_VAC_CLEANER.py'))
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'chain: apply A exits 0' ($LASTEXITCODE -eq 0)
$chainApplied = [System.IO.File]::ReadAllText((Join-Path $svDirB '_SMART_VAC_CLEANER.py'), $utf8NoBom)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1 | Out-Null
check 'chain: reapply (up to date) exits 0' ($LASTEXITCODE -eq 0)
check 'chain: reapply is a no-op on the file' ([System.IO.File]::ReadAllText((Join-Path $svDirB '_SMART_VAC_CLEANER.py'), $utf8NoBom) -eq $chainApplied)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette dracula 2>&1 | Out-Null
check 'chain: repaint exits 0' ($LASTEXITCODE -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Revert 2>&1 | Out-Null
check 'chain: revert exits 0' ($LASTEXITCODE -eq 0)
check 'chain: final file is byte-identical to the original' (-not (Compare-Object $chainOriginal ([System.IO.File]::ReadAllBytes((Join-Path $svDirB '_SMART_VAC_CLEANER.py')))))

# ---- Test 12: corrupt manifest is reported clearly by -Status, exit nonzero ----
Clean-TestState
[System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), '{ broken', $utf8NoBom)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
check 'corrupt manifest status exits nonzero' ($LASTEXITCODE -ne 0)
check 'corrupt manifest status reports CORRUPT' ($out -match 'CORRUPT')
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'corrupt manifest reapply exits nonzero' ($LASTEXITCODE -ne 0)
check 'corrupt manifest reapply reports CORRUPT' ($out -match 'CORRUPT')

# ---- Test 13: an Electron helper failure bubbles through the dispatch ----
Clean-TestState
# Point LOCALAPPDATA at a throwaway root so the antigravity-app resolver finds a
# FIXTURE resources dir (Programs\Antigravity\resources) whose app.asar is
# garbage: install-electron.js cannot read the package.json out of it, so the
# helper MUST die, the child MUST exit nonzero and the reapply MUST NOT refresh
# the target. Redirecting LOCALAPPDATA keeps a real local install out of reach.
$prevLocalAppData = $env:LOCALAPPDATA
try {
    $fakeLocal = Join-Path $testRoot 'localappdata'
    New-Item -ItemType Directory -Path (Join-Path $fakeLocal 'Programs\Antigravity\resources') -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $fakeLocal 'Programs\Antigravity\resources\app.asar'), [byte[]]@(0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01))
    $env:LOCALAPPDATA = $fakeLocal
    @{ 'antigravity-app' = @{ palette = 'goldendefault'; path = (Join-Path $fakeLocal 'Programs\Antigravity\resources'); appVersion = 'n/a'; payloadVersion = '1.9.0'; applied = '2020-01-01T00:00:00Z' } } |
        ConvertTo-Json -Depth 3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'electron helper failure makes reapply exit NONZERO' ($LASTEXITCODE -ne 0)
    check 'electron helper failure is named in the output' ($out -match 'antigravity-app' -and $out -match 'FAILED')
    $mElectron = Read-TestManifest
    check 'electron helper failure does NOT refresh the manifest entry' ($mElectron.'antigravity-app'.payloadVersion -eq '1.9.0')
    # Dry-run propagates the same helper failure (validation gate, not just
    # apply) -- at the DIRECT target level, where -WhatIf reaches the helper.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'antigravity-app' -WhatIf 2>&1
    $ErrorActionPreference = $prevEap
    check 'electron dry-run helper failure exits NONZERO' ($LASTEXITCODE -ne 0)
} finally {
    $env:LOCALAPPDATA = $prevLocalAppData
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail

} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
