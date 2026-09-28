# W2-001 (SRC-014) first-touch ownership / recovery regression suite.
#
# Notepad++ and Cinema 4D used to treat an EPHEMERAL rollback snapshot as if it
# were persistent ownership evidence:
#   - Notepad++ snapshotted only Wintage.xml + the marker, overwrote every
#     generated Wintage-<pack>.xml alias, and Revert wildcard-deleted every
#     matching file - including pre-existing/user files it never owned.
#   - Cinema 4D Revert recursively deleted schemes\Wintage regardless of whether
#     Wintage created it or replaced a pre-existing directory.
#   - Both wrote their persistent recovery.json only AFTER the live mutation and
#     the manifest commit, so a crash there left an applied target with no undo.
#
# This gate drives the REAL install.ps1 against isolated fixtures and asserts
# byte-exact behaviour through Apply -> repaint -> Revert, plus deterministic
# failure injection at every recovery/transaction boundary:
#   Notepad++: pre-existing bytes restored; unrelated alias survives; created
#              paths removed; alias-write failure rolls back the complete set;
#              recovery-promotion failure aborts before mutation; crash after
#              manifest commit leaves Revert possible.
#   Cinema 4D: replaced tree restored byte-for-byte (unrelated nested files
#              included); created directory removed; failures during pristine
#              capture, recovery promotion, live mutation and manifest commit
#              leave no user-data loss and no unrecoverable state.
#
#   .\tools\test-first-touch-recovery.ps1          # all tests
#   .\tools\test-first-touch-recovery.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\install.ps1'
$nppOut = Join-Path $root 'desktop\out\notepadplusplus'
$c4dOut = Join-Path $root 'desktop\out\cinema4d'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

function Run-Child([string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}

function Invoke-Install([string[]]$extra) {
    Run-Child (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer) + $extra)
}

function Same-Bytes([string]$path, [byte[]]$expected) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $now = [System.IO.File]::ReadAllBytes($path)
    if ($now.Length -ne $expected.Length) { return $false }
    for ($i = 0; $i -lt $now.Length; $i++) { if ($now[$i] -ne $expected[$i]) { return $false } }
    return $true
}

function Get-TreeFingerprint([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return '<absent>' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($dir.Length).TrimStart('\')
        $hash = [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($f.FullName))).Replace('-', '')
        [void]$sb.AppendLine("$rel=$hash")
    }
    return $sb.ToString()
}

function Get-ManifestKeys {
    $p = Join-Path $env:WINTAGE_APPDATA 'installed.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $o = [System.IO.File]::ReadAllText($p, $utf8) | ConvertFrom-Json
    return @($o.PSObject.Properties.Name)
}

if ($List) {
    Write-Host "test-first-touch-recovery.ps1 (Notepad++ + Cinema 4D first-touch ownership):"
    Write-Host "  npp-1  pre-existing primary + aliases + marker: Apply -> repaint -> Revert restores every byte"
    Write-Host "  npp-2  unrelated Wintage-*.xml outside the ledger survives Revert"
    Write-Host "  npp-3  absent start: Apply -> Revert removes only Wintage-created paths"
    Write-Host "  npp-4  failure after the first alias write restores the complete pre-operation set"
    Write-Host "  npp-5  recovery-promotion failure aborts before any live mutation"
    Write-Host "  npp-6  crash after the manifest commit leaves valid persistent recovery and Revert works"
    Write-Host "  c4d-1  pre-existing scheme tree: Apply -> repaint -> Revert restores byte-for-byte"
    Write-Host "  c4d-2  absent scheme dir: Apply -> Revert removes the Wintage-created directory"
    Write-Host "  c4d-3  capture / promotion / live-mutation / manifest failures lose no user data"
    Write-Host "  c4d-4  crash after the manifest commit leaves valid persistent recovery and Revert works"
    exit 0
}

# Fixtures need generated desktop output exactly like the other installer
# suites. Failing here is a missing precondition, never a skipped test.
if (-not (Test-Path -LiteralPath $nppOut)) { throw "generated Notepad++ output missing: $nppOut - run 'node tools/build-desktop.js'" }
if (-not (Test-Path -LiteralPath $c4dOut)) { throw "generated Cinema 4D output missing: $c4dOut - run 'node tools/build-desktop.js'" }
$nppPacks = @(Get-ChildItem $nppOut -Directory | Sort-Object Name)
$c4dPacks = @(Get-ChildItem $c4dOut -Directory | Sort-Object Name)
$packA = $nppPacks[0].Name
$packB = if ($nppPacks.Count -gt 1) { $nppPacks[1].Name } else { $nppPacks[0].Name }
$c4dPackA = $c4dPacks[0].Name
$c4dPackB = if ($c4dPacks.Count -gt 1) { $c4dPacks[1].Name } else { $c4dPacks[0].Name }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-firsttouch-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$prevAppData = $env:WINTAGE_APPDATA
$seamKeys = @(
    'WINTAGE_TEST_FAIL_NPP_AFTER_ALIAS', 'WINTAGE_TEST_FAIL_NPP_RECOVERY', 'WINTAGE_TEST_CRASH_AFTER_NPP_COMMIT',
    'WINTAGE_TEST_FAIL_C4D_CAPTURE', 'WINTAGE_TEST_FAIL_C4D_RECOVERY', 'WINTAGE_TEST_FAIL_C4D_AFTER_COPY',
    'WINTAGE_TEST_CRASH_AFTER_C4D_COMMIT', 'WINTAGE_TEST_FAIL_MANIFEST_MOVE'
)
$prevSeams = @{}
foreach ($k in $seamKeys) { $prevSeams[$k] = [Environment]::GetEnvironmentVariable($k) }
foreach ($k in $seamKeys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }

function New-Case([string]$name) {
    $dir = Join-Path $testRoot $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $appdata = Join-Path $dir 'appdata'
    New-Item -ItemType Directory -Path $appdata -Force | Out-Null
    $env:WINTAGE_APPDATA = $appdata
    return $dir
}

function New-NppFixture([string]$caseDir, [string[]]$names) {
    $npp = Join-Path $caseDir 'npp'
    $themes = Join-Path $npp 'themes'
    New-Item -ItemType Directory -Path $themes -Force | Out-Null
    foreach ($n in $names) { [System.IO.File]::WriteAllText((Join-Path $themes $n), "user-original:$n", $utf8) }
    return $npp
}

function New-C4dFixture([string]$caseDir, [switch]$WithWintage) {
    $c4d = Join-Path $caseDir 'c4d'
    $schemes = Join-Path $c4d 'resource\modules\c4d_base\schemes'
    New-Item -ItemType Directory -Path $schemes -Force | Out-Null
    if ($WithWintage) {
        $w = Join-Path $schemes 'Wintage'
        New-Item -ItemType Directory -Path (Join-Path $w 'nested') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $w 'wintage.col'), 'user-original-col', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $w 'wintage.res'), 'user-original-res', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $w 'unrelated.txt'), 'not wintage data', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $w 'nested\deep.dat'), 'nested user data', $utf8)
    }
    return @{ Root = $c4d; Wintage = (Join-Path $schemes 'Wintage') }
}

try {
    # ════ npp-1: complete pre-existing state survives Apply -> repaint -> Revert ══
    $case = New-Case 'npp-1'
    $npp = New-NppFixture $case @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')
    $themes = Join-Path $npp 'themes'
    $originals = @{}
    foreach ($n in @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')) {
        $originals[$n] = [System.IO.File]::ReadAllBytes((Join-Path $themes $n))
    }
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    check 'npp-1 apply exits 0' ($r.Code -eq 0)
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\notepadplusplus\recovery.json'
    $recPristine = Join-Path $env:WINTAGE_APPDATA 'recovery\notepadplusplus\pristine'
    check 'npp-1 first-touch recovery.json exists' (Test-Path -LiteralPath $recMeta)
    check 'npp-1 provenance sidecar exists' (Test-Path -LiteralPath ($recMeta + '.provenance.json'))
    check 'npp-1 pristine bytes were captured' (Test-Path -LiteralPath $recPristine)
    $metaBytes = [System.IO.File]::ReadAllBytes($recMeta)
    $pristinePrint = Get-TreeFingerprint $recPristine

    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packB)
    check 'npp-1 repaint exits 0' ($r.Code -eq 0)
    check 'npp-1 repaint did NOT replace the first-touch recovery.json' (Same-Bytes $recMeta $metaBytes)
    check 'npp-1 repaint did NOT recapture the pristine bytes' ((Get-TreeFingerprint $recPristine) -eq $pristinePrint)

    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Revert')
    check 'npp-1 revert exits 0' ($r.Code -eq 0)
    foreach ($n in @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')) {
        check "npp-1 $n restored byte-for-byte" (Same-Bytes (Join-Path $themes $n) $originals[$n])
    }
    check 'npp-1 recovery consumed after revert' (-not (Test-Path -LiteralPath $recMeta))
    check 'npp-1 manifest entry removed' (@(Get-ManifestKeys) -notcontains 'notepadplusplus')

    # ════ npp-2: an alias outside the ownership ledger survives Revert ══════════
    $case = New-Case 'npp-2'
    $npp = New-NppFixture $case @('Wintage-userowned.xml')
    $themes = Join-Path $npp 'themes'
    $userAlias = Join-Path $themes 'Wintage-userowned.xml'
    $userBytes = [System.IO.File]::ReadAllBytes($userAlias)
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    check 'npp-2 apply exits 0' ($r.Code -eq 0)
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Revert')
    check 'npp-2 revert exits 0' ($r.Code -eq 0)
    check 'npp-2 unrelated matching alias survived byte-for-byte' (Same-Bytes $userAlias $userBytes)
    check 'npp-2 no Wintage-owned files remain' (@(Get-ChildItem $themes -Filter 'Wintage-*.xml' -ErrorAction SilentlyContinue).Count -eq 1)

    # ════ npp-3: absent start creates, Revert removes only what was created ══════
    $case = New-Case 'npp-3'
    $npp = Join-Path $case 'npp'
    New-Item -ItemType Directory -Path $npp -Force | Out-Null
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    check 'npp-3 apply exits 0' ($r.Code -eq 0)
    check 'npp-3 alias installed' (Test-Path -LiteralPath (Join-Path $npp "themes\Wintage-$packA.xml"))
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Revert')
    check 'npp-3 revert exits 0' ($r.Code -eq 0)
    check 'npp-3 primary removed' (-not (Test-Path -LiteralPath (Join-Path $npp 'themes\Wintage.xml')))
    check 'npp-3 aliases removed' (@(Get-ChildItem (Join-Path $npp 'themes') -Filter 'Wintage-*.xml' -ErrorAction SilentlyContinue).Count -eq 0)
    check 'npp-3 marker removed' (-not (Test-Path -LiteralPath (Join-Path $npp 'themes\.wintage-npp-palette')))
    check 'npp-3 recovery consumed' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\notepadplusplus\recovery.json')))

    # ════ npp-4: alias-write failure rolls back the COMPLETE mutation set ═══════
    $case = New-Case 'npp-4'
    $npp = New-NppFixture $case @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')
    $themes = Join-Path $npp 'themes'
    $originals = @{}
    foreach ($n in @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')) {
        $originals[$n] = [System.IO.File]::ReadAllBytes((Join-Path $themes $n))
    }
    $env:WINTAGE_TEST_FAIL_NPP_AFTER_ALIAS = '1'
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    Remove-Item env:WINTAGE_TEST_FAIL_NPP_AFTER_ALIAS -ErrorAction SilentlyContinue
    check 'npp-4 injected failure exits NONZERO' ($r.Code -ne 0)
    check 'npp-4 the seam is what failed' ($r.Out -match 'WINTAGE_TEST_FAIL_NPP_AFTER_ALIAS')
    foreach ($n in @('Wintage.xml', "Wintage-$packA.xml", "Wintage-$packB.xml", '.wintage-npp-palette')) {
        check "npp-4 $n restored to its pre-operation bytes" (Same-Bytes (Join-Path $themes $n) $originals[$n])
    }
    check 'npp-4 manifest entry was not written' (@(Get-ManifestKeys) -notcontains 'notepadplusplus')
    check 'npp-4 rollback claim is present' ($r.Out -match 'exact pre-operation state')

    # ════ npp-5: recovery promotion failure aborts BEFORE live mutation ════════
    $case = New-Case 'npp-5'
    $npp = New-NppFixture $case @('Wintage.xml', '.wintage-npp-palette')
    $themes = Join-Path $npp 'themes'
    $primaryBytes = [System.IO.File]::ReadAllBytes((Join-Path $themes 'Wintage.xml'))
    $markerBytes = [System.IO.File]::ReadAllBytes((Join-Path $themes '.wintage-npp-palette'))
    $env:WINTAGE_TEST_FAIL_NPP_RECOVERY = '1'
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    Remove-Item env:WINTAGE_TEST_FAIL_NPP_RECOVERY -ErrorAction SilentlyContinue
    check 'npp-5 injected recovery failure exits NONZERO' ($r.Code -ne 0)
    check 'npp-5 the seam is what failed' ($r.Out -match 'WINTAGE_TEST_FAIL_NPP_RECOVERY')
    check 'npp-5 live primary untouched' (Same-Bytes (Join-Path $themes 'Wintage.xml') $primaryBytes)
    check 'npp-5 live marker untouched' (Same-Bytes (Join-Path $themes '.wintage-npp-palette') $markerBytes)
    check 'npp-5 no authoritative recovery.json was published' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\notepadplusplus\recovery.json')))
    check 'npp-5 no manifest entry was written' (@(Get-ManifestKeys) -notcontains 'notepadplusplus')

    # ════ npp-6: crash after manifest commit still leaves Revert possible ══════
    $case = New-Case 'npp-6'
    $npp = Join-Path $case 'npp'
    New-Item -ItemType Directory -Path $npp -Force | Out-Null
    $env:WINTAGE_TEST_CRASH_AFTER_NPP_COMMIT = '1'
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Palette', $packA)
    Remove-Item env:WINTAGE_TEST_CRASH_AFTER_NPP_COMMIT -ErrorAction SilentlyContinue
    check 'npp-6 crash seam exits NONZERO' ($r.Code -ne 0)
    check 'npp-6 the manifest really committed' (@(Get-ManifestKeys) -contains 'notepadplusplus')
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\notepadplusplus\recovery.json'
    check 'npp-6 persistent recovery exists after the crash' (Test-Path -LiteralPath $recMeta)
    $recParses = $false
    try { $null = [System.IO.File]::ReadAllText($recMeta, $utf8) | ConvertFrom-Json; $recParses = $true } catch { }
    check 'npp-6 recovery parses as JSON' $recParses
    $r = Invoke-Install @('-Target', 'notepadplusplus', '-NotepadPlusPlusPath', $npp, '-Revert')
    check 'npp-6 Revert after the crash exits 0' ($r.Code -eq 0)
    check 'npp-6 Revert removed the Wintage-created theme' (-not (Test-Path -LiteralPath (Join-Path $npp 'themes\Wintage.xml')))
    check 'npp-6 recovery consumed after the successful Revert' (-not (Test-Path -LiteralPath $recMeta))

    # ════ c4d-1: complete pre-existing tree survives Apply -> repaint -> Revert ══
    $case = New-Case 'c4d-1'
    $fix = New-C4dFixture $case -WithWintage
    $treeBefore = Get-TreeFingerprint $fix.Wintage
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    check 'c4d-1 apply exits 0' ($r.Code -eq 0)
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json'
    $recPristine = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\pristine'
    check 'c4d-1 recovery.json exists' (Test-Path -LiteralPath $recMeta)
    check 'c4d-1 pristine tree was captured' (Test-Path -LiteralPath $recPristine)
    $metaBytes = [System.IO.File]::ReadAllBytes($recMeta)
    $pristinePrint = Get-TreeFingerprint $recPristine

    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackB)
    check 'c4d-1 repaint exits 0' ($r.Code -eq 0)
    check 'c4d-1 repaint did NOT replace the first-touch recovery.json' (Same-Bytes $recMeta $metaBytes)
    check 'c4d-1 repaint did NOT recapture the pristine tree' ((Get-TreeFingerprint $recPristine) -eq $pristinePrint)

    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Revert')
    check 'c4d-1 revert exits 0' ($r.Code -eq 0)
    check 'c4d-1 the complete original tree is restored byte-for-byte' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)
    check 'c4d-1 recovery consumed after revert' (-not (Test-Path -LiteralPath $recMeta))

    # ════ c4d-2: absent directory is created then removed ═══════════════════════
    $case = New-Case 'c4d-2'
    $fix = New-C4dFixture $case
    check 'c4d-2 fixture starts without schemes\Wintage' (-not (Test-Path -LiteralPath $fix.Wintage))
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    check 'c4d-2 apply exits 0' ($r.Code -eq 0)
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json'
    $modeText = [System.IO.File]::ReadAllText($recMeta, $utf8)
    check 'c4d-2 recovery records mode=created' ($modeText -match '"mode"\s*:\s*"created"')
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Revert')
    check 'c4d-2 revert exits 0' ($r.Code -eq 0)
    check 'c4d-2 the Wintage-created directory is removed' (-not (Test-Path -LiteralPath $fix.Wintage))
    check 'c4d-2 recovery consumed' (-not (Test-Path -LiteralPath $recMeta))

    # ════ c4d-3a: pristine-capture failure → zero mutation ═════════════════════
    $case = New-Case 'c4d-3a'
    $fix = New-C4dFixture $case -WithWintage
    $treeBefore = Get-TreeFingerprint $fix.Wintage
    $env:WINTAGE_TEST_FAIL_C4D_CAPTURE = '1'
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    Remove-Item env:WINTAGE_TEST_FAIL_C4D_CAPTURE -ErrorAction SilentlyContinue
    check 'c4d-3a capture failure exits NONZERO' ($r.Code -ne 0)
    check 'c4d-3a live tree untouched' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)
    check 'c4d-3a no recovery.json published' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json')))
    check 'c4d-3a no manifest entry' (@(Get-ManifestKeys) -notcontains 'cinema4d')

    # ════ c4d-3b: recovery-promotion failure → zero mutation ═══════════════════
    $case = New-Case 'c4d-3b'
    $fix = New-C4dFixture $case -WithWintage
    $treeBefore = Get-TreeFingerprint $fix.Wintage
    $env:WINTAGE_TEST_FAIL_C4D_RECOVERY = '1'
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    Remove-Item env:WINTAGE_TEST_FAIL_C4D_RECOVERY -ErrorAction SilentlyContinue
    check 'c4d-3b promotion failure exits NONZERO' ($r.Code -ne 0)
    check 'c4d-3b live tree untouched' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)
    check 'c4d-3b no recovery.json published' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json')))
    check 'c4d-3b no manifest entry' (@(Get-ManifestKeys) -notcontains 'cinema4d')

    # ════ c4d-3c: live-mutation failure → rollback, recovery stays usable ══════
    $case = New-Case 'c4d-3c'
    $fix = New-C4dFixture $case -WithWintage
    $treeBefore = Get-TreeFingerprint $fix.Wintage
    $env:WINTAGE_TEST_FAIL_C4D_AFTER_COPY = '1'
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    Remove-Item env:WINTAGE_TEST_FAIL_C4D_AFTER_COPY -ErrorAction SilentlyContinue
    check 'c4d-3c live-write failure exits NONZERO' ($r.Code -ne 0)
    check 'c4d-3c live tree rolled back byte-for-byte' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)
    check 'c4d-3c no manifest entry' (@(Get-ManifestKeys) -notcontains 'cinema4d')
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json'
    check 'c4d-3c persistent recovery was established BEFORE mutation' (Test-Path -LiteralPath $recMeta)
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Revert')
    check 'c4d-3c Revert after the failed apply exits 0' ($r.Code -eq 0)
    check 'c4d-3c Revert restores the pristine tree byte-for-byte' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)

    # ════ c4d-3d: manifest-commit failure → rollback, recovery stays usable ════
    $case = New-Case 'c4d-3d'
    $fix = New-C4dFixture $case -WithWintage
    $treeBefore = Get-TreeFingerprint $fix.Wintage
    $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    Remove-Item env:WINTAGE_TEST_FAIL_MANIFEST_MOVE -ErrorAction SilentlyContinue
    check 'c4d-3d manifest-commit failure exits NONZERO' ($r.Code -ne 0)
    check 'c4d-3d live tree rolled back byte-for-byte' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)
    check 'c4d-3d no manifest entry' (@(Get-ManifestKeys) -notcontains 'cinema4d')
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json'
    check 'c4d-3d persistent recovery survives the failed commit' (Test-Path -LiteralPath $recMeta)
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Revert')
    check 'c4d-3d Revert after the failed apply exits 0' ($r.Code -eq 0)
    check 'c4d-3d Revert restores the pristine tree byte-for-byte' ((Get-TreeFingerprint $fix.Wintage) -eq $treeBefore)

    # ════ c4d-4: crash after manifest commit still leaves Revert possible ══════
    $case = New-Case 'c4d-4'
    $fix = New-C4dFixture $case
    $env:WINTAGE_TEST_CRASH_AFTER_C4D_COMMIT = '1'
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Palette', $c4dPackA)
    Remove-Item env:WINTAGE_TEST_CRASH_AFTER_C4D_COMMIT -ErrorAction SilentlyContinue
    check 'c4d-4 crash seam exits NONZERO' ($r.Code -ne 0)
    check 'c4d-4 the manifest really committed' (@(Get-ManifestKeys) -contains 'cinema4d')
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\cinema4d\recovery.json'
    check 'c4d-4 persistent recovery exists after the crash' (Test-Path -LiteralPath $recMeta)
    $r = Invoke-Install @('-Target', 'cinema4d', '-Cinema4DPath', $fix.Root, '-Revert')
    check 'c4d-4 Revert after the crash exits 0' ($r.Code -eq 0)
    check 'c4d-4 Revert removed the Wintage-created directory' (-not (Test-Path -LiteralPath $fix.Wintage))
    check 'c4d-4 recovery consumed after the successful Revert' (-not (Test-Path -LiteralPath $recMeta))
} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    foreach ($k in $seamKeys) {
        if ($null -eq $prevSeams[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($k, $prevSeams[$k]) }
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
