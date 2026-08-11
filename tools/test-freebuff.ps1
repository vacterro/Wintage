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
    Write-Host "  1. cross-file preflight causes ZERO mutation on mismatch"
    Write-Host "  2. dry-run with a stale matcher exits nonzero"
    Write-Host "  3. one transaction backup restores all owned files; partial dirs refused"
    Write-Host "  4. install.ps1 missing FreeBuff helper hard-fails (no manifest)"
    Write-Host "  5. install.ps1 FreeBuff -WhatIf validates the ad helper"
    Write-Host "  6. top-level FreeBuff Revert restores shim + patches + sound + manifest"
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
const exports_Effect = { promise: (f) => f() };
function maybeRequestAd(threadId, impUrl) {
  const ad2 = yield* exports_Effect.promise(() => app.ads.slotAd(threadId));
  const ok2 = yield* exports_Effect.promise(() => app.ads.impression(impUrl));
  const ok2 = yield* exports_Effect.promise(() => app.ads.click(impUrl));
  if (harnessId !== "codebuff") { return ad2; }
}
"@

$BROKEN_ORCH = @"
const app = {};
const exports_Effect = { promise: (f) => f() };
function maybeRequestAd(threadId, impUrl) {
  const ad2 = yield* exports_Effect.promise(() => app.ads.slotAd(threadId));
  if (harnessId !== "codebuff") { return ad2; }
}
"@

$BUNDLE = @"
const ad = { adSlot:e=>Ie("/api/ad/slot",{threadId:e}),adImpression:e=>Ie("/api/ad/impression",{impUrl:e}),adClick:e=>Ie("/api/ad/click",{impUrl:e}) };
function render(m) { return case"ad":return b.jsx(s2,{ad:m.ad,variant:"card"}); }
function thread(i, r) { return !i||!r?null:b.jsx(s2,{ad:r,variant:"banner"}); }
"@

function New-StockWav { [byte[]]@(0x52,0x49,0x46,0x46,0x24,0,0,0,0x57,0x41,0x56,0x45,0x66,0x6D,0x74,0x20,0x10,0,0,0,1,0,1,0,0x40,0x1F,0,0,0x40,0x1F,0,0,1,0,8,0,0x64,0x61,0x74,0x61,0,0,0,0) }

function Write-StockFixture {
    # Full stock fixture: every required matcher present (happy path).
    New-Item -ItemType Directory -Path $orchestratorDir, $assetsDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $app 'Freebuff.exe'), '', $utf8)
    Build-FakeAsar (Join-Path $app 'resources\app.asar') '1.0.0'
    [System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $FULL_ORCH, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $orchestratorDir 'ui\index.html'), '<script src="assets/index-abc.js"></script>', $utf8)
    [System.IO.File]::WriteAllText($bundlePath, $BUNDLE, $utf8)
    [System.IO.File]::WriteAllBytes($chimePath, (New-StockWav))
    $env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'
}

function Write-BrokenFixture {
    # Renderer has ALL matchers, orchestrator is MISSING two -> preflight must fail
    # with ZERO mutation and NO backup transaction.
    New-Item -ItemType Directory -Path $orchestratorDir, $assetsDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $app 'Freebuff.exe'), '', $utf8)
    Build-FakeAsar (Join-Path $app 'resources\app.asar') '1.0.0'
    [System.IO.File]::WriteAllText($orchestratorDir + '\orchestrator.js', $BROKEN_ORCH, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $orchestratorDir 'ui\index.html'), '<script src="assets/index-abc.js"></script>', $utf8)
    [System.IO.File]::WriteAllText($bundlePath, $BUNDLE, $utf8)
    [System.IO.File]::WriteAllBytes($chimePath, (New-StockWav))
    $env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'
}

function Clean-Fixture {
    if (Test-Path $app) { Remove-Item $app -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path (Join-Path $app 'resources') -Force | Out-Null
    $installed = Join-Path $fakeAppData 'Wintage\installed.json'
    if (Test-Path $installed) { Remove-Item $installed -Force }
}

$prevLocal = $env:LOCALAPPDATA
$prevApp = $env:APPDATA
$prevWin = $env:WINTAGE_APPDATA
$prevPatch = $env:WINTAGE_FREEBUFF_PATCH_PATH
$env:LOCALAPPDATA = $fakeLocal
$env:APPDATA = $fakeAppData
$env:WINTAGE_APPDATA = Join-Path $fakeAppData 'Wintage'

try {

# ---- Test 1: cross-file preflight -> zero mutation on mismatch (P0#12) ----
Clean-Fixture
Write-BrokenFixture
$bundleBefore = [System.IO.File]::ReadAllBytes($bundlePath)
$orchBefore = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'))
check 'cross-file preflight mismatch exits NONZERO' ($r.Code -ne 0)
check 'preflight mismatch leaves the renderer byte-unchanged' (-not (Compare-Object $bundleBefore ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'preflight mismatch leaves the orchestrator byte-unchanged' (-not (Compare-Object $orchBefore ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js'))))
check 'preflight mismatch creates NO backup transaction' (-not (Get-ChildItem $app -Directory -Filter '_orig-backup-*' -ErrorAction SilentlyContinue))

# ---- Test 2: dry-run with a stale matcher exits nonzero (P0#11) ----
Clean-Fixture
Write-BrokenFixture
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--dry-run')
check 'dry-run stale matcher exits NONZERO' ($r.Code -ne 0)
check 'dry-run names the missing matcher' (($r.Out -join ' ') -match 'required matcher')
check 'dry-run creates NO backup transaction' (-not (Get-ChildItem $app -Directory -Filter '_orig-backup-*' -ErrorAction SilentlyContinue))

# ---- Test 3: one transaction restores all owned files; partial dirs refused (P0#13) ----
Clean-Fixture
Write-StockFixture
$bundleStock = [System.IO.File]::ReadAllBytes($bundlePath)
$orchStock = [System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js')
$chimeStock = [System.IO.File]::ReadAllBytes($chimePath)
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'))
check 'happy-path patch exits 0' ($r.Code -eq 0)
$txs = @(Get-ChildItem $app -Directory -Filter '_orig-backup-*')
check 'exactly ONE transaction dir created' ($txs.Count -eq 1)
check 'transaction carries metadata marking it complete' (Test-Path (Join-Path $txs[0].FullName 'wintage-backup.json'))
# Simulate a partial transaction (no metadata) - revert must refuse it.
$partialDir = Join-Path $app ('_orig-backup-' + [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ss') + '-999')
New-Item -ItemType Directory -Path $partialDir -Force | Out-Null
# Corrupt the owned live files (bundle + orchestrator; the sound is only owned
# when --sound is given), then revert from the complete transaction.
[System.IO.File]::WriteAllBytes($bundlePath, [byte[]]@(1,2,3,4))
[System.IO.File]::WriteAllBytes($orchestratorDir + '\orchestrator.js', [byte[]]@(5,6,7,8))
$r = Run-TestChild node @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--revert')
check 'revert from complete transaction exits 0' ($r.Code -eq 0)
check 'revert restores the renderer byte-exact' (-not (Compare-Object $bundleStock ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'revert restores the orchestrator byte-exact' (-not (Compare-Object $orchStock ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js'))))

# ---- Test 4: install.ps1 missing FreeBuff helper hard-fails, no manifest (P0#10) ----
Clean-Fixture
Write-StockFixture
$env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $testRoot 'does-not-exist.js'
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault')
check 'missing FreeBuff helper exits NONZERO' ($r.Code -ne 0)
check 'missing helper leaves NO manifest entry' (-not (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')))
$env:WINTAGE_FREEBUFF_PATCH_PATH = Join-Path $root 'desktop\patch-freebuff-ads.js'

# ---- Test 5: install.ps1 FreeBuff -WhatIf validates the ad helper (P0#11) ----
Clean-Fixture
Write-StockFixture
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault', '-WhatIf')
check 'FreeBuff WhatIf with healthy helper exits 0' ($r.Code -eq 0)
check 'FreeBuff WhatIf reports the would-install plan' (($r.Out -join ' ') -match 'What if|would|dry-run')
Write-BrokenFixture
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Palette', 'goldendefault', '-WhatIf')
check 'FreeBuff WhatIf with stale matcher exits NONZERO' ($r.Code -ne 0)
check 'FreeBuff WhatIf with stale matcher leaves files untouched' (-not (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')))

# ---- Test 6: top-level FreeBuff Revert restores shim + patches + sound + manifest (P0#9) ----
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
check 'patch applied to the bundle' (([System.IO.File]::ReadAllText($bundlePath)) -match 'adSlot:\(\)=>Promise\.resolve\(null\)')
check 'custom sound installed' (-not (Compare-Object $customWav ([System.IO.File]::ReadAllBytes($chimePath))))
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'freebuff', '-Revert')
check 'top-level FreeBuff Revert exits 0' ($r.Code -eq 0)
check 'Revert restores the stock app.asar byte-exact' (-not (Compare-Object $stockAsar ([System.IO.File]::ReadAllBytes((Join-Path $app 'resources\app.asar')))))
check 'Revert removes the Wintage app dir' (-not (Test-Path (Join-Path $app 'resources\app')))
check 'Revert restores the bundle to stock' (-not (Compare-Object $bundleStock2 ([System.IO.File]::ReadAllBytes($bundlePath))))
check 'Revert restores the orchestrator to stock' (-not (Compare-Object $orchStock2 ([System.IO.File]::ReadAllBytes($orchestratorDir + '\orchestrator.js'))))
check 'Revert restores the stock sound' (-not (Compare-Object $chimeStock2 ([System.IO.File]::ReadAllBytes($chimePath))))
$mAfter = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
check 'Revert removes the manifest entry' (-not $mAfter.freebuff)

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
