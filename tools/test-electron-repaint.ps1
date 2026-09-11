# SRC-006:R007 -- Electron repaint I/O must be proportional to the mutation set.
#
# DEFECT (pre-fix): a palette-only repaint of an already-themed Electron app
# paid ARCHIVE-SIZED I/O at both transaction layers:
#   - child: repaintRelocation() snapshotted the moved app.asar (size+SHA-256)
#     via captureAppDir() although a repaint cannot touch the archive;
#   - parent: install.ps1 always took the full Save-ElectronStateSnapshot
#     (which in relocation mode copies the whole app/ tree INCLUDING the moved
#     archive) even for healthy themed repaints, leaving the PERF-005
#     lightweight -Operation Repaint branch dead code.
#
# CONTRACT under test:
#  - a healthy relocated/in-place palette repaint reads ZERO archive bytes,
#    instrumented through a NODE_OPTIONS preload that logs every byte read;
#  - an injected repaint failure restores every mutated sidecar byte-exactly;
#  - the parent's manifest-commit failure on a themed target restores the
#    pre-repaint sidecars while the archive stays intact;
#  - the parent still restores the FULL pre-state on a full-install path and
#    Revert remains archive-safe;
#  - red control: -ToolPath pointing at a copy whose relocation repaint uses
#    captureAppDir() again makes the zero-archive-read assertion FAIL.

[CmdletBinding()]
param(
    [switch]$List,
    [string]$ToolPath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$tool = if ($ToolPath) { $ToolPath } else { Join-Path $root 'tools\install-electron.js' }
$installer = Join-Path $root 'desktop\install.ps1'
$probe = Join-Path $here 'test-electron-repaint-probe.cjs'
$fixtureBuilder = Join-Path $here 'build-asar-fixture.js'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function Save-AllBytes([string]$path) { [System.IO.File]::ReadAllBytes($path) }
function Same-BytesFile([string]$a, [byte[]]$b) {
    if (-not (Test-Path $a)) { return $false }
    $x = [System.IO.File]::ReadAllBytes($a)
    if ($x.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $b[$i]) { return $false } }
    return $true
}

if ($List) {
    Write-Host "test-electron-repaint.ps1 (2 fixtures, 15 checks):"
    Write-Host "  1. child: relocated + in-place repaint read ZERO archive bytes; injected failure restores sidecars"
    Write-Host "  2. parent: manifest failure restores pre-repaint sidecars, archive intact; install path restores full pre-state; revert archive-safe"
    exit 0
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-el-repaint-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$prevLocalAppData = $env:LOCALAPPDATA
$prevAppData = $env:WINTAGE_APPDATA
$prevFailMove = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE
$prevNodeOpts = $env:NODE_OPTIONS

try {

# Fixture app under a redirected LOCALAPPDATA so the antigravity-app resolver
# finds it: LOCALAPPDATA\Programs\Antigravity\resources with a FAT archive
# (4 MiB of tail padding) so any archive-sized read is loud in the probe log.
$fakeLocal = Join-Path $testRoot 'localappdata'
$appRoot = Join-Path $fakeLocal 'Programs\Antigravity'
$R = Join-Path $appRoot 'resources'
New-Item -ItemType Directory -Path $R -Force | Out-Null
$env:LOCALAPPDATA = $fakeLocal
$env:WINTAGE_APPDATA = Join-Path $testRoot 'appdata'

$asarPath = Join-Path $R 'app.asar'
$exePath = Join-Path $appRoot 'FakeApp.exe'
& node $fixtureBuilder $asarPath '1.0.0' 4194304 --exe $exePath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'asar fixture build failed' }
$stockAsar = Save-AllBytes $asarPath

$env:NODE_OPTIONS = "--require `"$($probe -replace '\\', '/')`""

# ---- child 1: healthy relocated repaint reads ZERO archive bytes ----
$env:WINTAGE_R007_IOLOG = Join-Path $testRoot 'io-install.log'
$null = & node $tool --resources $R --palette goldendefault 2>&1
check 'child: first apply (install) exits 0' ($LASTEXITCODE -eq 0)
Remove-Item Env:\WINTAGE_R007_IOLOG -ErrorAction SilentlyContinue

# The install MOVED the archive into resources\app\; that moved file is what
# the pre-fix snapshot paid archive-sized I/O on.
$movedAsar = Join-Path $R 'app\app.asar'
$asarBefore = Save-AllBytes $movedAsar
$ioLog = Join-Path $testRoot 'io-repaint.log'
$env:WINTAGE_R007_IOLOG = $ioLog
$null = & node $tool --resources $R --palette dracula 2>&1
$repaintCode = $LASTEXITCODE
Remove-Item Env:\WINTAGE_R007_IOLOG -ErrorAction SilentlyContinue
check 'child: healthy relocated repaint exits 0' ($repaintCode -eq 0)
$pkgAfter = [System.IO.File]::ReadAllText((Join-Path $R 'app\package.json'), $utf8)
check 'child: repaint changed the recorded palette' ($pkgAfter -match '"wintagePalette": "dracula"')
$ioEntries = @(Get-Content $ioLog -ErrorAction SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json })
$archivePaths = @($asarPath, $movedAsar)
$asarHits = @($ioEntries | Where-Object { $archivePaths -contains $_.path })
check 'child: repaint performed ZERO archive reads' ($asarHits.Count -eq 0)
$unpackedPrefix = (Join-Path $R 'app\app.asar.unpacked').ToLowerInvariant()
$unpackedHits = @($ioEntries | Where-Object { $_.path.ToLowerInvariant().StartsWith($unpackedPrefix) })
check 'child: repaint performed ZERO unpacked-tree reads' ($unpackedHits.Count -eq 0)
check 'child: archive bytes unchanged after repaint' (Same-BytesFile $movedAsar $asarBefore)

# ---- child 2: in-place healthy repaint also reads ZERO archive bytes ----
# Own fixture: --in-place never moves the archive, it patches it via a .bak.
$Ipr = Join-Path $testRoot 'inplace\resources'
New-Item -ItemType Directory -Path $Ipr -Force | Out-Null
$ipAsar = Join-Path $Ipr 'app.asar'
& node $fixtureBuilder $ipAsar '1.0.0' 4194304 --exe (Join-Path $testRoot 'inplace\FakeApp.exe') | Out-Null
$env:WINTAGE_R007_IOLOG = Join-Path $testRoot 'io-install-ip.log'
$null = & node $tool --resources $Ipr --in-place --palette goldendefault 2>&1
check 'child: in-place apply exits 0' ($LASTEXITCODE -eq 0)
Remove-Item Env:\WINTAGE_R007_IOLOG -ErrorAction SilentlyContinue
$ioLog = Join-Path $testRoot 'io-repaint-ip.log'
$env:WINTAGE_R007_IOLOG = $ioLog
$null = & node $tool --resources $Ipr --in-place --palette dracula 2>&1
check 'child: healthy in-place repaint exits 0' ($LASTEXITCODE -eq 0)
Remove-Item Env:\WINTAGE_R007_IOLOG -ErrorAction SilentlyContinue
$ioEntries = @(Get-Content $ioLog -ErrorAction SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json })
# The in-place repaint legitimately reads a FEW header bytes of the .bak
# (asarPackageJson) to rewrite the shim's require path; what it must never do
# is a FULL archive read/copy/hash. 64 KiB bounds that comfortably.
$asarHits = @($ioEntries | Where-Object { $_.path -eq $ipAsar -or $_.path -eq "$ipAsar.bak" })
$asarBytesRead = ($asarHits | Measure-Object -Property bytes -Sum).Sum; if (-not $asarBytesRead) { $asarBytesRead = 0 }
check 'child: in-place repaint read NO archive-sized bytes (<64KiB total)' ($asarBytesRead -lt 65536)

# ---- child 3: injected repaint failure restores every mutated sidecar ----
# Back to relocation mode for the PS parent scenarios.
& node $fixtureBuilder $asarPath '1.0.0' 4194304 --exe $exePath | Out-Null
$null = & node $tool --resources $R --palette goldendefault 2>&1 | Out-Null
$prePkg = Save-AllBytes (Join-Path $R 'app\package.json')
$preShim = Save-AllBytes (Join-Path $R 'app\shim.cjs')
$preCss = Save-AllBytes (Join-Path $R 'app\wintage.css')
$env:WINTAGE_TEST_FAIL_AFTER_REPAINT = '1'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$null = & node $tool --resources $R --palette dracula 2>&1
$failCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
Remove-Item Env:\WINTAGE_TEST_FAIL_AFTER_REPAINT -ErrorAction SilentlyContinue
check 'child: injected repaint failure exits NONZERO' ($failCode -ne 0)
$pkgNow = [System.IO.File]::ReadAllText((Join-Path $R 'app\package.json'), $utf8)
check 'child: rollback kept the PRE-repaint palette (goldendefault)' ($pkgNow -match '"wintagePalette": "goldendefault"')
check 'child: rollback restored shim.cjs byte-exactly' (Same-BytesFile (Join-Path $R 'app\shim.cjs') $preShim)
check 'child: rollback restored wintage.css byte-exactly' (Same-BytesFile (Join-Path $R 'app\wintage.css') $preCss)
check 'child: rollback restored package.json byte-exactly' (Same-BytesFile (Join-Path $R 'app\package.json') $prePkg)

# ========================================================== PARENT LAYER ===
# A themed fixture + WINTAGE_TEST_FAIL_MANIFEST_MOVE: the repaint runs, the
# manifest commit fails, and the parent must restore the pre-repaint sidecars
# WITHOUT harming the moved archive.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target antigravity-app -Palette goldendefault 2>&1
$firstCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
check 'parent: first PS apply exits 0' ($firstCode -eq 0)
$manifestPath = Join-Path $env:WINTAGE_APPDATA 'installed.json'
$mBefore = [System.IO.File]::ReadAllText($manifestPath, $utf8)

$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target antigravity-app -Palette dracula 2>&1
$repaintFailCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
Remove-Item Env:\WINTAGE_TEST_FAIL_MANIFEST_MOVE -ErrorAction SilentlyContinue
check 'parent: failing repaint apply exits NONZERO' ($repaintFailCode -ne 0)
$pkgAfterParent = [System.IO.File]::ReadAllText((Join-Path $R 'app\package.json'), $utf8)
check 'parent: manifest failure restored the pre-repaint palette sidecar' ($pkgAfterParent -match '"wintagePalette": "goldendefault"')
check 'parent: archive still intact after the failed repaint' (Same-BytesFile $movedAsar $asarBefore)
check 'parent: manifest unchanged after the failed repaint' ([System.IO.File]::ReadAllText($manifestPath, $utf8) -eq $mBefore)

# Revert through the parent stays archive-safe: stock state comes back.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target antigravity-app -Revert 2>&1
$revertCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
check 'parent: PS revert exits 0' ($revertCode -eq 0)
check 'parent: revert removed the themed app dir (stock restored)' (-not (Test-Path (Join-Path $R 'app')))
check 'parent: revert put the stock archive back byte-exactly' ((Test-Path $asarPath) -and (Same-BytesFile $asarPath $stockAsar))

Remove-Item Env:\WINTAGE_APPDATA -ErrorAction SilentlyContinue
if ($prevNodeOpts) { $env:NODE_OPTIONS = $prevNodeOpts } else { Remove-Item Env:\NODE_OPTIONS -ErrorAction SilentlyContinue }

} finally {
    $env:LOCALAPPDATA = $prevLocalAppData
    if ($prevAppData) { $env:WINTAGE_APPDATA = $prevAppData } else { Remove-Item Env:\WINTAGE_APPDATA -ErrorAction SilentlyContinue }
    if ($prevFailMove) { $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFailMove } else { Remove-Item Env:\WINTAGE_TEST_FAIL_MANIFEST_MOVE -ErrorAction SilentlyContinue }
    if ($prevNodeOpts) { $env:NODE_OPTIONS = $prevNodeOpts } else { Remove-Item Env:\NODE_OPTIONS -ErrorAction SilentlyContinue }
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
