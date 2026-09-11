# SRC-006:R004 -- generic VS Code-family recovery epoch fail-closed + retire-first consumption
#
# Defect classes this fixture pins down:
#  1. CORRUPT / WRONG / UNKNOWN / INCOMPLETE recovery.json must fail CLOSED:
#     nonzero exit, zero live mutation, zero manifest mutation, evidence kept.
#  2. Replaced-mode Revert must restore the pre-Wintage tree BYTE-EXACTLY from
#     the retired epoch (SRC-006:R004: the retirement rename moves pristine
#     with the epoch, so reads after retirement must go through the tombstone).
#  3. A failed manifest transition after retirement must restore BOTH the live
#     destination AND the epoch back to its active path (retry stays possible).
#  4. Two full cycles: the second Revert restores the SECOND baseline (B), and
#     no first-cycle (A) data may resurrect.
#  5. An empty pristine is a LEGITIMATE replaced-mode state (the user's
#     wintage-themes directory was empty before Wintage): Revert restores an
#     empty directory. Fail-closed is for missing/incomplete AUTHORITY, not
#     for empty user directories the format cannot distinguish.
#
# Instrument/red notes:
#  - Every fixture uses WINTAGE_APPDATA / HOME / USERPROFILE isolation so the
#    live profile is untouched; the backup root is isolated too.
#  - The retire+commit failure control sets WINTAGE_TEST_FAIL_MANIFEST_MOVE,
#    which makes Write-Manifest throw AFTER the destination was mutated and
#    the epoch retired -- the exact seam the rollback contract protects.
#  - Red control: run this fixture with -InstallerPath pointing at a copy of
#    install.ps1 whose replaced-mode branch still reads the pristine from the
#    ACTIVE path after retirement (the pre-R004 behavior). Fixtures B/C/H
#    FAIL against that copy (the copy cannot restore the destination) and
#    PASS against the real installer.

[CmdletBinding()]
param(
    [switch]$List,
    [string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = if ($InstallerPath) { $InstallerPath } else { Join-Path $root 'desktop\install.ps1' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function Same-Bytes([string]$path, [byte[]]$exp) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $got = [System.IO.File]::ReadAllBytes($path)
    if ($got.Length -ne $exp.Length) { return $false }
    for ($i = 0; $i -lt $got.Length; $i++) { if ($got[$i] -ne $exp[$i]) { return $false } }
    return $true
}

function Run-Child([string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}

# Tree equality is BYTE IDENTITY, not relative membership: same relative files,
# same lengths, same SHA-256 content. A destination whose filenames survived
# but whose bytes changed must FAIL this assertion.
function Get-TreeManifest([string]$treeRoot) {
    if (-not (Test-Path -LiteralPath $treeRoot)) { return $null }
    $m = @{}
    Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($treeRoot.Length).TrimStart('\', '/').ToLowerInvariant()
        $sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($_.FullName))).Replace('-', '')
        $m[$rel] = "$($_.Length):$sha"
    }
    return $m
}

function Same-Tree([string]$a, [string]$b) {
    $ma = Get-TreeManifest $a
    $mb = Get-TreeManifest $b
    if (($null -eq $ma) -or ($null -eq $mb)) { return (($null -eq $ma) -and ($null -eq $mb)) }
    if ($ma.Count -ne $mb.Count) { return $false }
    foreach ($k in $ma.Keys) {
        if (-not $mb.ContainsKey($k)) { return $false }
        if ($mb[$k] -ne $ma[$k]) { return $false }
    }
    return $true
}

function Snapshot-Tree([string]$src, [string]$dst) {
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force }
}

function Read-ManifestText([string]$appData) {
    $p = Join-Path $appData 'installed.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return [System.IO.File]::ReadAllText($p, $utf8)
}

if ($List) {
    Write-Host "test-vscode-recovery.ps1 (9 fixtures):"
    Write-Host "  A. created mode: Apply -> Revert removes dest, consumes epoch, no tombstone"
    Write-Host "  B. replaced mode: existing tree A -> Apply -> Revert restores A byte-exactly"
    Write-Host "  C. two cycles: A->Apply->Revert, user makes B, B->Apply->Revert == B (no A data)"
    Write-Host "  D. unknown mode fail-closed"
    Write-Host "  E. malformed / wrong-shape JSON fail-closed"
    Write-Host "  F. wrong target fail-closed"
    Write-Host "  G. replaced + missing pristine fail-closed"
    Write-Host "  H. retire + manifest commit failure rolls back dest AND epoch; retry succeeds"
    Write-Host "  I. empty pristine (legit empty user dir) restores to an empty directory"
    exit 0
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-vscode-rec-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$prevHome = $env:HOME
$prevUserProfile = $env:USERPROFILE
$prevAppData = $env:WINTAGE_APPDATA
$prevBakRoot = $env:WINTAGE_BACKUP_ROOT
$prevFailMove = $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE

try {

function New-VscodeHome([string]$tag) {
    $hDir = Join-Path $testRoot "home-$tag"
    $ext = Join-Path $hDir '.vscode\extensions'
    $dest = Join-Path $ext 'wintage-themes'
    $appData = Join-Path $testRoot "appdata-$tag"
    New-Item -ItemType Directory -Path $ext, $appData -Force | Out-Null
    return @{ Home = $hDir; AppData = $appData; ExtDir = $ext; Dest = $dest; RecDir = (Join-Path $appData "recovery\vscode"); RecMeta = (Join-Path $appData "recovery\vscode\recovery.json"); Pristine = (Join-Path $appData "recovery\vscode\pristine") }
}

function Set-Home([hashtable]$ctx, [string]$backupTag) {
    $env:HOME = $ctx.Home
    $env:USERPROFILE = $ctx.Home
    $env:WINTAGE_APPDATA = $ctx.AppData
    $env:WINTAGE_BACKUP_ROOT = Join-Path $testRoot "backup-$backupTag"
}

# ---- A. CREATED MODE: Apply -> Revert removes dest, consumes epoch ----
$ctxA = New-VscodeHome 'created-ok'
$env:HOME = $ctxA.Home; $env:USERPROFILE = $ctxA.Home; $env:WINTAGE_APPDATA = $ctxA.AppData; $env:WINTAGE_BACKUP_ROOT = Join-Path $testRoot 'backup-A'
$r = Run-Child @('-Target', 'vscode', '-Palette', 'goldendefault')
check 'r004-A created: apply exits 0' ($r.Code -eq 0)
check 'r004-A created: recovery mode created recorded' ((Test-Path $ctxA.RecMeta) -and ((Get-Content $ctxA.RecMeta -Raw | ConvertFrom-Json).mode -eq 'created'))
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-A created: revert exits 0' ($r.Code -eq 0)
check 'r004-A created: dest removed' (-not (Test-Path $ctxA.Dest))
check 'r004-A created: manifest entry removed' (-not ((Read-ManifestText $ctxA.AppData | ConvertFrom-Json).vscode))
check 'r004-A created: recovery epoch consumed' (-not (Test-Path $ctxA.RecMeta))
check 'r004-A created: no retired tombstone leaks' (-not @(Get-ChildItem (Join-Path $ctxA.AppData 'recovery') -Filter '*wintage-retired*' -Force -ErrorAction SilentlyContinue).Count)

# ---- B. REPLACED MODE byte-exact + C. TWO CYCLES ----
$ctxB = New-VscodeHome 'twocycle'
Set-Home $ctxB 'B'
# Tree A: stock + a-only file
New-Item -ItemType Directory -Path (Join-Path $ctxB.Dest 'themes') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ctxB.Dest 'themes\a-only.json'), '{"a":1}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $ctxB.Dest 'themes\stock.json'), '{"s":1}', $utf8)
$snapA = Join-Path $testRoot 'snap-A'; Snapshot-Tree $ctxB.Dest $snapA
$r = Run-Child @('-Target', 'vscode', '-Palette', 'goldendefault')
check 'r004-B replaced: first Apply exits 0' ($r.Code -eq 0)
check 'r004-B replaced: mode replaced recorded' (((Get-Content $ctxB.RecMeta -Raw | ConvertFrom-Json).mode -eq 'replaced'))
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-B replaced: first Revert exits 0' ($r.Code -eq 0)
check 'r004-B replaced: A restored BYTE-EXACTLY from the retired epoch' (Same-Tree $ctxB.Dest $snapA)
check 'r004-B replaced: active recovery epoch consumed' (-not (Test-Path $ctxB.RecMeta))
check 'r004-B replaced: no tombstone leak' (-not @(Get-ChildItem (Join-Path $ctxB.AppData 'recovery') -Filter '*wintage-retired*' -Force -ErrorAction SilentlyContinue).Count)
# User changes tree to B: remove a-only, add b-only, change stock
Remove-Item (Join-Path $ctxB.Dest 'themes\a-only.json') -Force
[System.IO.File]::WriteAllText((Join-Path $ctxB.Dest 'themes\b-only.json'), '{"b":2}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $ctxB.Dest 'themes\stock.json'), '{"s":9}', $utf8)
$snapB = Join-Path $testRoot 'snap-B'; Snapshot-Tree $ctxB.Dest $snapB
$r = Run-Child @('-Target', 'vscode', '-Palette', 'goldendefault')
check 'r004-C twocycle: second Apply exits 0' ($r.Code -eq 0)
check 'r004-C twocycle: second recovery is fresh (mode replaced)' (((Get-Content $ctxB.RecMeta -Raw | ConvertFrom-Json).mode -eq 'replaced'))
$sameB = Same-Bytes (Join-Path $ctxB.Pristine 'themes\b-only.json') ([System.IO.File]::ReadAllBytes((Join-Path $snapB 'themes\b-only.json')))
check 'r004-C twocycle: second pristine captures B not A' $sameB
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-C twocycle: second Revert exits 0' ($r.Code -eq 0)
check 'r004-C twocycle: B restored BYTE-EXACTLY (Same-Tree)' (Same-Tree $ctxB.Dest $snapB)
check 'r004-C twocycle: A not resurrected' (-not (Test-Path (Join-Path $ctxB.Dest 'themes\a-only.json')))
check 'r004-C twocycle: second epoch consumed' (-not (Test-Path $ctxB.RecMeta))

# Shared fail-closed fixture scaffold: build a healthy replaced-mode install,
# snapshot dest + manifest, then corrupt one aspect and demand zero mutation.
function New-FailClosedFixture([string]$tag) {
    $ctx = New-VscodeHome $tag
    Set-Home $ctx $tag
    New-Item -ItemType Directory -Path (Join-Path $ctx.Dest 'themes') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $ctx.Dest 'themes\stock.json'), '{"k":"keep"}', $utf8)
    $null = Run-Child @('-Target', 'vscode', '-Palette', 'goldendefault')
    $snap = Join-Path $testRoot "snap-$tag"; Snapshot-Tree $ctx.Dest $snap
    $manifest = Read-ManifestText $ctx.AppData
    return @{ Ctx = $ctx; Snap = $snap; Manifest = $manifest }
}

# ---- D. UNKNOWN MODE fail-closed ----
$fD = New-FailClosedFixture 'unknown-mode'
$metaD = Get-Content $fD.Ctx.RecMeta -Raw | ConvertFrom-Json
$metaD.mode = 'garbage'
[System.IO.File]::WriteAllText($fD.Ctx.RecMeta, ($metaD | ConvertTo-Json), $utf8)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-D unknown: revert exits NONZERO' ($r.Code -ne 0)
check 'r004-D unknown: dest byte-identical' (Same-Tree $fD.Ctx.Dest $fD.Snap)
check 'r004-D unknown: manifest byte-identical' ((Read-ManifestText $fD.Ctx.AppData) -eq $fD.Manifest)
check 'r004-D unknown: recovery evidence retained' (Test-Path $fD.Ctx.RecMeta)

# ---- E. MALFORMED / WRONG-SHAPE JSON fail-closed ----
$fE = New-FailClosedFixture 'malformed'
[System.IO.File]::WriteAllText($fE.Ctx.RecMeta, '{ this is not json', $utf8)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-E malformed: revert exits NONZERO' ($r.Code -ne 0)
check 'r004-E malformed: dest byte-identical' (Same-Tree $fE.Ctx.Dest $fE.Snap)
check 'r004-E malformed: manifest byte-identical' ((Read-ManifestText $fE.Ctx.AppData) -eq $fE.Manifest)
check 'r004-E malformed: recovery retained' (Test-Path $fE.Ctx.RecMeta)
[System.IO.File]::WriteAllText($fE.Ctx.RecMeta, '[]', $utf8)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-E shape: array recovery exits NONZERO' ($r.Code -ne 0)
check 'r004-E shape: dest still byte-identical' (Same-Tree $fE.Ctx.Dest $fE.Snap)
[System.IO.File]::WriteAllText($fE.Ctx.RecMeta, '"hello"', $utf8)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-E shape: scalar recovery exits NONZERO' ($r.Code -ne 0)
check 'r004-E shape: manifest still byte-identical' ((Read-ManifestText $fE.Ctx.AppData) -eq $fE.Manifest)

# ---- F. WRONG TARGET fail-closed ----
$fF = New-FailClosedFixture 'wrong-target'
$metaF = Get-Content $fF.Ctx.RecMeta -Raw | ConvertFrom-Json
$metaF.target = 'not-vscode'
[System.IO.File]::WriteAllText($fF.Ctx.RecMeta, ($metaF | ConvertTo-Json), $utf8)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-F wrongtarget: revert exits NONZERO' ($r.Code -ne 0)
check 'r004-F wrongtarget: dest byte-identical' (Same-Tree $fF.Ctx.Dest $fF.Snap)
check 'r004-F wrongtarget: manifest byte-identical' ((Read-ManifestText $fF.Ctx.AppData) -eq $fF.Manifest)
check 'r004-F wrongtarget: recovery retained' (Test-Path $fF.Ctx.RecMeta)

# ---- G. REPLACED + MISSING PRISTINE fail-closed ----
$fG = New-FailClosedFixture 'missing-pristine'
Remove-Item $fG.Ctx.Pristine -Recurse -Force
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-G mpristine: revert exits NONZERO' ($r.Code -ne 0)
check 'r004-G mpristine: dest byte-identical' (Same-Tree $fG.Ctx.Dest $fG.Snap)
check 'r004-G mpristine: manifest byte-identical' ((Read-ManifestText $fG.Ctx.AppData) -eq $fG.Manifest)
check 'r004-G mpristine: recovery.json retained at the ACTIVE path' (Test-Path $fG.Ctx.RecMeta)
check 'r004-G mpristine: no tombstone leak before retirement' (-not @(Get-ChildItem (Join-Path $fG.Ctx.AppData 'recovery') -Filter '*wintage-retired*' -Force -ErrorAction SilentlyContinue).Count)

# ---- H. RETIRE + MANIFEST COMMIT FAILURE: rollback restores both ----
$fH = New-FailClosedFixture 'retire-commit-fail'
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
$r = Run-Child @('-Target', 'vscode', '-Revert')
$env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFailMove
check 'r004-H retire: failing revert exits NONZERO' ($r.Code -ne 0)
check 'r004-H retire: dest byte-identical pre-operation state' (Same-Tree $fH.Ctx.Dest $fH.Snap)
check 'r004-H retire: manifest byte-identical after failed commit' ((Read-ManifestText $fH.Ctx.AppData) -eq $fH.Manifest)
check 'r004-H retire: active recovery epoch restored (retry possible)' (Test-Path $fH.Ctx.RecMeta)
check 'r004-H retire: no tombstone leak' (-not @(Get-ChildItem (Join-Path $fH.Ctx.AppData 'recovery') -Filter '*wintage-retired*' -Force -ErrorAction SilentlyContinue).Count)
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-H retire: retry revert exits 0' ($r.Code -eq 0)
check 'r004-H retire: retry consumed epoch' (-not (Test-Path $fH.Ctx.RecMeta))

# ---- I. EMPTY PRISTINE is a VALID replaced-mode state ----
$fI = New-FailClosedFixture 'empty-pristine'
Get-ChildItem -LiteralPath $fI.Ctx.Pristine -Force | Remove-Item -Recurse -Force
$r = Run-Child @('-Target', 'vscode', '-Revert')
check 'r004-I emptyprist: revert exits 0' ($r.Code -eq 0)
check 'r004-I emptyprist: dest restored as an EMPTY directory' ((Test-Path $fI.Ctx.Dest) -and (-not @(Get-ChildItem -LiteralPath $fI.Ctx.Dest -Recurse -Force -ErrorAction SilentlyContinue).Count))
check 'r004-I emptyprist: manifest entry removed' (-not ((Read-ManifestText $fI.Ctx.AppData | ConvertFrom-Json).vscode))
check 'r004-I emptyprist: epoch consumed' (-not (Test-Path $fI.Ctx.RecMeta))

# ---- Structural guard: recovery-present branch must not delete before validation ----
$installerText = Get-Content $installer -Raw
check 'r004-J structural: no bare Remove-Item dest in recovery-present branch without validation' (
    -not ($installerText -match 'if \(Test-Path \$recoveryMeta\)\s*\{[^}]*Remove-Item \$dest -Recurse -Force(?!\s*\}.*Invoke-TargetCommit)')
)
check 'r004-J structural: replaced-mode restore reads the pristine from the TOMBSTONE' (
    $installerText -match '\$retiredPristine = Join-Path \$recoveryTombstone ''pristine'''
)

} finally {
    $env:HOME = $prevHome
    $env:USERPROFILE = $prevUserProfile
    $env:WINTAGE_APPDATA = $prevAppData
    $env:WINTAGE_BACKUP_ROOT = $prevBakRoot
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = $prevFailMove
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
