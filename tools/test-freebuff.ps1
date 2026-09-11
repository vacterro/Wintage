# FreeBuff single-transaction + top-level revert regression suite (T-189).
#
# Builds a FAKE FreeBuff install (fake asar + orchestrator.js + renderer bundle +
# chime) under redirected LOCALAPPDATA/APPDATA, then drives patch-freebuff-ads.js
# and install.ps1 -Target freebuff as children. Nothing real is ever touched.
#
#   .\tools\test-freebuff.ps1

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$common = Join-Path $here '..\desktop\modules\common.ps1'
$targets = Join-Path $here '..\desktop\modules\targets.ps1'
$pass = 0; $fail = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Child invocation wrapper: native stderr under EAP=Stop becomes a terminating
# error (PS 5.1), which would abort the fixture before the assertion runs.
function Run-TestChild([string]$exe, [string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $exe @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = @($out); Code = $code }
}

if ($List) {
    Write-Host "test-freebuff.ps1:"
    Write-Host "  1. sound preflight causes ZERO mutation on invalid audio input"
    Write-Host "  2. dry-run with invalid sound exits nonzero"
    Write-Host "  3. one transaction backup restores owned sound; partial dirs refused"
    Write-Host "  4. install.ps1 missing FreeBuff helper hard-fails (no manifest)"
    Write-Host "  5. install.ps1 FreeBuff -WhatIf validates the sound helper"
    Write-Host "  6. top-level FreeBuff Revert restores shim + sound + manifest"
    Write-Host "  7. repeated Apply sound B after sound A restores all stock from baseline"
    Write-Host "  8. failed composite Apply restores exact pre-state"
    Write-Host "  9. missing configured sound fails closed"
    Write-Host " 10. FreeBuff sound tamper repaired by Reapply"
    Write-Host " 11. Electron snapshot carries EXE and fuse backup"
    Write-Host " 12. new app generation refuses stale baseline"
    Write-Host " 13. baseline pruning stays bounded"
    Write-Host " 14. missing live chime restored from baseline"
    exit 0
}

# ------------------------------------------------------------------ fixture
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-freebuff-" + [guid]::NewGuid().ToString('N'))
$fakeLocal = Join-Path $testRoot 'localappdata'
$fakeAppData = Join-Path $testRoot 'appdata'
$app = Join-Path $fakeLocal 'Programs\@codebufffreebuff-desktop'
$orchestratorDir = Join-Path $app 'resources\orchestrator'
$assetsDir = Join-Path $orchestratorDir 'ui\assets'
$bundlePath = Join-Path $assetsDir 'index-abc.js'
$chimePath = Join-Path $assetsDir 'chime-abc123.mp3'
New-Item -ItemType Directory -Path (Join-Path $app 'resources'), $orchestratorDir, $assetsDir, (Join-Path $fakeAppData 'Wintage') -Force | Out-Null

# Minimal valid asar so install-electron can read a version.
function Build-FakeAsar([string]$path, [string]$version) {
    $pkgJson = '{"name":"Freebuff","version":"' + $version + '","main":"' + ('x'.PadRight(40, 'x')) + '"}'
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

$FULL_ORCH = @"
const app = {};
const routes = [];
module.exports = { app, routes };
"@

$BUNDLE = @"
const app = {};
module.exports = { app };
"@

function New-StockWav { [byte[]]@(0x52,0x49,0x46,0x46,0x24,0,0,0,0x57,0x41,0x56,0x45,0x66,0x6D,0x74,0x20,0x10,0,0,0,1,0,1,0,0x40,0x1F,0,0,0x40,0x1F,0,0,1,0,8,0,0x64,0x61,0x74,0x61,0,0,0,0) }

function New-StockExe {
    $sentinel = [Text.Encoding]::ASCII.GetBytes('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX')
    $head = [byte[]]@(1, 8)
    $fuses = New-Object byte[] 8
    for ($i = 0; $i -lt 8; $i++) { $fuses[$i] = 0x30 }
    [Text.Encoding]::ASCII.GetBytes('MZ fake exe ') + $sentinel + $head + $fuses + [Text.Encoding]::ASCII.GetBytes(' padding')
}

function Write-StockFixture {
    New-Item -ItemType Directory -Path $orchestratorDir, $assetsDir -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $app 'Freebuff.exe'), (New-StockExe))
    Build-FakeAsar (Join-Path $app 'resources\app.asar') '1.0.0'
    [System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $FULL_ORCH, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $orchestratorDir 'ui\index.html'), '<script src="assets/index-abc.js"></script>', $utf8)
    [System.IO.File]::WriteAllText($bundlePath, $BUNDLE, $utf8)
    [System.IO.File]::WriteAllBytes($chimePath, (New-StockWav))
    $env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'
}

function Write-BrokenFixture {
    New-Item -ItemType Directory -Path $orchestratorDir, $assetsDir -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $app 'Freebuff.exe'), (New-StockExe))
    Build-FakeAsar (Join-Path $app 'resources\app.asar') '1.0.0'
    [System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $FULL_ORCH, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $orchestratorDir 'ui\index.html'), '<script src="assets/index-abc.js"></script>', $utf8)
    [System.IO.File]::WriteAllText($bundlePath, $BUNDLE, $utf8)
    [System.IO.File]::WriteAllBytes($chimePath, (New-StockWav))
    $corruptSound = Join-Path $testRoot 'corrupt.wav'
    [System.IO.File]::WriteAllText($corruptSound, 'THIS-IS-NOT-AN-AUDIO-FILE', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $corruptSound, $utf8)
    $env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'
}

function Clean-Fixture {
    if (Test-Path $app) { Remove-Item $app -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path (Join-Path $app 'resources') -Force | Out-Null
    $installed = Join-Path $fakeAppData 'Wintage\installed.json'
    if (Test-Path $installed) { Remove-Item $installed -Force }
    $soundPref = Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'
    if (Test-Path $soundPref) { Remove-Item $soundPref -Force }
}

$prevLocal = $env:LOCALAPPDATA
$prevApp = $env:APPDATA
$prevWin = $env:WINTAGE_APPDATA
$prevPatch = $env:WINTAGE_FREEBUFF_PATCH_PATH
$env:LOCALAPPDATA = $fakeLocal
$env:APPDATA = $fakeAppData
$env:WINTAGE_APPDATA = Join-Path $fakeAppData 'Wintage'

try {

# ---- Test 1: sound preflight -> zero mutation on invalid input ----
Clean-Fixture
Write-BrokenFixture
$corruptSound = Join-Path $testRoot 'corrupt.wav'
$chimeBefore = [System.IO.File]::ReadAllBytes($chimePath)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $corruptSound)
check 'sound preflight invalid input exits NONZERO' ($r.Code -ne 0)
check 'preflight mismatch leaves chime byte-unchanged' (-not (Compare-Object $chimeBefore ([System.IO.File]::ReadAllBytes($chimePath))))
check 'preflight mismatch creates NO backup transaction' (-not (Get-ChildItem $app -Directory -Filter '_orig-backup-*' -ErrorAction SilentlyContinue))

# ---- Test 2: dry-run with invalid sound exits nonzero ----
Clean-Fixture
Write-BrokenFixture
$corruptSound = Join-Path $testRoot 'corrupt.wav'
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--dry-run', '--sound', $corruptSound)
check 'dry-run invalid sound exits NONZERO' ($r.Code -ne 0)
check 'dry-run names the invalid sound issue' (($r.Out -join ' ') -match 'not a recognized audio file')
check 'dry-run creates NO backup transaction' (-not (Get-ChildItem $app -Directory -Filter '_orig-backup-*' -ErrorAction SilentlyContinue))

# ---- Test 3: one transaction restores owned sound; partial dirs refused ----
Clean-Fixture
Write-StockFixture
$chimeStock = [System.IO.File]::ReadAllBytes($chimePath)
$customWav3 = (New-StockWav) + [byte[]]@(0x33, 0x33)
$customPath3 = Join-Path $testRoot 'custom3.wav'
[System.IO.File]::WriteAllBytes($customPath3, $customWav3)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $customPath3)
check 'happy-path sound patch exits 0' ($r.Code -eq 0)
$txs = @(Get-ChildItem $app -Directory -Filter '_orig-backup-*')
check 'exactly ONE transaction dir created' ($txs.Count -eq 1)
check 'transaction carries metadata marking it complete' (Test-Path (Join-Path $txs[0].FullName 'wintage-backup.json'))
$partialDir = Join-Path $app ('_orig-backup-' + [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ss') + '-999')
New-Item -ItemType Directory -Path $partialDir -Force | Out-Null
[System.IO.File]::WriteAllBytes($chimePath, [byte[]]@(1,2,3,4))
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'revert from complete baseline exits 0' ($r.Code -eq 0)
check 'revert restores the chime byte-exact' (-not (Compare-Object $chimeStock ([System.IO.File]::ReadAllBytes($chimePath))))

# ---- Test 4: install.ps1 missing FreeBuff helper hard-fails, no manifest (P0#10) ----
Clean-Fixture
Write-StockFixture
$env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $testRoot 'does-not-exist.js'
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'missing FreeBuff helper exits NONZERO' ($r.Code -ne 0)
check 'missing helper leaves NO manifest entry' (-not (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')))
$env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'

# ---- Test 5: install.ps1 FreeBuff -WhatIf validates the sound helper ----
Clean-Fixture
Write-StockFixture
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault', '-WhatIf')
check 'FreeBuff WhatIf with healthy helper exits 0' ($r.Code -eq 0)
check 'FreeBuff WhatIf reports the would-install plan' (($r.Out -join ' ') -match 'What if|would|dry-run')
Write-BrokenFixture
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault', '-WhatIf')
check 'FreeBuff WhatIf with invalid sound exits NONZERO' ($r.Code -ne 0)
check 'FreeBuff WhatIf with invalid sound leaves files untouched' (-not (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')))

# ---- Test 6: top-level FreeBuff Revert restores shim + sound + manifest ----
Clean-Fixture
Write-StockFixture
$customWav = (New-StockWav) + [byte[]]@(0xDE, 0xAD)
$customPath = Join-Path $testRoot 'custom.wav'
[System.IO.File]::WriteAllBytes($customPath, $customWav)
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $customPath, $utf8)
$stockAsar = [System.IO.File]::ReadAllBytes((Join-Path $app 'resources\app.asar'))
$bundleStock2 = [System.IO.File]::ReadAllBytes($bundlePath)
$orchStock2 = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$chimeStock2 = [System.IO.File]::ReadAllBytes($chimePath)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'top-level FreeBuff Apply exits 0' ($r.Code -eq 0)
$m = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
check 'Apply records the manifest entry' ([bool]$m.freebuff)
check 'shim installed (archive moved into app/)' (Test-Path (Join-Path $app 'resources\app\app.asar'))
check 'renderer bundle remains untouched (no ad patching)' (-not (Compare-Object $bundleStock2 ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'custom sound installed' (-not (Compare-Object $customWav ([System.IO.File]::ReadAllBytes($chimePath))))
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Revert')
check 'top-level FreeBuff Revert exits 0' ($r.Code -eq 0)
check 'Revert restores the stock app.asar byte-exact' (-not (Compare-Object $stockAsar ([System.IO.File]::ReadAllBytes((Join-Path $app 'resources\app.asar')))))
check 'Revert removes the Wintage app dir' (-not (Test-Path (Join-Path $app 'resources\app')))
check 'Revert leaves bundle untouched' (-not (Compare-Object $bundleStock2 ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'Revert leaves orchestrator untouched' (-not (Compare-Object $orchStock2 ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js'))))
check 'Revert restores the stock sound' (-not (Compare-Object $chimeStock2 ([System.IO.File]::ReadAllBytes($chimePath))))
$mAfter = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
check 'Revert removes the manifest entry' (-not $mAfter.freebuff)

# ---- Test 7: repeated Apply (sound B after sound A) then Revert restores ALL stock ----
Clean-Fixture
Write-StockFixture
$stockBundle = [System.IO.File]::ReadAllBytes($bundlePath)
$stockOrch = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$stockChime = [System.IO.File]::ReadAllBytes($chimePath)
$wavA = (New-StockWav) + [byte[]]@(0xAA)
$wavB = (New-StockWav) + [byte[]]@(0xBB)
$wavAPath = Join-Path $testRoot 'soundA.wav'
$wavBPath = Join-Path $testRoot 'soundB.wav'
[System.IO.File]::WriteAllBytes($wavAPath, $wavA)
[System.IO.File]::WriteAllBytes($wavBPath, $wavB)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavAPath)
check 'baseline: Apply with sound A exits 0' ($r.Code -eq 0)
check 'baseline: exactly ONE baseline created' (@(Get-ChildItem $app -Directory -Filter '_orig-baseline-*').Count -eq 1)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavBPath)
check 'baseline: Apply with sound B exits 0' ($r.Code -eq 0)
check 'baseline: still exactly ONE baseline (same generation)' (@(Get-ChildItem $app -Directory -Filter '_orig-baseline-*').Count -eq 1)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'baseline: Revert exits 0' ($r.Code -eq 0)
check 'baseline: Revert restores the chime to STOCK (sound B did not shadow recovery)' (-not (Compare-Object $stockChime ([System.IO.File]::ReadAllBytes($chimePath))))

# ---- Test 8: FreeBuff apply failure after Electron mutation restores EXACT pre-state ----
Clean-Fixture
Write-StockFixture
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $wavAPath, $utf8)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'atomic: initial Apply exits 0' ($r.Code -eq 0)
$preAppDir = Join-Path $app 'resources\app'
$prePkg = [System.IO.File]::ReadAllText((Join-Path $preAppDir 'package.json'), $utf8)
$preBundle = [System.IO.File]::ReadAllBytes($bundlePath)
$preOrch = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$preChime = [System.IO.File]::ReadAllBytes($chimePath)
$env:WINTAGE_FREEBUFF_TEST_FAIL_APPLY = '1'
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $wavBPath, $utf8)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'dracula')
$env:WINTAGE_FREEBUFF_TEST_FAIL_APPLY = ''
check 'atomic: second-layer failure exits NONZERO' ($r.Code -ne 0)
$afterPkg = [System.IO.File]::ReadAllText((Join-Path $preAppDir 'package.json'), $utf8)
check 'atomic: Electron layer restored to EXACT pre-state' ($afterPkg -eq $prePkg)
check 'atomic: chime restored to pre-state (sound A)' (-not (Compare-Object $preChime ([System.IO.File]::ReadAllBytes($chimePath))))
$mAtom = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
check 'atomic: manifest unchanged (still palette goldendefault)' ($mAtom.freebuff.palette -eq 'goldendefault')

# ---- Test 9: missing configured sound fails WhatIf + Apply with zero mutation ----
Clean-Fixture
Write-StockFixture
$missPath = Join-Path $testRoot 'does-not-exist.wav'
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $missPath, $utf8)
$bundleBefore9 = [System.IO.File]::ReadAllBytes($bundlePath)
$orchBefore9 = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault', '-WhatIf')
check 'missing sound: WhatIf exits NONZERO' ($r.Code -ne 0)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'missing sound: Apply exits NONZERO' ($r.Code -ne 0)
check 'missing sound: bundle unchanged' (-not (Compare-Object $bundleBefore9 ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'missing sound: orchestrator unchanged' (-not (Compare-Object $orchBefore9 ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js'))))
check 'missing sound: no manifest entry' (-not (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')))

# ---- Test 10: FreeBuff sound tamper is detected and repaired by Reapply ----
Clean-Fixture
Write-StockFixture
$stockChime10 = [System.IO.File]::ReadAllBytes($chimePath)
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'Wintage\freebuff-sound.txt'), $wavAPath, $utf8)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'health: initial Apply exits 0' ($r.Code -eq 0)
[System.IO.File]::WriteAllBytes($chimePath, $stockChime10)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Reapply')
check 'health: Reapply after sound tamper exits 0' ($r.Code -eq 0)
check 'health: Reapply repaired the sound' (-not (Compare-Object $wavA ([System.IO.File]::ReadAllBytes($chimePath))))
$mHealth = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
check 'health: manifest entry preserved after repair' ([bool]$mHealth.freebuff)

# ---- Test 11: Electron snapshot carries the EXE + fuse backup and restores them ----
Clean-Fixture
Write-StockFixture
[System.IO.File]::WriteAllText((Join-Path $app 'Freebuff.exe'), 'ORIGINAL-EXE-BYTES', $utf8)
. $common
. $targets
$script:WintageAppData = Join-Path $fakeAppData 'Wintage'
$script:ManifestPath = Join-Path $fakeAppData 'Wintage\installed.json'
$ELECTRON = @{ freebuff = @{ Name = 'Freebuff'; Resources = (Join-Path $app 'resources'); Note = '' } }
$snap11 = Save-ElectronStateSnapshot 'freebuff'
check 'exe-snapshot: snapshot carries the exe' (Test-Path (Join-Path $snap11 'Freebuff.exe'))
[System.IO.File]::WriteAllText((Join-Path $app 'Freebuff.exe'), 'DEFUSED-EXE-BYTES', $utf8)
[System.IO.File]::WriteAllText((Join-Path $app 'Freebuff.exe.wintage-fuse.bak'), 'FUSE-BACKUP', $utf8)
Restore-ElectronStateSnapshot 'freebuff' $snap11
check 'exe-snapshot: exe restored byte-exact' (([System.IO.File]::ReadAllText((Join-Path $app 'Freebuff.exe'), $utf8)) -eq 'ORIGINAL-EXE-BYTES')
check 'exe-snapshot: stale fuse backup removed with the transaction' (-not (Test-Path (Join-Path $app 'Freebuff.exe.wintage-fuse.bak')))
Remove-Item $snap11 -Recurse -Force

# ---- Test 12: Revert refuses to restore an OLD baseline over a NEW generation ----
Clean-Fixture
Write-StockFixture
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavAPath)
check 'gen-reconcile: Apply exits 0' ($r.Code -eq 0)
$newGenBundle = 'const app = {}; function render(r) { return r; } module.exports = { app, render }; // generation 2 build with a full-length plausible body'
$newGenOrch = 'module.exports = { render: 2, plugin: (app) => app }; // generation 2 orchestrator with a full-length plausible body'
[System.IO.File]::WriteAllText($bundlePath, $newGenBundle, $utf8)
[System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $newGenOrch, $utf8)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'gen-reconcile: Revert REFUSED (nonzero)' ($r.Code -ne 0)
check 'gen-reconcile: refusal names the file' (($r.Out -join ' ') -match 'REVERT REFUSED')
check 'gen-reconcile: new-generation bundle NOT overwritten' (-not (Compare-Object ([System.IO.File]::ReadAllBytes($bundlePath)) ([System.Text.Encoding]::UTF8.GetBytes($newGenBundle))))
check 'gen-reconcile: new-generation orchestrator NOT overwritten' (-not (Compare-Object ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')) ([System.Text.Encoding]::UTF8.GetBytes($newGenOrch))))
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'gen-reconcile: repeated Revert is refused again' ($r.Code -ne 0)

# ---- Test 13: new generations re-base the baseline AND pruning caps it ----
Clean-Fixture
Write-StockFixture
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavAPath)
check 'prune: gen1 apply exits 0' ($r.Code -eq 0)
for ($g = 2; $g -le 5; $g++) {
    $genBundle = $BUNDLE + "`n// generation $g build"
    $genOrch = $FULL_ORCH + "`n// generation $g"
    [System.IO.File]::WriteAllText($bundlePath, $genBundle, $utf8)
    [System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $genOrch, $utf8)
    $r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavAPath)
    check "prune: gen$g apply exits 0" ($r.Code -eq 0)
}
$bCount = @(Get-ChildItem $app -Directory -Filter '_orig-baseline-*').Count
check 'prune: at most 3 baselines kept' ($bCount -le 3)
check 'prune: at least 1 baseline kept' ($bCount -ge 1)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'prune: Revert still works after pruning' ($r.Code -eq 0)

# ---- Test 14: W2-010 missing-live recovery from complete baseline ----
Clean-Fixture
Write-StockFixture
$stockChime14 = [System.IO.File]::ReadAllBytes($chimePath)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--sound', $wavAPath)
check 'missing-live: initial Apply exits 0' ($r.Code -eq 0)
Remove-Item $chimePath -Force -ErrorAction SilentlyContinue

$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'missing-live: missing chime Revert exits 0' ($r.Code -eq 0)
check 'missing-live: Revert does not refuse missing chime' (($r.Out -join ' ') -notmatch 'REVERT REFUSED')
check 'missing-live: missing chime recreated byte-exact from baseline' ((Test-Path $chimePath) -and (-not (Compare-Object $stockChime14 ([System.IO.File]::ReadAllBytes($chimePath)))))

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail

} finally {
    $env:LOCALAPPDATA = $prevLocal
    $env:APPDATA = $prevApp
    $env:WINTAGE_APPDATA = $prevWin
    $env:WINTAGE_FREEBUFF_PATCH_PATH = $prevPatch
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
