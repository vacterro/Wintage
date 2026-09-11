# Reapply + manifest regression suite (T-187).
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
    Write-Host "test-reapply.ps1 (32 tests):"
    Write-Host "  1. semver-compare-is-semantic-not-string"
    Write-Host "  2. up-to-date-payload-is-skipped"
    Write-Host "  3. unhealthy-target-detected-under-whatif-child-preflight"
    Write-Host "  4. empty-manifest-reports-nothing-to-do"
    Write-Host "  5. corrupt-manifest-is-not-overwritten"
    Write-Host "  6. manifest-atomic-round-trip"
    Write-Host "  7. rediscovery-finds-moved-target"
    Write-Host "  8. child-failure-bubbles-to-exit-code"
    Write-Host "  9. notepadplusplus-apply-repaint-revert"
    Write-Host " 10. full-chain-apply-reapply-repaint-revert"
    Write-Host " 11. corrupt-manifest-status-reports-clearly"
    Write-Host " 12. electron-helper-failure-bubbles-and-dryrun"
    Write-Host " 13. electron-same-payload-app-update-triggers-reapply"
    Write-Host " 14. recorded-vanished-target-fails-reapply-entry-kept"
    Write-Host " 15. strict-vs-bulk-absence-semantics"
    Write-Host " 16. concurrent-manifest-writers-keep-both-entries"
    Write-Host " 17. native-target-applies-without-node"
    Write-Host " 18. present-generated-consumer-fails-without-node"
    Write-Host " 19. write-manifest-failure-cleans-tmp-keeps-old-manifest"
    Write-Host " 20. marker-tamper-repaired-by-reapply"
    Write-Host " 21. betterdiscord-css-tamper-repaired-by-reapply"
    Write-Host " 22. browser-stage-marker-tamper-repaired-by-reapply"
    Write-Host " 23. corrupt-manifest-aborts-before-target-mutation"
    Write-Host " 24. manifest-commit-failure-rolls-target-back"
    Write-Host " 25. concurrent-same-target-installs-serialize"
    Write-Host " 26. browser-stage-rollback-on-commit-failure"
    Write-Host " 27. vscode-extension-revert-restores-apply-time-recovery"
    Write-Host " 28. conhost-revert-keeps-backup-until-manifest-transition"
    Write-Host " 29. browser-stage-ownership-unowned-never-deleted"
    Write-Host " 30. manifest-schema-validation-rejects-syntax-valid-garbage"
    Write-Host " 31. conhost-scrollback-floor-zero-history-gets-usable-buffer"
    Write-Host " 32. conhost-reapply-health-reasserts-collapsed-scrollback"
    exit 0
}

# ------------------------------------------------------------------ fixture
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-reapply-test-" + [guid]::NewGuid().ToString('N'))
$appData = Join-Path $testRoot 'appdata'
$nppDirA = Join-Path $testRoot 'npp-a'
$nppDirB = Join-Path $testRoot 'npp-b'
$c4dDir = Join-Path $testRoot 'c4d'
New-Item -ItemType Directory -Path $appData, (Join-Path $nppDirA 'themes'), (Join-Path $nppDirB 'themes'), (Join-Path $c4dDir 'resource\modules\c4d_base\schemes') -Force | Out-Null

$prevAppData = $env:WINTAGE_APPDATA
$env:WINTAGE_APPDATA = $appData

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

function Reset-NppDir([string]$dir = $nppDirB) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $dir 'themes') -Force | Out-Null
}

function Reset-C4dDir([string]$dir = $c4dDir) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $dir 'resource\modules\c4d_base\schemes') -Force | Out-Null
}

# CORE-007: a mutating install-electron apply requires a RESOLVABLE executable
# whose fuse wire is readable and schema-valid (zero-EXE is UNVERIFIABLE and
# must fail closed), so every fixture that runs a real apply ships a stock
# fused exe with both blocking fuses enabled. Schema v1, count 8, sentinel as
# produced by the production reader.
function New-FusedExe {
    $sentinel = [System.Text.Encoding]::ASCII.GetBytes('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX')
    $fuses = New-Object byte[] 8
    for ($i = 0; $i -lt 8; $i++) { $fuses[$i] = 0x30 }
    $fuses[5] = 0x31   # OnlyLoadAppFromAsar
    $fuses[6] = 0x31   # LoadBrowserProcessSpecificV8Snapshot (non-blocking, exercises byte-level restore)
    $bytes = New-Object System.Collections.Generic.List[byte]
    $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes('MZ fake exe '))
    $bytes.AddRange($sentinel)
    $bytes.Add(1); $bytes.Add(8)
    $bytes.AddRange($fuses)
    $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes(' padding'))
    $bytes.ToArray()
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
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1 | Out-Null
check 'test2: real apply exits 0' ($LASTEXITCODE -eq 0)
$mHealthy = Read-TestManifest
$mHealthy.notepadplusplus.payloadVersion = '99.99.99'   # force "payload current" so health alone decides
$mHealthy | ConvertTo-Json -Depth 3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'up-to-date healthy target is skipped' ($out -match 'up to date')
check 'reapply of an up-to-date healthy manifest exits 0' ($LASTEXITCODE -eq 0)

# ---- Test 3: unhealthy target detected under -WhatIf, child preflight runs ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
@{notepadplusplus=@{palette='goldendefault';path=$nppDirB;appVersion='n/a';payloadVersion='1.9.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
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
Reset-NppDir $nppDirA
Write-PathsJson @{ notepadplusplus = $nppDirA }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus 2>&1 | Out-Null
check 'initial notepadplusplus apply exits 0' ($LASTEXITCODE -eq 0)
$mAfterApply = Read-TestManifest
check 'initial apply records path A in the manifest' ($mAfterApply.notepadplusplus.path -eq $nppDirA)

# Simulate the app moving: A is gone, B is where it lives now. The manifest still
# says A (with the CURRENT payload version - no fake bump). The user's remembered
# path (paths.json) is updated to B. The health probe must detect the path move
# and trigger -Reapply WITHOUT any Wintage payload version change (T-189).
Copy-Item $nppDirA $nppDirB -Recurse -Force
Remove-Item $nppDirA -Recurse -Force
Write-PathsJson @{ notepadplusplus = $nppDirB }

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'reapply after move exits 0' ($LASTEXITCODE -eq 0)
$mAfterReapply = Read-TestManifest
check 'reapply records the NEW path B, not the stale manifest path A' ($mAfterReapply.notepadplusplus.path -eq $nppDirB)
check 'reapply kept the CURRENT payload version (no fake bump)' ($mAfterReapply.notepadplusplus.payloadVersion -ne '1.9.0')
check 'the moved target file at B is actually themed' (Test-Path (Join-Path $nppDirB 'themes\Wintage.xml'))

# ---- Test 8: a failing child bubbles to a nonzero exit, a sibling still applies ----
Clean-TestState
Reset-NppDir
Reset-C4dDir
Write-PathsJson @{ notepadplusplus = $nppDirB; cinema4d = $c4dDir }
@{ notepadplusplus = @{ palette = 'nosuchpalette'; path = $nppDirB; appVersion = 'n/a'; payloadVersion = '1.9.0'; applied = '2020-01-01T00:00:00Z' }
   cinema4d = @{ palette = 'goldendefault'; path = $c4dDir; appVersion = 'n/a'; payloadVersion = '1.9.0'; applied = '2020-01-01T00:00:00Z' } } |
    ConvertTo-Json -Depth 3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'reapply with one failing child exits NONZERO' ($LASTEXITCODE -ne 0)
check 'the failing target is named in the output' ($out -match 'FAILED' -and $out -match 'nosuchpalette')
check 'the successful sibling is still applied' (Test-Path (Join-Path $c4dDir 'resource\modules\c4d_base\schemes\Wintage\wintage.col'))
$mAfterFail = Read-TestManifest
check 'failed target manifest entry is NOT refreshed' ($mAfterFail.notepadplusplus.payloadVersion -eq '1.9.0')
$currentVer = (([System.IO.File]::ReadAllText((Join-Path $root 'wintage.user.js'), $utf8NoBom) -split "`n") | Where-Object { $_ -match '// @version\s+(\S+)' } | Select-Object -First 1) -replace '.*@version\s+(\S+).*', '$1'
check 'successful sibling manifest entry IS refreshed' ($mAfterFail.cinema4d.palette -eq 'goldendefault' -and $mAfterFail.cinema4d.payloadVersion -eq $currentVer)

# ---- Test 9: Notepad++ apply -> repaint -> revert restores pre-state ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1 | Out-Null
check 'notepadplusplus apply A exits 0' ($LASTEXITCODE -eq 0)
check 'notepadplusplus A theme installed' (Test-Path (Join-Path $nppDirB 'themes\Wintage.xml'))
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette dracula 2>&1 | Out-Null
check 'notepadplusplus apply B (repaint) exits 0' ($LASTEXITCODE -eq 0)
check 'notepadplusplus B marker updated' ((Get-Content (Join-Path $nppDirB 'themes\.wintage-npp-palette') -Raw).Trim() -eq 'dracula')
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Revert 2>&1 | Out-Null
check 'notepadplusplus revert exits 0' ($LASTEXITCODE -eq 0)
check 'notepadplusplus revert removed theme' (-not (Test-Path (Join-Path $nppDirB 'themes\Wintage.xml')))
check 'notepadplusplus revert removed marker' (-not (Test-Path (Join-Path $nppDirB 'themes\.wintage-npp-palette')))
check 'notepadplusplus revert removed manifest entry' (-not (Read-TestManifest).ContainsKey('notepadplusplus'))

# ---- Test 10: full chain apply -> reapply(noop) -> repaint -> revert ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1 | Out-Null
check 'chain: apply A exits 0' ($LASTEXITCODE -eq 0)
$chainApplied = [System.IO.File]::ReadAllText((Join-Path $nppDirB 'themes\Wintage.xml'), $utf8NoBom)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1 | Out-Null
check 'chain: reapply (up to date) exits 0' ($LASTEXITCODE -eq 0)
check 'chain: reapply is a no-op on the file' ([System.IO.File]::ReadAllText((Join-Path $nppDirB 'themes\Wintage.xml'), $utf8NoBom) -eq $chainApplied)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette dracula 2>&1 | Out-Null
check 'chain: repaint exits 0' ($LASTEXITCODE -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Revert 2>&1 | Out-Null
check 'chain: revert exits 0' ($LASTEXITCODE -eq 0)
check 'chain: revert removed theme' (-not (Test-Path (Join-Path $nppDirB 'themes\Wintage.xml')))

# ---- Test 11: corrupt manifest is reported clearly by -Status, exit nonzero ----
Clean-TestState
[System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), '{ broken', $utf8NoBom)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
check 'corrupt manifest status exits nonzero' ($LASTEXITCODE -ne 0)
check 'corrupt manifest status reports CORRUPT' ($out -match 'CORRUPT')
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'corrupt manifest reapply exits nonzero' ($LASTEXITCODE -ne 0)
check 'corrupt manifest reapply reports CORRUPT' ($out -match 'CORRUPT')

# ---- Test 12: an Electron helper failure bubbles through the dispatch ----
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

# ---- Test 13: an ELECTRON app update with the SAME payload triggers Reapply ----
Clean-TestState
$prevLocalAppData = $env:LOCALAPPDATA
try {
    $fakeLocal = Join-Path $testRoot 'localappdata2'
    $agRes = Join-Path $fakeLocal 'Programs\Antigravity\resources'
    New-Item -ItemType Directory -Path $agRes -Force | Out-Null
    Build-FakeAsar (Join-Path $agRes 'app.asar') '1.0.0'
    [System.IO.File]::WriteAllBytes((Join-Path $fakeLocal 'Programs\Antigravity\FakeApp.exe'), (New-FusedExe))
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

# ---- Test 14: a manifest-recorded target that VANISHED fails Reapply, entry kept ----
Clean-TestState
$goneWb = Join-Path $testRoot 'workbuddy-gone'
@{workbuddy=@{palette='goldendefault';path=$goneWb;appVersion='n/a';payloadVersion='99.99.99';applied='2026-01-01T00:00:00Z'}} | ConvertTo-Json |
    ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $_, $utf8NoBom) }
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'recorded-but-vanished target makes reapply exit NONZERO' ($LASTEXITCODE -ne 0)
check 'recorded-but-vanished target named as FAILED' ($out -match 'workbuddy' -and $out -match 'FAILED')
$mGone = Read-TestManifest
check 'recorded-but-vanished manifest entry is PRESERVED' ($mGone.workbuddy.path -eq $goneWb)

# ---- Test 15: strict vs bulk absence semantics (P0#3) ----
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

# ---- Test 16: concurrent manifest writers keep BOTH entries (P1#11) ----
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

# ---- Test 16b: abandoned-mutex recovery (P1#10) ----
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

# ---- Test 17: native target applies WITHOUT Node (P1#19) ----
Clean-TestState
$prevKey17 = $env:WINTAGE_TEST_CONHOST_KEY
$conRoot17 = 'HKCU:\Software\Wintage-Test-Conhost-' + [guid]::NewGuid().ToString('N')
$env:WINTAGE_TEST_CONHOST_KEY = $conRoot17
New-Item -Path $conRoot17 -Force | Out-Null
New-Item -Path (Join-Path $conRoot17 'Console') -Force | Out-Null
$env:WINTAGE_TEST_NO_NODE = '1'
try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'native target applies WITHOUT node' ($LASTEXITCODE -eq 0)
    check 'native target without node is actually themed' ((Get-ItemProperty $conRoot17 -Name WintagePalette).WintagePalette -eq 'goldendefault')
} finally {
    $env:WINTAGE_TEST_NO_NODE = ''
    Remove-Item $conRoot17 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey17
}

# ---- Test 18: a PRESENT generated-build consumer FAILS without Node (P1#19) ----
Clean-TestState
$prevLocal18 = $env:LOCALAPPDATA
try {
    $fakeLocal18 = Join-Path $testRoot 'localappdata-nn'
    $agRes18 = Join-Path $fakeLocal18 'Programs\Antigravity\resources'
    New-Item -ItemType Directory -Path $agRes18 -Force | Out-Null
    Build-FakeAsar (Join-Path $agRes18 'app.asar') '1.0.0'
    $env:LOCALAPPDATA = $fakeLocal18
    $env:WINTAGE_TEST_NO_NODE = '1'
    $prevEap18 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'antigravity-app' -Palette goldendefault 2>&1
    $code18 = $LASTEXITCODE
    $ErrorActionPreference = $prevEap18
    $env:WINTAGE_TEST_NO_NODE = ''
    check 'present generated-consumer target FAILS without node' ($code18 -ne 0)
} finally { $env:LOCALAPPDATA = $prevLocal18 }

# ---- Test 19: Write-Manifest failure cleans its tmp and keeps the old manifest (P1#20) ----
Clean-TestState
$mPath19 = Join-Path $appData 'installed.json'
. $common
$script:WintageAppData = $appData
$script:ManifestPath = $mPath19
$script:Utf8NoBom = $utf8NoBom
$prevFail = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$threw19 = $false
try { Set-ManifestEntry 'probe' 'golden' 'C:\p' '1' '2' } catch { $threw19 = $true }
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail
check 'Write-Manifest replace failure throws' $threw19
check 'Write-Manifest failure leaves the OLD manifest intact' (-not (Test-Path $mPath19))
check 'Write-Manifest failure leaves NO tmp garbage' (-not (Get-ChildItem $appData -Filter 'installed.json.tmp-*' -ErrorAction SilentlyContinue))

# ---- Test 20: marker tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1 | Out-Null
check 'marker-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
$marker20 = Join-Path $nppDirB 'themes\.wintage-npp-palette'
[System.IO.File]::WriteAllText($marker20, 'dracula', $utf8NoBom)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
check 'marker-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
$after20 = ([System.IO.File]::ReadAllText($marker20, $utf8NoBom)).Trim()
check 'marker-tamper: Reapply repaired the marker' ($after20 -eq 'goldendefault')

# ---- Test 21: BetterDiscord css tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
$prevApp21 = $env:APPDATA
$prevWintageApp21 = $env:WINTAGE_APPDATA
$pack21 = [System.IO.File]::ReadAllText((Join-Path $root 'themes\goldendefault.json'), $utf8NoBom) | ConvertFrom-Json
try {
    $fakeApp21 = Join-Path $testRoot 'bdappdata'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp21 'BetterDiscord\themes'), (Join-Path $fakeApp21 'Wintage') -Force | Out-Null
    $env:APPDATA = $fakeApp21
    $env:WINTAGE_APPDATA = Join-Path $fakeApp21 'Wintage'
    $bdOriginal21 = '/* user theme */'
    [System.IO.File]::WriteAllText((Join-Path $fakeApp21 'BetterDiscord\themes\wintage.theme.css'), $bdOriginal21, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target discord -Palette goldendefault 2>&1
    check 'discord-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
    $bdCss21 = Join-Path $fakeApp21 'BetterDiscord\themes\wintage.theme.css'
    $t21 = [System.IO.File]::ReadAllText($bdCss21, $utf8NoBom) -replace [regex]::Escape($pack21.tokens.background), '#000000'
    [System.IO.File]::WriteAllText($bdCss21, $t21, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'discord-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
    $after21 = [System.IO.File]::ReadAllText($bdCss21, $utf8NoBom)
    check 'discord-tamper: Reapply repaired the css' ($after21 -match [regex]::Escape($pack21.tokens.background))
    Remove-Item (Join-Path $fakeApp21 'Wintage\recovery\discord\pristine.css') -Force
    $beforeMissingPristine21 = [System.IO.File]::ReadAllBytes($bdCss21)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target discord -Revert 2>&1
    check 'discord-revert: missing pristine exits NONZERO' ($LASTEXITCODE -ne 0)
    $afterMissingPristine21 = [System.IO.File]::ReadAllBytes($bdCss21)
    check 'discord-revert: missing pristine preserves live css' (-not (Compare-Object $beforeMissingPristine21 $afterMissingPristine21))
} finally { $env:APPDATA = $prevApp21; $env:WINTAGE_APPDATA = $prevWintageApp21 }

# ---- Test 22: browser stage marker tamper is detected and repaired by Reapply (P1#16) ----
Clean-TestState
$prevLocal22 = $env:LOCALAPPDATA
$prevApp22 = $env:APPDATA
$prevWintageApp22 = $env:WINTAGE_APPDATA
try {
    $browserRoot22 = Join-Path $testRoot 'browsers22'
    $fakeBrowser22 = Join-Path $browserRoot22 'Portable Browser'
    $fakeExe22 = Join-Path $fakeBrowser22 'chrome.exe'
    $fakeData22 = Join-Path $fakeBrowser22 'User Data'
    $fakeProfile22 = Join-Path $fakeData22 'Default'
    $tmDir22 = Join-Path $fakeProfile22 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage22 = Join-Path $browserRoot22 'stage'
    New-Item -ItemType Directory -Path $tmDir22 -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe22, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile22 'Preferences'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $fakeData22 'Local State'), '{}', $utf8NoBom)
    $catalog22 = Join-Path $browserRoot22 'catalog.json'
    @([ordered]@{ Name = 'Fixture'; Exe = $fakeExe22; UserData = $fakeData22 }) | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog22, $_, $utf8NoBom) }
    $fakeApp22 = Join-Path $testRoot 'winappdata22'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp22 'Wintage') -Force | Out-Null
    $fakeLocal22 = Join-Path $testRoot 'localappdata22'
    New-Item -ItemType Directory -Path $fakeLocal22 -Force | Out-Null
    $env:LOCALAPPDATA = $fakeLocal22
    $env:APPDATA = $fakeApp22
    $env:WINTAGE_APPDATA = Join-Path $fakeApp22 'Wintage'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette goldendefault -BrowserCatalog $catalog22 -BrowserStageRoot $stage22 -NoBrowserLaunch 2>&1
    check 'browser-tamper: apply exits 0' ($LASTEXITCODE -eq 0)
    [System.IO.File]::WriteAllText((Join-Path $stage22 '.wintage-palette'), 'dracula', $utf8NoBom)
    # T-191: the Reapply child must inherit the catalog (never discover real
    # Edge/Chrome) and must NEVER reopen a browser over a repaint.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -BrowserCatalog $catalog22 -BrowserStageRoot $stage22 2>&1
    check 'browser-tamper: Reapply exits 0' ($LASTEXITCODE -eq 0)
    $after22 = ([System.IO.File]::ReadAllText((Join-Path $stage22 '.wintage-palette'), $utf8NoBom)).Trim()
    check 'browser-tamper: Reapply repaired the marker' ($after22 -eq 'goldendefault')
} finally { $env:LOCALAPPDATA = $prevLocal22; $env:APPDATA = $prevApp22; $env:WINTAGE_APPDATA = $prevWintageApp22 }

# ---- Test 23: corrupt manifest aborts BEFORE any target mutation (T-191 P0#1) ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
$theme23 = Join-Path $nppDirB 'themes\Wintage.xml'
$garbage23 = '{"this is ::: not valid json'
[System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), $garbage23, $utf8NoBom)
$out23 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1
check 'corrupt-precheck: install exits nonzero' ($LASTEXITCODE -ne 0)
check 'corrupt-precheck: target theme not created (no mutation)' (-not (Test-Path $theme23))
check 'corrupt-precheck: corrupt manifest still present (not overwritten)' ((Test-Path (Join-Path $appData 'installed.json')) -and ([System.IO.File]::ReadAllText((Join-Path $appData 'installed.json'), $utf8NoBom) -eq $garbage23))

# ---- Test 24: manifest-commit failure rolls the target back (T-191 P0#1) ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
$theme24 = Join-Path $nppDirB 'themes\Wintage.xml'
$prevFail24 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$out24 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail24
check 'commit-rollback: install exits nonzero' ($LASTEXITCODE -ne 0)
check 'commit-rollback: target restored to exact pre-operation state' (-not (Test-Path $theme24))
check 'commit-rollback: old manifest unchanged (still absent)' (-not (Test-Path (Join-Path $appData 'installed.json')))
check 'commit-rollback: rollback message surfaced' ($out24 -match 'restored to its exact pre-operation state')

# ---- Test 25: concurrent same-target installs serialize (T-191 P0#2) ----
Clean-TestState
Reset-NppDir
Write-PathsJson @{ notepadplusplus = $nppDirB }
$p1 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Target','notepadplusplus','-Palette','goldendefault') -PassThru -WindowStyle Hidden
$p2 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Target','notepadplusplus','-Palette','goldendefault') -PassThru -WindowStyle Hidden
$null = $p1.WaitForExit(60000)
$null = $p2.WaitForExit(60000)
check 'lock-serialize: both concurrent installs exited' ($p1.HasExited -and $p2.HasExited)
$exitSum = ($p1.ExitCode + $p2.ExitCode)
check 'lock-serialize: both installs succeeded (serialized, not corrupted)' ($p1.HasExited -and $p2.HasExited -and $exitSum -eq 0)
check 'lock-serialize: final file exists' (Test-Path (Join-Path $nppDirB 'themes\Wintage.xml'))
check 'lock-serialize: manifest recorded once, sane' ((Read-TestManifest).notepadplusplus.path -eq $nppDirB)

# ---- Test 26: browser stage rollback on manifest-commit failure (T-191 P0#10) ----
Clean-TestState
$prevLocal26 = $env:LOCALAPPDATA
$prevApp26 = $env:APPDATA
$prevWintage26 = $env:WINTAGE_APPDATA
try {
    $browserRoot26 = Join-Path $testRoot 'browsers26'
    $fakeBrowser26 = Join-Path $browserRoot26 'Portable Browser'
    $fakeExe26 = Join-Path $fakeBrowser26 'chrome.exe'
    $fakeData26 = Join-Path $fakeBrowser26 'User Data'
    $fakeProfile26 = Join-Path $fakeData26 'Default'
    $tmDir26 = Join-Path $fakeProfile26 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage26 = Join-Path $browserRoot26 'stage'
    New-Item -ItemType Directory -Path $tmDir26 -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe26, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile26 'Preferences'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $fakeData26 'Local State'), '{}', $utf8NoBom)
    $catalog26 = Join-Path $browserRoot26 'catalog.json'
    @([ordered]@{ Name = 'Fixture'; Exe = $fakeExe26; UserData = $fakeData26 }) | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog26, $_, $utf8NoBom) }
    $fakeApp26 = Join-Path $testRoot 'winappdata26'
    New-Item -ItemType Directory -Path (Join-Path $fakeApp26 'Wintage') -Force | Out-Null
    $fakeLocal26 = Join-Path $testRoot 'localappdata26'
    New-Item -ItemType Directory -Path $fakeLocal26 -Force | Out-Null
    $env:LOCALAPPDATA = $fakeLocal26
    $env:APPDATA = $fakeApp26
    $env:WINTAGE_APPDATA = Join-Path $fakeApp26 'Wintage'
    New-Item -ItemType Directory -Path $stage26 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $stage26 '.wintage-palette'), 'goldendefault', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $stage26 'manifest.json'), '{"name":"old"}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $stage26 '.wintage-owner.json'), '{"owner":"Wintage","schema":1,"palette":"goldendefault"}', $utf8NoBom)
    $prevFail26 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
    $out26 = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette dracula -BrowserCatalog $catalog26 -BrowserStageRoot $stage26 -NoBrowserLaunch 2>&1
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail26
    check 'browser-stage-rollback: install exits nonzero' ($LASTEXITCODE -ne 0)
    check 'browser-stage-rollback: stage marker restored to the pre-state palette' ([System.IO.File]::ReadAllText((Join-Path $stage26 '.wintage-palette'), $utf8NoBom) -eq 'goldendefault')
    check 'browser-stage-rollback: stage manifest restored' ([System.IO.File]::ReadAllText((Join-Path $stage26 'manifest.json'), $utf8NoBom) -match 'old')
} finally { $env:LOCALAPPDATA = $prevLocal26; $env:APPDATA = $prevApp26; $env:WINTAGE_APPDATA = $prevWintage26 }

# ---- Test 27: VS Code extension revert restores the apply-time backup (T-191 P0#11) ----
Clean-TestState
$prevHome27 = $env:HOME
$prevProfile27 = $env:USERPROFILE
$prevBakRoot27 = $env:WINTAGE_BACKUP_ROOT
$prevWintage27 = $env:WINTAGE_APPDATA
try {
    $fakeHome27 = Join-Path $testRoot 'fakehome27'
    $extDir27 = Join-Path $fakeHome27 '.vscode\extensions'
    $dest27 = Join-Path $extDir27 'wintage-themes'
    New-Item -ItemType Directory -Path (Join-Path $dest27 'themes') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest27 'themes\stock.json'), '{"name":"stock"}', $utf8NoBom)
    $fakeApp27 = Join-Path $testRoot 'winappdata27'
    New-Item -ItemType Directory -Path $fakeApp27 -Force | Out-Null
    $env:HOME = $fakeHome27
    $env:USERPROFILE = $fakeHome27
    $env:WINTAGE_BACKUP_ROOT = Join-Path $testRoot 'backup27'
    $env:WINTAGE_APPDATA = $fakeApp27
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Palette goldendefault 2>&1
    check 'vscode-backup: apply exits 0' ($LASTEXITCODE -eq 0)
    check 'vscode-backup: Wintage themes installed' (Test-Path (Join-Path $dest27 'themes'))
    $m27 = Join-Path $fakeApp27 'installed.json'
    check 'vscode-backup: manifest recorded' ((Test-Path $m27) -and ((Get-Content $m27 -Raw | ConvertFrom-Json).vscode.palette -eq 'goldendefault'))
    # T-192 P1#15: recovery lives under WINTAGE_APPDATA/recovery (non-pruned authority).
    $rec27 = Join-Path $fakeApp27 'recovery\vscode'
    $pristine27 = Join-Path $rec27 'pristine'
    check 'vscode-backup: recovery mode recorded as replaced' (((Get-Content (Join-Path $rec27 'recovery.json') -Raw | ConvertFrom-Json).mode -eq 'replaced'))
    check 'vscode-backup: pristine snapshot captured under recovery/' (Test-Path (Join-Path $pristine27 'themes\stock.json'))
    $pristineBytes27 = [System.IO.File]::ReadAllBytes((Join-Path $pristine27 'themes\stock.json'))
    # Repaint to another palette must NOT overwrite the pristine snapshot.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Palette dracula 2>&1
    check 'vscode-backup: repaint exits 0' ($LASTEXITCODE -eq 0)
    $pristineAfter27 = [System.IO.File]::ReadAllBytes((Join-Path $pristine27 'themes\stock.json'))
    $same27 = $pristineAfter27.Length -eq $pristineBytes27.Length
    if ($same27) { for ($i = 0; $i -lt $pristineAfter27.Length; $i++) { if ($pristineAfter27[$i] -ne $pristineBytes27[$i]) { $same27 = $false; break } } }
    check 'vscode-backup: repaint never overwrites the pristine snapshot' $same27
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target vscode -Revert 2>&1
    check 'vscode-backup: revert exits 0' ($LASTEXITCODE -eq 0)
    check 'vscode-backup: revert restores the ORIGINAL pre-Wintage tree' (Test-Path (Join-Path $dest27 'themes\stock.json'))
    check 'vscode-backup: repainted artifact gone after revert' (-not (Test-Path (Join-Path $dest27 'themes\dracula.json')))
    $m27After = if (Test-Path $m27) { Get-Content $m27 -Raw | ConvertFrom-Json } else { $null }
    check 'vscode-backup: manifest entry removed' ((-not $m27After) -or -not $m27After.vscode)
} finally { $env:HOME = $prevHome27; $env:USERPROFILE = $prevProfile27; $env:WINTAGE_BACKUP_ROOT = $prevBakRoot27; $env:WINTAGE_APPDATA = $prevWintage27 }

# ---- Test 28: conhost revert keeps its backup until the manifest transition succeeds (T-192 P0#4) ----
Clean-TestState
$prevKey28 = $env:WINTAGE_TEST_CONHOST_KEY
$prevBakBase28 = $env:WINTAGE_BACKUP_ROOT
$prevWintage28 = $env:WINTAGE_APPDATA
try {
    $conRoot28 = 'HKCU:\Software\Wintage-Test-Conhost-' + [guid]::NewGuid().ToString('N')
    $env:WINTAGE_TEST_CONHOST_KEY = $conRoot28
    $fakeBak28 = Join-Path $testRoot 'backup28'
    $env:WINTAGE_BACKUP_ROOT = $fakeBak28
    $fakeApp28 = Join-Path $testRoot 'winappdata28'
    $env:WINTAGE_APPDATA = $fakeApp28
    New-Item -Path $conRoot28 -Force | Out-Null
    New-Item -Path (Join-Path $conRoot28 'Console') -Force | Out-Null
    New-ItemProperty -Path $conRoot28 -Name ColorTable00 -Value 0x00999999 -PropertyType DWord -Force | Out-Null
    $mPath28 = Join-Path $fakeApp28 'installed.json'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'conhost-recovery: apply exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-recovery: WintagePalette recorded' ((Get-ItemProperty $conRoot28 -Name WintagePalette).WintagePalette -eq 'goldendefault')
    $bak28 = Join-Path $fakeBak28 'conhost-settings.json'
    check 'conhost-recovery: apply-time backup exists' (Test-Path $bak28)
    # Inject a manifest-remove failure during Revert.
    $prevFail28 = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFail28
    check 'conhost-recovery: failing revert exits NONZERO' ($LASTEXITCODE -ne 0)
    check 'conhost-recovery: recovery backup still valid after failure' (Test-Path $bak28)
    check 'conhost-recovery: manifest still recorded after failure' ((Test-Path $mPath28) -and (Get-Content $mPath28 -Raw | ConvertFrom-Json).conhost)
    check 'conhost-recovery: themed state restored after failure (matches manifest)' ((Get-ItemProperty $conRoot28 -Name WintagePalette).WintagePalette -eq 'goldendefault')
    # Clean retry Revert must succeed and consume the backup.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    check 'conhost-recovery: retry revert exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-recovery: retry consumes the backup' (-not (Test-Path $bak28))
    check 'conhost-recovery: manifest removed on retry' (-not ((Test-Path $mPath28) -and (Get-Content $mPath28 -Raw | ConvertFrom-Json).conhost))
    check 'conhost-recovery: pre-Wintage value restored' ((Get-ItemProperty $conRoot28 -Name ColorTable00).ColorTable00 -eq 0x00999999)
    check 'conhost-recovery: no mixed state (marker gone)' (-not ((Get-ItemProperty $conRoot28 -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'WintagePalette'))
} finally {
    Remove-Item $conRoot28 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey28
    $env:WINTAGE_BACKUP_ROOT = $prevBakBase28
    $env:WINTAGE_APPDATA = $prevWintage28
}

# ---- Test 29: browser stage ownership - unowned dir is NEVER deleted (T-192 P0#14) ----
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
    # Unowned stage with real user data - no owner marker.
    New-Item -ItemType Directory -Path $stage29 -Force | Out-Null
    $important29 = 'user data that must survive'
    [System.IO.File]::WriteAllText((Join-Path $stage29 'important.txt'), $important29, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Palette goldendefault -BrowserCatalog $catalog29 -BrowserStageRoot $stage29 -NoBrowserLaunch 2>&1
    check 'browser-ownership: unowned Apply REFUSED (nonzero)' ($LASTEXITCODE -ne 0)
    check 'browser-ownership: important.txt preserved byte-identical' ([System.IO.File]::ReadAllText((Join-Path $stage29 'important.txt'), $utf8NoBom) -eq $important29)
    check 'browser-ownership: no owner marker written over user data' (-not (Test-Path (Join-Path $stage29 '.wintage-owner.json')))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target browsers -Revert -BrowserCatalog $catalog29 -BrowserStageRoot $stage29 -NoBrowserLaunch 2>&1
    check 'browser-ownership: unowned Revert REFUSED (nonzero)' ($LASTEXITCODE -ne 0)
    check 'browser-ownership: important.txt still intact after refused Revert' ([System.IO.File]::ReadAllText((Join-Path $stage29 'important.txt'), $utf8NoBom) -eq $important29)
    check 'browser-ownership: no manifest entry recorded' (-not ((Test-Path (Join-Path $fakeApp29 'Wintage\installed.json')) -and (Get-Content (Join-Path $fakeApp29 'Wintage\installed.json') -Raw | ConvertFrom-Json).browsers))
} finally { $env:LOCALAPPDATA = $prevLocal29; $env:APPDATA = $prevApp29; $env:WINTAGE_APPDATA = $prevWintage29 }

# ---- Test 30: manifest schema validation rejects syntax-valid garbage (T-192 P1#20) ----
Clean-TestState
$prevW30 = $env:WINTAGE_APPDATA
try {
    $fakeApp30 = Join-Path $testRoot 'winappdata30'
    New-Item -ItemType Directory -Path $fakeApp30 -Force | Out-Null
    $env:WINTAGE_APPDATA = $fakeApp30
    $m30 = Join-Path $fakeApp30 'installed.json'
    $cases30 = @(
        @{ Name = 'non-array items'; Body = '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}' },
        @{ Name = 'top-level array'; Body = '[]' },
        @{ Name = 'scalar manifest'; Body = '"hello"' },
        @{ Name = 'non-object entry'; Body = '{"notepadplusplus":42}' },
        @{ Name = 'wrong-typed field'; Body = '{"conhost":{"palette":5,"path":"x","appVersion":"1","payloadVersion":"1","applied":"z"}}' }
    )
    foreach ($c in $cases30) {
        [System.IO.File]::WriteAllText($m30, $c.Body, $utf8NoBom)
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
        check "manifest-schema: $($c.Name) reported by -Status (nonzero)" ($LASTEXITCODE -ne 0)
        check "manifest-schema: $($c.Name) message says schema" ($out -match 'schema')
        check "manifest-schema: $($c.Name) file NOT overwritten by the read" ([System.IO.File]::ReadAllText($m30, $utf8NoBom) -eq $c.Body)
    }
    # Set-ManifestEntry must refuse to overwrite schema-invalid content.
    [System.IO.File]::WriteAllText($m30, '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}', $utf8NoBom)
    Reset-NppDir
    Write-PathsJson @{ notepadplusplus = $nppDirB }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target notepadplusplus -Palette goldendefault 2>&1
    check 'manifest-schema: Apply over schema-invalid manifest exits NONZERO' ($LASTEXITCODE -ne 0)
    check 'manifest-schema: schema-invalid manifest preserved byte-exact' ([System.IO.File]::ReadAllText($m30, $utf8NoBom) -eq '{"terminal":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z","items":"oops"}}')
    # Unknown target keys are preserved + readable (never destroyed).
    $future30 = '{"futuretarget":{"palette":"a","path":"x","appVersion":"1","payloadVersion":"1","applied":"z"}}'
    [System.IO.File]::WriteAllText($m30, $future30, $utf8NoBom)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Status 2>&1
    check 'manifest-schema: unknown future target key is readable (Status exits 0)' ($LASTEXITCODE -eq 0)
} finally { $env:WINTAGE_APPDATA = $prevW30 }

# ---- Test 31: conhost scrollback floor - zero-history console profiles get a usable buffer (T-193) ----
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
    # The broken shape this reproduces: buffer height == window height (25 rows,
    # 106 cols) - i.e. ZERO scrollback, the "terminal cuts my history" bug.
    New-ItemProperty -Path $conRoot31 -Name ScreenBufferSize -Value ((25 -shl 16) -bor 106) -PropertyType DWord -Force | Out-Null
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'conhost-scrollback: apply exits 0' ($LASTEXITCODE -eq 0)
    $buf31 = (Get-ItemProperty $conRoot31 -Name ScreenBufferSize).ScreenBufferSize
    check 'conhost-scrollback: buffer height raised to the 9001 floor' (((($buf31 -shr 16) -band 0xFFFF) -ge 9001))
    check 'conhost-scrollback: buffer width preserved' ((($buf31 -band 0xFFFF) -eq 106))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Revert 2>&1
    check 'conhost-scrollback: revert exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-scrollback: original zero-history buffer restored byte-exact' ((Get-ItemProperty $conRoot31 -Name ScreenBufferSize).ScreenBufferSize -eq ((25 -shl 16) -bor 106))
} finally {
    Remove-Item $conRoot31 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey31
    $env:WINTAGE_BACKUP_ROOT = $prevBakBase31
    $env:WINTAGE_APPDATA = $prevWintage31
}

# ---- Test 32: conhost Reapply health detects a scrollback buffer that collapsed
# back to the window height AFTER apply (conhost rewrites ScreenBufferSize on
# resize) and re-asserts the 9001 floor -> the scrollbar returns (T-203 follow-up) ----
Clean-TestState
$prevKey32 = $env:WINTAGE_TEST_CONHOST_KEY
$prevBakBase32 = $env:WINTAGE_BACKUP_ROOT
$prevWintage32 = $env:WINTAGE_APPDATA
try {
    $conRoot32 = 'HKCU:\Software\Wintage-Test-Conhost-' + [guid]::NewGuid().ToString('N')
    $env:WINTAGE_TEST_CONHOST_KEY = $conRoot32
    $fakeBak32 = Join-Path $testRoot 'backup32'
    $env:WINTAGE_BACKUP_ROOT = $fakeBak32
    $fakeApp32 = Join-Path $testRoot 'winappdata32'
    $env:WINTAGE_APPDATA = $fakeApp32
    New-Item -Path $conRoot32 -Force | Out-Null
    # Apply from a collapsed (zero-scrollback) start -> buffer is raised to 9001.
    New-ItemProperty -Path $conRoot32 -Name ScreenBufferSize -Value ((25 -shl 16) -bor 106) -PropertyType DWord -Force | Out-Null
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target conhost -Palette goldendefault 2>&1
    check 'conhost-reapply-health: apply exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-reapply-health: apply raised buffer to 9001' ((((Get-ItemProperty $conRoot32 -Name ScreenBufferSize).ScreenBufferSize -shr 16) -band 0xFFFF) -ge 9001)
    # The user bug: conhost later rewrites ScreenBufferSize back to window height,
    # collapsing scrollback. The WintagePalette marker stays intact.
    New-ItemProperty -Path $conRoot32 -Name ScreenBufferSize -Value ((25 -shl 16) -bor 106) -PropertyType DWord -Force | Out-Null
    check 'conhost-reapply-health: simulated drift collapsed the buffer' ((((Get-ItemProperty $conRoot32 -Name ScreenBufferSize).ScreenBufferSize -shr 16) -band 0xFFFF) -eq 25)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'conhost-reapply-health: reapply exits 0' ($LASTEXITCODE -eq 0)
    check 'conhost-reapply-health: reapply re-asserts the 9001 floor' ((((Get-ItemProperty $conRoot32 -Name ScreenBufferSize).ScreenBufferSize -shr 16) -band 0xFFFF) -ge 9001)
    check 'conhost-reapply-health: reapply names the collapsed profile' ($out -match 'scrollback collapsed')
} finally {
    Remove-Item $conRoot32 -Recurse -Force -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_CONHOST_KEY = $prevKey32
    $env:WINTAGE_BACKUP_ROOT = $prevBakBase32
    $env:WINTAGE_APPDATA = $prevWintage32
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail

} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
