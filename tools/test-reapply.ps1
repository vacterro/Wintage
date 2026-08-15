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
    Write-Host "test-reapply.ps1 (35 tests):"
    Write-Host "  1. semver-compare-is-semantic-not-string"
    Write-Host "  2. up-to-date-payload-is-skipped"
    Write-Host "  3. unhealthy-target-detected-under-whatif-child-preflight"
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
    Write-Host " 14. electron-same-payload-app-update-triggers-reapply"
    Write-Host " 15. recorded-vanished-target-fails-reapply-entry-kept"
    Write-Host " 16. strict-vs-bulk-absence-semantics"
    Write-Host " 17. upstream-v2-change-survives-repaint-revert"
    Write-Host " 18. concurrent-manifest-writers-keep-both-entries"
    Write-Host " 19. provenance-rebase-never-absorbs-themed-live-file"
    Write-Host " 20. native-target-applies-without-node"
    Write-Host " 21. present-generated-consumer-fails-without-node"
    Write-Host " 22. write-manifest-failure-cleans-tmp-keeps-old-manifest"
    Write-Host " 23. owned-token-tamper-repaired-by-reapply"
    Write-Host " 24. betterdiscord-css-tamper-repaired-by-reapply"
    Write-Host " 25. browser-stage-marker-tamper-repaired-by-reapply"
    Write-Host " 26. corrupt-manifest-aborts-before-target-mutation"
    Write-Host " 27. manifest-commit-failure-rolls-target-back"
    Write-Host " 28. concurrent-same-target-installs-serialize"
    Write-Host " 29. browser-stage-rollback-on-commit-failure"
    Write-Host " 30. vscode-extension-revert-restores-apply-time-recovery"
    Write-Host " 31. conhost-revert-keeps-backup-until-manifest-transition"
    Write-Host " 32. browser-stage-ownership-unowned-never-deleted"
    Write-Host " 33. saipenview-provenance-rebase"
    Write-Host " 34. manifest-schema-validation-rejects-syntax-valid-garbage"
    Write-Host " 35. conhost-scrollback-floor-zero-history-gets-usable-buffer"
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
WIN95_SURFACE_RAISED = '#010203'
WIN95_SURFACE_ALT  = '#010203'
WIN95_BEVEL_HI     = '#010203'
WIN95_BEVEL_SH     = '#010203'
WIN95_TEXT         = '#010203'
WIN95_TEXT_DIM     = '#010203'
WIN95_TEXT_MUTED   = '#010203'
WIN95_GOLD         = '#010203'
WIN95_GOLD_DIM     = '#010203'
WIN95_ACCENT       = '#010203'
WIN95_DANGER       = '#010203'
WIN95_SUCCESS      = '#010203'
WIN95_BUTTON       = '#010203'
WIN95_BUTTON_HOVER = '#010203'
WIN95_ENTRY        = '#010203'
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

# Minimal valid asar so install-electron can read a package.json version.
function Build-FakeAsar([string]$path, [string]$version) {
    $pkgJson = '{"name":"FakeApp","version":"' + $version + '","main":"' + ('x'.PadRight(40, 'x')) + '"}'
    $data = [System.Text.Encoding]::UTF8.GetBytes($pkgJson)
    $jsonStr = '{"files":{"package.json":{"size":' + $data.Length + ',"offset":"0"}}}'
    $json = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
    $jsonLen = $json.Length
    $pickleSize = 8 + $jsonLen + (4 - ((8 + $jsonLen) % 4))
    if ((8 + $jsonLen) % 4 -eq 0) { $pickleSize = 8 + $jsonLen }
    $base = 8 + $pickleSize
    $w = [System.IO.BinaryWriter]::new([System.IO.File]::Open($path, 'Create'))
    try {
        $w.Write([uint32]4); $w.Write([uint32]$pickleSize); $w.Write([uint32]$jsonLen); $w.Write([uint32]$jsonLen)
        $w.Write($json)
        $pad = New-Object byte[] ($base - 16 - $jsonLen)
        $w.Write($pad)
        $w.Write($data)
    } finally { $w.Dispose() }
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

# ---- Test 2: a HEALTHY target with an up-to-date payload is skipped ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
# REAL apply first so the file actually carries the palette tokens (the deeper
# T-190 health probe checks owned values, not just marker existence).
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'test2: real apply exits 0' ($LASTEXITCODE -eq 0)
$mHealthy = Read-TestManifest
$mHealthy.smartvac.payloadVersion = '99.99.99'   # force "payload current" so health alone decides
$mHealthy | ConvertTo-Json -Depth 3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'up-to-date healthy target is skipped' ($out -match 'up to date')
check 'reapply of an up-to-date healthy manifest exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 3: unhealthy target detected under -WhatIf, child preflight runs ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
@{smartvac=@{palette='goldendefault';path=(Join-Path $svDirB '_SMART_VAC_CLEANER.py');appVersion='n/a';payloadVersion='1.9.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
    ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
check 'unhealthy target detected via -WhatIf' ($out -match 'WOULD re-apply')
check 'reapply -WhatIf does not claim "all recorded targets are up to date"' ($out -notmatch 'all recorded targets are up to date')
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
# says A (with the CURRENT payload version - no fake bump). The user's remembered
# path (paths.json) is updated to B. The health probe must detect the path move
# and trigger -Reapply WITHOUT any Wintage payload version change (T-189).
Copy-Item $svDirA $svDirB -Recurse -Force
Remove-Item $svDirA -Recurse -Force
Write-PathsJson @{ smartvac = $svDirB }

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'reapply after move exits 0' ($LASTEXITCODE -eq 0)
$mAfterReapply = Read-TestManifest
check 'reapply records the NEW path B, not the stale manifest path A' ($mAfterReapply.smartvac.path -eq (Join-Path $svDirB '_SMART_VAC_CLEANER.py'))
check 'reapply kept the CURRENT payload version (no fake bump)' ($mAfterReapply.smartvac.payloadVersion -ne '1.9.0')
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
    # And at the REAPPLY level: a planned target whose dry-run fails makes the
    # whole -Reapply -WhatIf exit nonzero (P0#2).
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
    check 'Reapply -WhatIf child dry-run failure exits NONZERO' ($LASTEXITCODE -ne 0)
} finally {
    $env:LOCALAPPDATA = $prevLocalAppData
}

# ---- Test 14: an ELECTRON app update with the SAME payload triggers Reapply ----
Clean-TestState
$prevLocalAppData = $env:LOCALAPPDATA
try {
    $fakeLocal = Join-Path $testRoot 'localappdata2'
    $agRes = Join-Path $fakeLocal 'Programs\Antigravity\resources'
    New-Item -ItemType Directory -Path $agRes -Force | Out-Null
    Build-FakeAsar (Join-Path $agRes 'app.asar') '1.0.0'
    $env:LOCALAPPDATA = $fakeLocal
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'antigravity-app' -Palette goldendefault 2>&1
    check 'electron apply v1 exits 0' ($LASTEXITCODE -eq 0)
    $m1 = Read-TestManifest
    check 'manifest records app version 1.0.0' ($m1.'antigravity-app'.appVersion -eq '1.0.0')
    # Simulate the app updating: v2 stock asar lands at root, old relocation remains.
    Build-FakeAsar (Join-Path $agRes 'app.asar') '2.0.0'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'app update with SAME payload triggers reapply (exit 0)' ($LASTEXITCODE -eq 0)
    $m2 = Read-TestManifest
    check 'reapply refreshed the manifest to app v2' ($m2.'antigravity-app'.appVersion -eq '2.0.0')
    check 'manifest payload stayed current (no version fake)' ($m2.'antigravity-app'.payloadVersion -ne '1.9.0')
    # Revert must restore v2 stock, never v1.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'antigravity-app' -Revert 2>&1
    check 'electron revert after update exits 0' ($LASTEXITCODE -eq 0)
    $vAfter = (& node (Join-Path $root 'tools/install-electron.js') --resources $agRes --version 2>$null | Out-String).Trim()
    check 'revert restores v2, never v1' ($vAfter -eq '2.0.0')
} finally {
    $env:LOCALAPPDATA = $prevLocalAppData
}

# ---- Test 15: a manifest-recorded target that VANISHED fails Reapply, entry kept ----
Clean-TestState
# smartvac dir recorded in the manifest is deleted; paths.json says nothing.
$goneDir = Join-Path $testRoot 'smartvac-gone'
New-Item -ItemType Directory -Path $goneDir -Force | Out-Null
$gonePy = Join-Path $goneDir '_SMART_VAC_CLEANER.py'
[System.IO.File]::WriteAllText($gonePy, $svSource, $utf8NoBom)
@{smartvac=@{palette='goldendefault';path=$gonePy;appVersion='n/a';payloadVersion='99.99.99';applied='2026-01-01T00:00:00Z'}} | ConvertTo-Json |
    ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
Remove-Item $goneDir -Recurse -Force
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'recorded-but-vanished target makes reapply exit NONZERO' ($LASTEXITCODE -ne 0)
check 'recorded-but-vanished target named as FAILED' ($out -match 'smartvac' -and $out -match 'FAILED')
$mGone = Read-TestManifest
check 'recorded-but-vanished manifest entry is PRESERVED' ($mGone.smartvac.path -eq $gonePy)

# ---- Test 16: strict vs bulk absence semantics (P0#3) ----
# `-Target all` treats genuine absence as SKIP (nonfatal); an explicit/recorded
# target that cannot be fulfilled FAILS. Tested at the dispatch-contract helper
# level because a full `-Target all` run on a real host legitimately touches
# every installed target (e.g. windows may fail on a host with no active .theme).
. (Join-Path $root 'desktop\modules\targets.ps1')
$script:StrictTarget = $false
$skipThrew = $false
try { Assert-TargetResolvable 'FakeBulkTarget' $false } catch { $skipThrew = $true }
check 'bulk (non-strict) absent target SKIPs, does not throw' (-not $skipThrew)
$script:StrictTarget = $true
$strictThrew = $false
try { Assert-TargetResolvable 'FakeExplicitTarget' $false } catch { $strictThrew = $true }
check 'explicit (strict) absent target THROWS' $strictThrew

# ---- Test 17: upstream source v2 change survives repaint/revert (P1#16) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$svPristine = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
$v1Bytes = [System.IO.File]::ReadAllBytes($svPristine)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'provenance: apply v1 exits 0' ($LASTEXITCODE -eq 0)
# Upstream ships v2: SAME owned token values (app constants), an unrelated new
# function added. The provenance rebase keeps the tokens and takes the new code.
$v2 = $svSource + "`ndef helper_v2():`n    return 'unrelated v2 code'`n"
[System.IO.File]::WriteAllText($svPristine, $v2, $utf8NoBom)
$v2Bytes = [System.IO.File]::ReadAllBytes($svPristine)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette dracula 2>&1 | Out-Null
check 'provenance: repaint onto v2 exits 0' ($LASTEXITCODE -eq 0)
$afterRepaint = [System.IO.File]::ReadAllText($svPristine, $utf8NoBom)
check 'provenance: unrelated v2 code survives the repaint' ($afterRepaint -match 'helper_v2')
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Revert 2>&1 | Out-Null
check 'provenance: revert exits 0' ($LASTEXITCODE -eq 0)
$reverted = [System.IO.File]::ReadAllBytes($svPristine)
check 'provenance: revert restores pristine v2, NOT v1' ((Compare-Object $v2Bytes $reverted).Count -eq 0)
check 'provenance: revert does NOT restore the obsolete v1' ((Compare-Object $v1Bytes $reverted).Count -ne 0)

# ---- Test 18: concurrent manifest writers keep BOTH entries (P1#11) ----
# No sleep-based assertions: child processes are captured with -PassThru, run
# behind a ready/go barrier so they contend over the same read-modify-write
# interval, and completion is judged by bounded WaitForExit + exit codes.
Clean-TestState
$mPath = Join-Path $appData 'installed.json'
$commonPath = Join-Path $root 'desktop\modules\common.ps1'
function New-WriterScript([string]$target) {
    $childScript = Join-Path $appData ("writer-$target.ps1")
    $childContent = @"
. "$commonPath"
`$WintageAppData = "$appData"
`$ManifestPath = "$mPath"
`$script:Utf8NoBom = New-Object System.Text.UTF8Encoding(`$false)
[System.IO.File]::WriteAllText("$appData\ready-$target", 'ready')
while (-not (Test-Path "$appData\go")) { Start-Sleep -Milliseconds 20 }
Set-ManifestEntry "$target" 'golden' 'C:\x' '1' '2'
"@
    [System.IO.File]::WriteAllText($childScript, $childContent, $utf8NoBom)
    return $childScript
}
function Start-Writer([string]$target) {
    Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (New-WriterScript $target)) -WindowStyle Hidden -PassThru
}
$p1 = Start-Writer 'alpha'
$p2 = Start-Writer 'beta'
$readyDeadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $readyDeadline -and -not ((Test-Path (Join-Path $appData 'ready-alpha')) -and (Test-Path (Join-Path $appData 'ready-beta')))) { Start-Sleep -Milliseconds 20 }
[System.IO.File]::WriteAllText((Join-Path $appData 'go'), 'go')
$bothDone = $p1.WaitForExit(15000) -and $p2.WaitForExit(15000)
check 'concurrent writers BOTH finish within the bounded wait' $bothDone
check 'concurrent writer 1 exits 0' ($p1.ExitCode -eq 0)
check 'concurrent writer 2 exits 0' ($p2.ExitCode -eq 0)
$mConc = Read-TestManifest
check 'concurrent writers preserve BOTH entries' ($mConc.ContainsKey('alpha') -and $mConc.ContainsKey('beta'))
check 'concurrent writers leave no tmp garbage' (-not (Get-ChildItem $appData -Filter 'installed.json.tmp-*' -ErrorAction SilentlyContinue))

# ---- Test 18b: abandoned-mutex recovery (P1#10) ----
# A writer dies while holding the manifest mutex; the NEXT writer must receive
# the AbandonedMutexException as ACQUISITION (not a timeout) and proceed.
Clean-TestState
$abandonScript = Join-Path $appData 'abandon.ps1'
$abandonContent = @"
. "$commonPath"
`$WintageAppData = "$appData"
`$ManifestPath = "$mPath"
`$script:Utf8NoBom = New-Object System.Text.UTF8Encoding(`$false)
`$lock = Enter-ManifestLock
[System.IO.File]::WriteAllText("$appData\abandon-locked", 'locked')
Start-Sleep -Seconds 10
exit 1
"@
[System.IO.File]::WriteAllText($abandonScript, $abandonContent, $utf8NoBom)
$pa = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $abandonScript) -WindowStyle Hidden -PassThru
$lockDeadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $lockDeadline -and -not (Test-Path (Join-Path $appData 'abandon-locked'))) { Start-Sleep -Milliseconds 20 }
$pa.Kill()
$pa.WaitForExit(5000)
# The abandoned mutex must be recovered by a normal writer.
[System.IO.File]::WriteAllText((Join-Path $appData 'go'), 'go')
$p3 = Start-Writer 'gamma'
$p3done = $p3.WaitForExit(15000)
check 'abandoned-mutex writer finishes' $p3done
check 'abandoned-mutex writer exits 0' ($p3.ExitCode -eq 0)
$mAb = Read-TestManifest
check 'abandoned-mutex writer wrote its entry' ($mAb.ContainsKey('gamma'))
check 'abandoned-mutex recovery leaves no tmp garbage' (-not (Get-ChildItem $appData -Filter 'installed.json.tmp-*' -ErrorAction SilentlyContinue))

# ---- Test 19: provenance rebase never absorbs a THEMED live file (P1#15) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$svLive = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'themed-edit: Apply exits 0' ($LASTEXITCODE -eq 0)
# User edits an unrelated function while Wintage is STILL applied (themed file).
$themed = [System.IO.File]::ReadAllText($svLive, $utf8NoBom)
$themed = $themed + "`ndef user_helper():`n    return 'user edit while themed'`n"
[System.IO.File]::WriteAllText($svLive, $themed, $utf8NoBom)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette dracula 2>&1 | Out-Null
check 'themed-edit: repaint exits 0' ($LASTEXITCODE -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Revert 2>&1 | Out-Null
check 'themed-edit: revert exits 0' ($LASTEXITCODE -eq 0)
$reverted19 = [System.IO.File]::ReadAllText($svLive, $utf8NoBom)
check 'themed-edit: unrelated edit survives the revert' ($reverted19 -match 'user_helper')
check 'themed-edit: original stock owned tokens return (#010203)' ($reverted19 -match "(?m)^WIN95_BG\s*=\s*'#010203'$")
check 'themed-edit: NO Wintage palette token remains' ($reverted19 -notmatch '(?i)#1A1810|#3D372A|#D4C89A')

# ---- Test 20: native source-tree target applies WITHOUT Node (P1#19) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$env:WINTAGE_TEST_NO_NODE = '1'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
$env:WINTAGE_TEST_NO_NODE = ''
check 'native target applies WITHOUT node' ($LASTEXITCODE -eq 0)
$sv20 = [System.IO.File]::ReadAllText((Join-Path $svDirB '_SMART_VAC_CLEANER.py'), $utf8NoBom)
$pack20 = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
check 'native target without node is actually themed' ($sv20 -match [regex]::Escape($pack20.tokens.background))

# ---- Test 21: a PRESENT generated-build consumer FAILS without Node (P1#19) ----
Clean-TestState
$prevLocal21 = $env:LOCALAPPDATA
try {
    $fakeLocal21 = Join-Path $testRoot 'localappdata-nn'
    $agRes21 = Join-Path $fakeLocal21 'Programs\Antigravity\resources'
    New-Item -ItemType Directory -Path $agRes21 -Force | Out-Null
    Build-FakeAsar (Join-Path $agRes21 'app.asar') '1.0.0'
    $env:LOCALAPPDATA = $fakeLocal21
    $env:WINTAGE_TEST_NO_NODE = '1'
    $prevEap21 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'antigravity-app' -Palette goldendefault 2>&1
    $code21 = $LASTEXITCODE
    $ErrorActionPreference = $prevEap21
    $env:WINTAGE_TEST_NO_NODE = ''
    check 'present generated-consumer target FAILS without node' ($code21 -ne 0)
} finally { $env:LOCALAPPDATA = $prevLocal21 }

# ---- Test 22: Write-Manifest failure cleans its tmp and keeps the old manifest (P1#20) ----
Clean-TestState
$mPath22 = Join-Path $appData 'installed.json'
. $common
$script:WintageAppData = $appData
$script:ManifestPath = $mPath22
$script:Utf8NoBom = $utf8NoBom
$prevFail = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$threw22 = $false
try { Set-ManifestEntry 'probe' 'golden' 'C:\p' '1' '2' } catch { $threw22 = $true }
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail
check 'Write-Manifest replace failure throws' $threw22
check 'Write-Manifest failure leaves the OLD manifest intact' (-not (Test-Path $mPath22))
check 'Write-Manifest failure leaves NO tmp garbage' (-not (Get-ChildItem $appData -Filter 'installed.json.tmp-*' -ErrorAction SilentlyContinue))

# ---- Test 23: owned-token tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1 | Out-Null
check 'token-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
$py23 = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
$t23 = [System.IO.File]::ReadAllText($py23, $utf8NoBom) -replace "(?m)^WIN95_BG\s*=\s*'[^']*'", "WIN95_BG = '#BADBAD'"
[System.IO.File]::WriteAllText($py23, $t23, $utf8NoBom)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'token-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
$after23 = [System.IO.File]::ReadAllText($py23, $utf8NoBom)
$pack23 = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
check 'token-tamper: Reapply repaired the owned token' ($after23 -match [regex]::Escape($pack23.tokens.background))

# ---- Test 24: BetterDiscord css tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
$prevApp24 = $env:APPDATA
$prevWintageApp24 = $env:WINTAGE_APPDATA
try {
    $fakeApp24 = Join-Path $testRoot 'bdappdata'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp24 'BetterDiscord\themes'), (Join-Path $fakeApp24 'Wintage') -Force | Out-Null
    $env:APPDATA = $fakeApp24
    $env:WINTAGE_APPDATA = Join-Path $fakeApp24 'Wintage'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target discord -Palette goldendefault 2>&1
    check 'discord-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
    $bdCss24 = Join-Path $fakeApp24 'BetterDiscord\themes\wintage.theme.css'
    $t24 = [System.IO.File]::ReadAllText($bdCss24, $utf8NoBom) -replace [regex]::Escape($pack23.tokens.background), '#000000'
    [System.IO.File]::WriteAllText($bdCss24, $t24, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'discord-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
    $after24 = [System.IO.File]::ReadAllText($bdCss24, $utf8NoBom)
    check 'discord-tamper: Reapply repaired the css' ($after24 -match [regex]::Escape($pack23.tokens.background))
} finally { $env:APPDATA = $prevApp24; $env:WINTAGE_APPDATA = $prevWintageApp24 }

# ---- Test 25: browser stage marker tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
$prevLocal25 = $env:LOCALAPPDATA
$prevApp25 = $env:APPDATA
$prevWintageApp25 = $env:WINTAGE_APPDATA
try {
    $browserRoot25 = Join-Path $testRoot 'browsers'
    $fakeBrowser25 = Join-Path $browserRoot25 'Portable Browser'
    $fakeExe25 = Join-Path $fakeBrowser25 'chrome.exe'
    $fakeData25 = Join-Path $fakeBrowser25 'User Data'
    $fakeProfile25 = Join-Path $fakeData25 'Default'
    $tmDir25 = Join-Path $fakeProfile25 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage25 = Join-Path $browserRoot25 'stage'
    New-Item -ItemType Directory -Path $tmDir25 -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe25, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile25 'Preferences'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $fakeData25 'Local State'), '{}', $utf8NoBom)
    $catalog25 = Join-Path $browserRoot25 'catalog.json'
    @([ordered]@{ Name = 'Fixture'; Exe = $fakeExe25; UserData = $fakeData25 }) | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog25, $_, $utf8NoBom) }
    $fakeApp25 = Join-Path $testRoot 'winappdata25'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp25 'Wintage') -Force | Out-Null
    $fakeLocal25 = Join-Path $testRoot 'localappdata25'
    New-Item -ItemType Directory -Path $fakeLocal25 -Force | Out-Null
    $env:LOCALAPPDATA = $fakeLocal25
    $env:APPDATA = $fakeApp25
    $env:WINTAGE_APPDATA = Join-Path $fakeApp25 'Wintage'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette goldendefault -BrowserCatalog $catalog25 -BrowserStageRoot $stage25 -NoBrowserLaunch 2>&1
    check 'browser-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
    [System.IO.File]::WriteAllText((Join-Path $stage25 '.wintage-palette'), 'dracula', $utf8NoBom)
    # T-191: the Reapply child must inherit the catalog (never discover real
    # Edge/Chrome) and must NEVER reopen a browser over a repaint.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -BrowserCatalog $catalog25 -BrowserStageRoot $stage25 2>&1
    check 'browser-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
    $after25 = ([System.IO.File]::ReadAllText((Join-Path $stage25 '.wintage-palette'), $utf8NoBom)).Trim()
    check 'browser-tamper: Reapply repaired the marker' ($after25 -eq 'goldendefault')
} finally { $env:LOCALAPPDATA = $prevLocal25; $env:APPDATA = $prevApp25; $env:WINTAGE_APPDATA = $prevWintageApp25 }

# ---- Test 26: corrupt manifest aborts BEFORE any target mutation (T-191 P0#1) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$py26 = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
$pre26 = [System.IO.File]::ReadAllBytes($py26)
$garbage26 = '{"this is ::: not valid json'
[System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $garbage26, $utf8NoBom)
$out26 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
check 'corrupt-precheck: install exits nonzero' ($LASTEXITCODE -ne 0)
$post26 = [System.IO.File]::ReadAllBytes($py26)
$bytesSame26 = $true
if ($post26.Length -ne $pre26.Length) { $bytesSame26 = $false }
else { for ($i = 0; $i -lt $post26.Length; $i++) { if ($post26[$i] -ne $pre26[$i]) { $bytesSame26 = $false; break } } }
check 'corrupt-precheck: target file byte-identical (no mutation)' $bytesSame26
check 'corrupt-precheck: no backup created' (-not (Test-Path (Join-Path $svDirB '_SMART_VAC_CLEANER.py.bak')))
check 'corrupt-precheck: corrupt manifest still present (not overwritten)' ((Test-Path (Join-Path $appData 'installed.json')) -and ([System.IO.File]::ReadAllText((Join-Path $appData 'installed.json'), $utf8NoBom) -eq $garbage26))

# ---- Test 27: manifest-commit failure rolls the target back (T-191 P0#1) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$py27 = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
$pre27 = [System.IO.File]::ReadAllBytes($py27)
$prevFail27 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$out27 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail27
check 'commit-rollback: install exits nonzero' ($LASTEXITCODE -ne 0)
$post27 = [System.IO.File]::ReadAllBytes($py27)
$bytesSame27 = $true
if ($post27.Length -ne $pre27.Length) { $bytesSame27 = $false }
else { for ($i = 0; $i -lt $post27.Length; $i++) { if ($post27[$i] -ne $pre27[$i]) { $bytesSame27 = $false; break } } }
check 'commit-rollback: target restored to exact pre-operation state' $bytesSame27
check 'commit-rollback: no backup left behind' (-not (Test-Path (Join-Path $svDirB '_SMART_VAC_CLEANER.py.bak')))
check 'commit-rollback: old manifest unchanged (still absent)' (-not (Test-Path (Join-Path $appData 'installed.json')))
check 'commit-rollback: rollback message surfaced' ($out27 -match 'restored to its exact pre-operation state')

# ---- Test 28: concurrent same-target installs serialize (T-191 P0#2) ----
Clean-TestState
Reset-SmartVacDir
Write-PathsJson @{ smartvac = $svDirB }
$p1 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Target','smartvac','-Palette','goldendefault') -PassThru -WindowStyle Hidden
$p2 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Target','smartvac','-Palette','goldendefault') -PassThru -WindowStyle Hidden
$null = $p1.WaitForExit(60000)
$null = $p2.WaitForExit(60000)
check 'lock-serialize: both concurrent installs exited' ($p1.HasExited -and $p2.HasExited)
$exitSum = ($p1.ExitCode + $p2.ExitCode)
check 'lock-serialize: both installs succeeded (serialized, not corrupted)' ($p1.HasExited -and $p2.HasExited -and $exitSum -eq 0)
$py28 = Join-Path $svDirB '_SMART_VAC_CLEANER.py'
$after28 = [System.IO.File]::ReadAllText($py28, $utf8NoBom)
$pack28 = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
check 'lock-serialize: final file is a valid palette' ($after28 -match [regex]::Escape($pack28.tokens.background))
check 'lock-serialize: manifest recorded once, sane' ((Read-TestManifest).smartvac.path -eq $py28)

# ---- Test 29: browser stage rollback on manifest-commit failure (T-191 P0#10) ----
Clean-TestState
$prevLocal29 = $env:LOCALAPPDATA
$prevApp29 = $env:APPDATA
$prevWintage29 = $env:WINTAGE_APPDATA
try {
    $browserRoot29 = Join-Path $testRoot 'browsers29'
    $fakeBrowser29 = Join-Path $browserRoot29 'Portable Browser'
    $fakeExe29 = Join-Path $fakeBrowser29 'chrome.exe'
    $fakeData29 = Join-Path $fakeBrowser29 'User Data'
    $fakeProfile29 = Join-Path $fakeData29 'Default'
    $tmDir29 = Join-Path $fakeProfile29 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage29 = Join-Path $browserRoot29 'stage'
    New-Item -ItemType Directory -Path $tmDir29 -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe29, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile29 'Preferences'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $fakeData29 'Local State'), '{}', $utf8NoBom)
    $catalog29 = Join-Path $browserRoot29 'catalog.json'
    @([ordered]@{ Name = 'Fixture'; Exe = $fakeExe29; UserData = $fakeData29 }) | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog29, $_, $utf8NoBom) }
    $fakeApp29 = Join-Path $testRoot 'winappdata29'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp29 'Wintage') -Force | Out-Null
    $fakeLocal29 = Join-Path $testRoot 'localappdata29'
    New-Item -ItemType Directory -Path $fakeLocal29 -Force | Out-Null
    $env:LOCALAPPDATA = $fakeLocal29
    $env:APPDATA = $fakeApp29
    $env:WINTAGE_APPDATA = Join-Path $fakeApp29 'Wintage'
    New-Item -ItemType Directory -Path $stage29 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $stage29 '.wintage-palette'), 'goldendefault', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $stage29 'manifest.json'), '{"name":"old"}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $stage29 '.wintage-owner.json'), '{"owner":"Wintage","schema":1,"palette":"goldendefault"}', $utf8NoBom)
    $prevFail29 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
    $out29 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette dracula -BrowserCatalog $catalog29 -BrowserStageRoot $stage29 -NoBrowserLaunch 2>&1
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail29
    check 'browser-stage-rollback: install exits nonzero' ($LASTEXITCODE -ne 0)
    check 'browser-stage-rollback: stage marker restored to the pre-state palette' ([System.IO.File]::ReadAllText((Join-Path $stage29 '.wintage-palette'), $utf8NoBom) -eq 'goldendefault')
    check 'browser-stage-rollback: stage manifest restored' ([System.IO.File]::ReadAllText((Join-Path $stage29 'manifest.json'), $utf8NoBom) -match 'old')
} finally { $env:LOCALAPPDATA = $prevLocal29; $env:APPDATA = $prevApp29; $env:WINTAGE_APPDATA = $prevWintage29 }

# ---- Test 30: VS Code extension revert restores the apply-time backup (T-191 P0#11) ----
Clean-TestState
$prevHome30 = $env:HOME
$prevBakRoot30 = $env:WINTAGE_BACKUP_ROOT
$prevWintage30 = $env:WINTAGE_APPDATA
try {
    $fakeHome30 = Join-Path $testRoot 'fakehome30'
    $extDir30 = Join-Path $fakeHome30 '.vscode\extensions'
    $dest30 = Join-Path $extDir30 'wintage-themes'
    New-Item -ItemType Directory -Path (Join-Path $dest30 'themes') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest30 'themes\stock.json'), '{"name":"stock"}', $utf8NoBom)
    $fakeApp30 = Join-Path $testRoot 'winappdata30'
    New-Item -ItemType Directory -Path $fakeApp30 -Force | Out-Null
    $env:HOME = $fakeHome30
    $env:WINTAGE_BACKUP_ROOT = Join-Path $testRoot 'backup30'
    $env:WINTAGE_APPDATA = $fakeApp30
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Palette goldendefault 2>&1
    check 'vscode-backup: apply exits 0' ($LASTEXITCODE -eq 0)
    check 'vscode-backup: Wintage themes installed' (Test-Path (Join-Path $dest30 'themes'))
    $m30 = Join-Path $fakeApp30 'installed.json'
    check 'vscode-backup: manifest recorded' ((Test-Path $m30) -and ((Get-Content $m30 -Raw | ConvertFrom-Json).vscode.palette -eq 'goldendefault'))
    # T-192 P1#15: recovery lives under WINTAGE_APPDATA/recovery (non-pruned authority).
    $rec30 = Join-Path $fakeApp30 'recovery\vscode'
    $pristine30 = Join-Path $rec30 'pristine'
    check 'vscode-backup: recovery mode recorded as replaced' (((Get-Content (Join-Path $rec30 'recovery.json') -Raw | ConvertFrom-Json).mode -eq 'replaced'))
    check 'vscode-backup: pristine snapshot captured under recovery/' (Test-Path (Join-Path $pristine30 'themes\stock.json'))
    $pristineBytes30 = [System.IO.File]::ReadAllBytes((Join-Path $pristine30 'themes\stock.json'))
    # Repaint to another palette must NOT overwrite the pristine snapshot.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Palette dracula 2>&1
    check 'vscode-backup: repaint exits 0' ($LASTEXITCODE -eq 0)
    $pristineAfter30 = [System.IO.File]::ReadAllBytes((Join-Path $pristine30 'themes\stock.json'))
    $same30 = $pristineAfter30.Length -eq $pristineBytes30.Length
    if ($same30) { for ($i = 0; $i -lt $pristineAfter30.Length; $i++) { if ($pristineAfter30[$i] -ne $pristineBytes30[$i]) { $same30 = $false; break } } }
    check 'vscode-backup: repaint never overwrites the pristine snapshot' $same30
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Revert 2>&1
    check 'vscode-backup: revert exits 0' ($LASTEXITCODE -eq 0)
    check 'vscode-backup: revert restores the ORIGINAL pre-Wintage tree' (Test-Path (Join-Path $dest30 'themes\stock.json'))
    check 'vscode-backup: repainted artifact gone after revert' (-not (Test-Path (Join-Path $dest30 'themes\dracula.json')))
    $m30After = if (Test-Path $m30) { Get-Content $m30 -Raw | ConvertFrom-Json } else { $null }
    check 'vscode-backup: manifest entry removed' ((-not $m30After) -or -not $m30After.vscode)
} finally { $env:HOME = $prevHome30; $env:WINTAGE_BACKUP_ROOT = $prevBakRoot30; $env:WINTAGE_APPDATA = $prevWintage30 }

# ---- Test 31: conhost revert keeps its backup until the manifest transition succeeds (T-192 P0#4) ----
Clean-TestState
$prevKey31 = $env:WINTAGE_TEST_CONHOST_KEY
$prevBakBase31 = $env:WINTAGE_BACKUP_ROOT
$prevWintage31 = $env:WINTAGE_APPDATA
try {
    $conRoot31 = 'HKCU:\Software\Wintage-Test-Conhost-' + [guid]::NewGuid().ToString('N')
    $env:WINTAGE_TEST_CONHOST_KEY = $conRoot31
    $fakeBak31 = Join-Path $testRoot 'backup31'
    $env:WINTAGE_BACKUP_ROOT = $fakeBak31
    $fakeApp31 = Join-Path $testRoot 'winappdata31'
    $env:WINTAGE_APPDATA = $fakeApp31
    New-Item -Path $conRoot31 -Force | Out-Null
    New-Item -Path (Join-Path $conRoot31 'Console') -Force | Out-Null
    New-ItemProperty -Path $conRoot31 -Name ColorTable00 -Value 0x00999999 -PropertyType DWord -Force | Out-Null
    $mPath31 = Join-Path $fakeApp31 'installed.json'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'conhost-recovery: apply exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-recovery: WintagePalette recorded' ((Get-ItemProperty $conRoot31 -Name WintagePalette).WintagePalette -eq 'goldendefault')
    $bak31 = Join-Path $fakeBak31 'conhost-settings.json'
    check 'conhost-recovery: apply-time backup exists' (Test-Path $bak31)
    # Inject a manifest-remove failure during Revert.
    $prevFail31 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail31
    check 'conhost-recovery: failing revert exits NONZERO' ($LASTEXITCODE -ne 0)
    check 'conhost-recovery: recovery backup still valid after failure' (Test-Path $bak31)
    check 'conhost-recovery: manifest still recorded after failure' ((Test-Path $mPath31) -and (Get-Content $mPath31 -Raw | ConvertFrom-Json).conhost)
    check 'conhost-recovery: themed state restored after failure (matches manifest)' ((Get-ItemProperty $conRoot31 -Name WintagePalette).WintagePalette -eq 'goldendefault')
    # Clean retry Revert must succeed and consume the backup.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    check 'conhost-recovery: retry revert exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-recovery: retry consumes the backup' (-not (Test-Path $bak31))
    check 'conhost-recovery: manifest removed on retry' (-not ((Test-Path $mPath31) -and (Get-Content $mPath31 -Raw | ConvertFrom-Json).conhost))
    check 'conhost-recovery: pre-Wintage value restored' ((Get-ItemProperty $conRoot31 -Name ColorTable00).ColorTable00 -eq 0x00999999)
    check 'conhost-recovery: no mixed state (marker gone)' (-not ((Get-ItemProperty $conRoot31 -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'WintagePalette'))
} finally {
    Remove-Item $conRoot31 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey31
    $env:WINTAGE_BACKUP_ROOT = $prevBakBase31
    $env:WINTAGE_APPDATA = $prevWintage31
}

# ---- Test 32: browser stage ownership - unowned dir is NEVER deleted (T-192 P0#14) ----
Clean-TestState
$prevLocal32 = $env:LOCALAPPDATA
$prevApp32 = $env:APPDATA
$prevWintage32 = $env:WINTAGE_APPDATA
try {
    $browserRoot32 = Join-Path $testRoot 'browsers32'
    $fakeBrowser32 = Join-Path $browserRoot32 'Portable Browser'
    $fakeExe32 = Join-Path $fakeBrowser32 'chrome.exe'
    $fakeData32 = Join-Path $fakeBrowser32 'User Data'
    $fakeProfile32 = Join-Path $fakeData32 'Default'
    $tmDir32 = Join-Path $fakeProfile32 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage32 = Join-Path $browserRoot32 'stage'
    New-Item -ItemType Directory -Path $tmDir32 -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe32, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile32 'Preferences'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $fakeData32 'Local State'), '{}', $utf8NoBom)
    $catalog32 = Join-Path $browserRoot32 'catalog.json'
    @([ordered]@{ Name = 'Fixture'; Exe = $fakeExe32; UserData = $fakeData32 }) | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog32, $_, $utf8NoBom) }
    $fakeApp32 = Join-Path $testRoot 'winappdata32'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp32 'Wintage') -Force | Out-Null
    $fakeLocal32 = Join-Path $testRoot 'localappdata32'
    New-Item -ItemType Directory -Path $fakeLocal32 -Force | Out-Null
    $env:LOCALAPPDATA = $fakeLocal32
    $env:APPDATA = $fakeApp32
    $env:WINTAGE_APPDATA = Join-Path $fakeApp32 'Wintage'
    # Unowned stage with real user data - no owner marker.
    New-Item -ItemType Directory -Path $stage32 -Force | Out-Null
    $important32 = 'user data that must survive'
    [System.IO.File]::WriteAllText((Join-Path $stage32 'important.txt'), $important32, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette goldendefault -BrowserCatalog $catalog32 -BrowserStageRoot $stage32 -NoBrowserLaunch 2>&1
    check 'browser-ownership: unowned Apply REFUSED (nonzero)' ($LASTEXITCODE -ne 0)
    check 'browser-ownership: important.txt preserved byte-identical' ([System.IO.File]::ReadAllText((Join-Path $stage32 'important.txt'), $utf8NoBom) -eq $important32)
    check 'browser-ownership: no owner marker written over user data' (-not (Test-Path (Join-Path $stage32 '.wintage-owner.json')))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Revert -BrowserCatalog $catalog32 -BrowserStageRoot $stage32 -NoBrowserLaunch 2>&1
    check 'browser-ownership: unowned Revert REFUSED (nonzero)' ($LASTEXITCODE -ne 0)
    check 'browser-ownership: important.txt still intact after refused Revert' ([System.IO.File]::ReadAllText((Join-Path $stage32 'important.txt'), $utf8NoBom) -eq $important32)
    check 'browser-ownership: no manifest entry recorded' (-not ((Test-Path (Join-Path $fakeApp32 'Wintage\installed.json')) -and (Get-Content (Join-Path $fakeApp32 'Wintage\installed.json') -Raw | ConvertFrom-Json).browsers))
} finally { $env:LOCALAPPDATA = $prevLocal32; $env:APPDATA = $prevApp32; $env:WINTAGE_APPDATA = $prevWintage32 }

# ---- Test 33: SAIPENVIEW provenance rebase - themed live CSS never becomes pristine (T-192 P1#18) ----
Clean-TestState
$prevSv33 = $env:WINTAGE_APPDATA
try {
    $svPath33 = Join-Path $testRoot 'saipenview33'
    $cssDir33 = Join-Path $svPath33 'saipenview\ui\static'
    $cssFile33 = Join-Path $cssDir33 'style.css'
    New-Item -ItemType Directory -Path $cssDir33 -Force | Out-Null
    $stockCss33 = ":root { --background: #010203; --textPrimary: #040506; --surface: #0a0b0c; --danger: #070809; }`n.banner { width: 100%; }`n"
    [System.IO.File]::WriteAllText($cssFile33, $stockCss33, $utf8NoBom)
    $fakeApp33 = Join-Path $testRoot 'winappdata33'
    New-Item -ItemType Directory -Path $fakeApp33 -Force | Out-Null
    $env:WINTAGE_APPDATA = $fakeApp33
    [System.IO.File]::WriteAllText((Join-Path $fakeApp33 'paths.json'), (@{ saipenview = $svPath33 } | ConvertTo-Json), $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target saipenview -Palette goldendefault 2>&1
    check 'saipen-provenance: Apply A exits 0' ($LASTEXITCODE -eq 0)
    $bak33 = Join-Path $cssDir33 'style.css.bak'
    check 'saipen-provenance: backup created' (Test-Path $bak33)
    # Unrelated selector added WHILE the theme is applied.
    $themed33 = [System.IO.File]::ReadAllText($cssFile33, $utf8NoBom) + "`n.new-selector { margin: 3px; }`n"
    [System.IO.File]::WriteAllText($cssFile33, $themed33, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target saipenview -Palette goldendefault 2>&1
    check 'saipen-provenance: Apply B (repaint) exits 0' ($LASTEXITCODE -eq 0)
    # The backup must have been REBASED: stock token values, not the themed ones.
    $rebaseBak33 = [System.IO.File]::ReadAllText($bak33, $utf8NoBom)
    check 'saipen-provenance: rebased backup keeps stock token values' ($rebaseBak33 -match '--background: #010203')
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target saipenview -Revert 2>&1
    check 'saipen-provenance: Revert exits 0' ($LASTEXITCODE -eq 0)
    $after33 = [System.IO.File]::ReadAllText($cssFile33, $utf8NoBom)
    check 'saipen-provenance: unrelated selector survives the Revert' ($after33 -match '\.new-selector')
    check 'saipen-provenance: stock token values return' ($after33 -match '--background: #010203' -and $after33 -match '--textPrimary: #040506')
    $pack33 = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
    check 'saipen-provenance: no Wintage palette value remains' ($after33 -notmatch [regex]::Escape($pack33.tokens.background))
} finally { $env:WINTAGE_APPDATA = $prevSv33 }

# ---- Test 34: manifest schema validation rejects syntax-valid garbage (T-192 P1#20) ----
Clean-TestState
$prevW34 = $env:WINTAGE_APPDATA
try {
    $fakeApp34 = Join-Path $testRoot 'winappdata34'
    New-Item -ItemType Directory -Path $fakeApp34 -Force | Out-Null
    $env:WINTAGE_APPDATA = $fakeApp34
    $m34 = Join-Path $fakeApp34 'installed.json'
    $cases34 = @(
        @{ Name = 'non-array items'; Body = '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}' },
        @{ Name = 'top-level array'; Body = '[]' },
        @{ Name = 'scalar manifest'; Body = '"hello"' },
        @{ Name = 'non-object entry'; Body = '{"smartvac":42}' },
        @{ Name = 'wrong-typed field'; Body = '{"conhost":{"palette":5,"path":"x","appVersion":"1","payloadVersion":"1","applied":"z"}}' }
    )
    foreach ($c in $cases34) {
        [System.IO.File]::WriteAllText($m34, $c.Body, $utf8NoBom)
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
        check "manifest-schema: $($c.Name) reported by -Status (nonzero)" ($LASTEXITCODE -ne 0)
        check "manifest-schema: $($c.Name) message says schema" ($out -match 'schema')
        check "manifest-schema: $($c.Name) file NOT overwritten by the read" ([System.IO.File]::ReadAllText($m34, $utf8NoBom) -eq $c.Body)
    }
    # Set-ManifestEntry must refuse to overwrite schema-invalid content.
    [System.IO.File]::WriteAllText($m34, '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}', $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target smartvac -Palette goldendefault 2>&1
    check 'manifest-schema: Apply over schema-invalid manifest exits NONZERO' ($LASTEXITCODE -ne 0)
    check 'manifest-schema: schema-invalid manifest preserved byte-exact' ([System.IO.File]::ReadAllText($m34, $utf8NoBom) -eq '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}')
    # Unknown target keys are preserved + readable (never destroyed).
    $future34 = '{"futuretarget":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z"}}'
    [System.IO.File]::WriteAllText($m34, $future34, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
    check 'manifest-schema: unknown future target key is readable (Status exits 0)' ($LASTEXITCODE -eq 0)
} finally { $env:WINTAGE_APPDATA = $prevW34 }

# ---- Test 35: conhost scrollback floor - zero-history console profiles get a usable buffer (T-193) ----
Clean-TestState
$prevKey35 = $env:WINTAGE_TEST_CONHOST_KEY
$prevBakBase35 = $env:WINTAGE_BACKUP_ROOT
$prevWintage35 = $env:WINTAGE_APPDATA
try {
    $conRoot35 = 'HKCU:\Software\Wintage-Test-Conhost-' + [guid]::NewGuid().ToString('N')
    $env:WINTAGE_TEST_CONHOST_KEY = $conRoot35
    $fakeBak35 = Join-Path $testRoot 'backup35'
    $env:WINTAGE_BACKUP_ROOT = $fakeBak35
    $fakeApp35 = Join-Path $testRoot 'winappdata35'
    $env:WINTAGE_APPDATA = $fakeApp35
    New-Item -Path $conRoot35 -Force | Out-Null
    # The broken shape this reproduces: buffer height == window height (25 rows,
    # 106 cols) - i.e. ZERO scrollback, the "terminal cuts my history" bug.
    New-ItemProperty -Path $conRoot35 -Name ScreenBufferSize -Value ((25 -shl 16) -bor 106) -PropertyType DWord -Force | Out-Null
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'conhost-scrollback: apply exits 0' ($LASTEXITCODE -eq 0)
    $buf35 = (Get-ItemProperty $conRoot35 -Name ScreenBufferSize).ScreenBufferSize
    check 'conhost-scrollback: buffer height raised to the 9001 floor' (((($buf35 -shr 16) -band 0xFFFF) -ge 9001))
    check 'conhost-scrollback: buffer width preserved' ((($buf35 -band 0xFFFF) -eq 106))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    check 'conhost-scrollback: revert exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-scrollback: original zero-history buffer restored byte-exact' ((Get-ItemProperty $conRoot35 -Name ScreenBufferSize).ScreenBufferSize -eq ((25 -shl 16) -bor 106))
} finally {
    Remove-Item $conRoot35 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey35
    $env:WINTAGE_BACKUP_ROOT = $prevBakBase35
    $env:WINTAGE_APPDATA = $prevWintage35
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail

} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
