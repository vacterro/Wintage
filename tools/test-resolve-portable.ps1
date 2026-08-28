# Resolve-PortableElectron manifest-path semantic regression suite (T-207 / CORE-009).
#
# The audit caught that the resolver appended 'resources' to EVERY candidate,
# including the manifest-recorded path -- but the installer records
# `$e.Resources` (the resources directory itself) into the manifest. Appending
# another 'resources' to an already-resources path tests `<resources>\resources`,
# which never exists, so a Reapply against a moved target fails to rediscover
# the installation it just recorded and may fall through to a different
# installation or report it missing.
#
# The fix: explicit / remembered / process / default candidates are APP ROOTS
# and need 'resources' appended; the manifest-recorded candidate is ALREADY the
# resources directory and must be used as-is. This test enforces the new
# semantic and confirms the precedence chain (explicit > remembered > manifest
# > process/default) still works for every candidate type.
#
#   .\tools\test-resolve-portable.ps1          # all tests
#   .\tools\test-resolve-portable.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$common = Join-Path $here '..\desktop\modules\common.ps1'
$install = Join-Path $here '..\desktop\install.ps1'
$pass = 0; $fail = 0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-resolve-portable.ps1 (5 tests):"
    Write-Host "  1. resolver does NOT append 'resources' to the manifest-recorded path"
    Write-Host "  2. resolver still appends 'resources' to the explicit / remembered / process paths"
    Write-Host "  3. manifest-recorded resources path is returned when no other candidate resolves"
    Write-Host "  4. manifest path uses the recorded value byte-exact (no Join-Path rewrite)"
    Write-Host "  5. install.ps1 Set-ManifestEntry contract: records $e.Resources, not the app root"
    exit 0
}

# ---- Test 1 + 2: source-level structural check ----
# The fix is a single function (Resolve-PortableElectron). We assert that
# the manifest branch of the function uses the manifest path as-is, while
# the explicit / remembered / process branches still append 'resources'.
$src = Get-Content $common -Raw
$resolverStart = $src.IndexOf('function Resolve-PortableElectron')
$resolverEnd   = $src.IndexOf("`nfunction", $resolverStart + 1)
if ($resolverEnd -lt 0) { $resolverEnd = $src.Length }
$resolverBlock = $src.Substring($resolverStart, $resolverEnd - $resolverStart)

# Find each Join-Path-with-'resources' line and the manifest branch.
# The manifest branch should NOT carry another Join-Path.
$manifestBranch = $resolverBlock.IndexOf('$manifest[$key].path')
$postManifest = $resolverBlock.Substring($manifestBranch, [Math]::Min(220, $resolverBlock.Length - $manifestBranch))
check 'manifest branch: NO Join-Path appending resources to $manifest path' ($postManifest -notmatch "Join-Path.*'resources'")

# The explicit + remembered + process branches MUST still append 'resources'.
$explicitHasResources = $resolverBlock -match "Join-Path \`$explicitPath 'resources'"
$rememberedHasResources = $resolverBlock -match "Join-Path \`$remembered\[\`$key\] 'resources'"
$processHasResources = $resolverBlock -match "Join-Path \(Split-Path \`$proc.Path -Parent\) 'resources'"
check 'explicit branch: still appends resources to the app root' ([bool]$explicitHasResources)
check 'remembered branch: still appends resources to the app root' ([bool]$rememberedHasResources)
check 'process branch: still appends resources to the app root' ([bool]$processHasResources)

# ---- Test 3 + 4: behavioural check via a synthetic Electron app layout ----
# Layout:
#   <root>/explicit/resources/        -> app.asar (works)
#   <root>/manifest/resources/        -> app.asar (works)
#   <root>/manifest/resources/resources/  -> DOES NOT EXIST (the audit's bug)
#
# We dot-source common.ps1 (with the script-scope UTF8 encodings and a
# WintageAppData env seam) and a minimal Test-ElectronApp stub, then call
# Resolve-PortableElectron and assert it returns the manifest resources
# directory byte-exact, not a Join-Path-rewritten path.

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-resolve-portable-" + [guid]::NewGuid().ToString('N'))
$appData = Join-Path $testRoot 'appdata'
$explicitRoot = Join-Path $testRoot 'explicit'
$manifestRoot = Join-Path $testRoot 'manifest'
$explicitRes = Join-Path $explicitRoot 'resources'
$manifestRes = Join-Path $manifestRoot 'resources'
New-Item -ItemType Directory -Path $appData, $explicitRes, $manifestRes -Force | Out-Null
# A minimal "Electron app" is recognised by the resolver's Test-ElectronApp
# stub: the presence of a `resources/app.asar` (and any package.json).
'{"name":"fake","main":"app.asar"}' | Set-Content (Join-Path $manifestRes 'package.json')
'' | Set-Content (Join-Path $manifestRes 'app.asar')
'' | Set-Content (Join-Path $explicitRes 'package.json')
'' | Set-Content (Join-Path $explicitRes 'app.asar')

# Seed a manifest with a recorded resources path (what Set-ManifestEntry writes).
$manifestPath = Join-Path $appData 'installed.json'
$manifestObj = @{ codenomad = @{ path = $manifestRes; palette = 'goldendefault' } }
[System.IO.File]::WriteAllText($manifestPath, ($manifestObj | ConvertTo-Json -Depth 4), $script:Utf8NoBom)

# Dot-source common.ps1 after setting the env seam so Read-Manifest resolves
# to our test fixture.
$env:WINTAGE_APPDATA = $appData
. $common
# Stub Test-ElectronApp: a directory is an Electron app iff it contains
# both package.json and app.asar. The real one uses node helpers; we
# inline a pure-PS stub for this test.
function Test-ElectronApp([string]$dir) {
    if (-not $dir -or -not (Test-Path $dir)) { return $false }
    $p = Join-Path $dir 'package.json'
    $a = Join-Path $dir 'app.asar'
    return ((Test-Path $p) -and (Test-Path $a))
}

# Pass 1: NO explicit, NO remembered, no running process. The resolver MUST
# fall back to the manifest-recorded path -- and that path is ALREADY
# `<root>/manifest/resources`. The pre-fix code would have appended another
# 'resources' and returned `<root>/manifest/resources/resources`, which does
# not exist. With the fix, the resolver returns the recorded value byte-exact.
$got = Resolve-PortableElectron 'codenomad' $null @{} 'CodeNomad' @()
check 'manifest path: resolver returns the recorded resources path, not <resources>/resources' (
    $got -eq $manifestRes)
check 'manifest path: returned value is byte-exact (no Join-Path rewrite)' (
    $got -and ($got -replace '\\', '/') -eq ($manifestRes -replace '\\', '/'))
check 'manifest path: returned value ends in /resources (NOT /resources/resources)' (
    $got -and $got.EndsWith('\resources') -and -not $got.EndsWith('\resources\resources'))

# Pass 2: explicit override wins over the manifest. The explicit path is an
# app root, so the resolver appends 'resources' to it.
$got2 = Resolve-PortableElectron 'codenomad' $explicitRoot @{} 'CodeNomad' @()
check 'precedence: explicit override resolves before the manifest' (
    $got2 -eq $explicitRes)

# Pass 3: remembered paths.json wins over the manifest.
$got3 = Resolve-PortableElectron 'codenomad' $null @{ codenomad = $explicitRoot } 'CodeNomad' @()
check 'precedence: remembered paths.json resolves before the manifest' (
    $got3 -eq $explicitRes)

# Cleanup
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
$env:WINTAGE_APPDATA = $null

# ---- Test 5: install.ps1 Set-ManifestEntry contract ----
# The audit's REPAIR clause says: "treat manifest `path` as the
# already-resolved resources directory". That contract lives in install.ps1
# where the manifest entry is written. Assert the recording site still writes
# $e.Resources (i.e., the resources path), NOT the app root.
$installSrc = Get-Content $install -Raw
# The Electron target commit records the manifest with `$e.Resources` (T-196
# for WorkBuddy; same shape for the other Electron targets).
$recordingSite = $installSrc -match 'Set-ManifestEntry\s+\$name\s+\$Palette\s+\$e\.Resources'
check 'install.ps1: Set-ManifestEntry records $e.Resources (the resources dir, not the app root)' ([bool]$recordingSite)
# Defensive: the literal string 'resources' must NOT appear as a Join-Path
# operand next to the manifest path, anywhere in the resolver.
$violations = [regex]::Matches($resolverBlock, "Join-Path\s+\(\s*\[string\]\s*\`$manifest\[\`$key\]\.path")
check 'install.ps1: no Join-Path appending resources to the manifest path' ($violations.Count -eq 0)

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
