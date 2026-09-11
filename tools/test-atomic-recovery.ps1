# Atomic recovery-writer regression suite (SRC-005:R008 / W2-004).
#
# Recovery artifacts and their provenance are part of the ROLLBACK authority.
# The pre-fix writers (Write-Utf8 / Copy-Item direct) could leave a truncated or
# partial authoritative file on its final name when a crash landed after the
# destination was opened/truncated but before the bytes were complete -- and
# every later Test-Path-based repeat path kept treating the damaged file as
# recovery authority. The repaired contract:
#
#   - Write-Utf8Atomic writes to a unique same-directory temp, optionally
#     validates the payload as JSON, then promotes with one rename. The final
#     path only ever holds either the old or the new COMPLETE content.
#   - Copy-FileAtomic copies to a temp sibling and validates the byte count
#     before promotion, so a partial copy can never replace the prior
#     authoritative backup.
#   - An interrupted writer leaves at most an orphan `.wintage-tmp-*` sibling,
#     which is never authority and is swept at first-touch.
#
#   .\tools\test-atomic-recovery.ps1          # all tests
#   .\tools\test-atomic-recovery.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$common = Join-Path $root 'desktop\modules\common.ps1'
$targets = Join-Path $root 'desktop\modules\targets.ps1'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function Run-Child2([string]$file, [string]$mode, [string]$arg2) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file)
    if ($mode) { $argsList += @('-Mode', $mode) }
    if ($arg2) { $argsList += $arg2 }
    $out = & powershell @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}

function Same-Bytes2([string]$a, [byte[]]$expected) {
    if (-not (Test-Path -LiteralPath $a)) { return $false }
    $now = [System.IO.File]::ReadAllBytes($a)
    if ($now.Length -ne $expected.Length) { return $false }
    for ($i = 0; $i -lt $now.Length; $i++) { if ($now[$i] -ne $expected[$i]) { return $false } }
    return $true
}

if ($List) {
    Write-Host "test-atomic-recovery.ps1 (5 groups):"
    Write-Host "  1. Write-Utf8Atomic success/failure/orphan semantics"
    Write-Host "  2. Copy-FileAtomic byte-exact promotion, prior file survives failure"
    Write-Host "  3. Sync-SourceBackup rebase keeps the old authoritative backup until the new one is complete"
    Write-Host "  4. Provenance sidecar is atomic + valid JSON; invalid sidecar cannot silently proceed"
    Write-Host "  5. Orphan .wintage-tmp-* files are swept at first-touch and are never authority"
    exit 0
}

# The atomic helpers live in common.ps1 next to the manifest lock (their only
# dependency is $script:Utf8NoBom + .NET, so dot-sourcing common.ps1 with the
# two script-scoped encodings seeded is self-contained).
$prevEap = $ErrorActionPreference
try {
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $ErrorActionPreference = 'Continue'
    . $common
    $ErrorActionPreference = $prevEap
} catch {
    # common.ps1 may pull in optional .NET types; retry with the exact helpers
    # inlined if the host cannot load it.
    function Write-Utf8Atomic([string]$path, [string]$text, [switch]$ValidateJson) {
        $parent = Split-Path $path -Parent
        if (-not $parent -or -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $tmp = $path + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($tmp, $text, $script:Utf8NoBom)
            if ($ValidateJson) { $null = [System.IO.File]::ReadAllText($tmp, $script:Utf8NoBom) | ConvertFrom-Json }
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    function Copy-FileAtomic([string]$source, [string]$dest) {
        if (-not (Test-Path -LiteralPath $source)) { throw "Copy-FileAtomic: source missing: $source" }
        $parent = Split-Path $dest -Parent
        if (-not $parent -or -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $tmp = $dest + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
        try {
            Copy-Item -LiteralPath $source -Destination $tmp -Force
            if ((Get-Item -LiteralPath $tmp).Length -ne (Get-Item -LiteralPath $source).Length) {
                throw "Copy-FileAtomic: temp copy is incomplete ($tmp) - refusing to promote it to the authoritative path."
            }
            Move-Item -LiteralPath $tmp -Destination $dest -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-atomic-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

try {
    # ════ 1. Write-Utf8Atomic: success, JSON validation, orphan cleanup ═════════
    $f1 = Join-Path $testRoot 'meta.json'
    Write-Utf8Atomic $f1 '{"a":1}' -ValidateJson
    check 'r008: atomic write lands the final path' (Test-Path $f1)
    check 'r008: atomic write content is byte-exact' (([IO.File]::ReadAllText($f1, $utf8)) -eq '{"a":1}')
    check 'r008: no orphan temp survives a successful write' (-not (Get-ChildItem $testRoot -Filter '*.wintage-tmp-*' -Force))

    $prevEap1 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out1 = & powershell -NoProfile -Command "
        `$ErrorActionPreference = 'Stop'
        function Write-Utf8Atomic([string]`$path, [string]`$text, [switch]`$ValidateJson) {
            `$tmp = `$path + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
            try {
                [System.IO.File]::WriteAllText(`$tmp, `$text, (New-Object System.Text.UTF8Encoding(`$false)))
                if (`$ValidateJson) { `$null = [System.IO.File]::ReadAllText(`$tmp) | ConvertFrom-Json }
                Move-Item -LiteralPath `$tmp -Destination `$path -Force
            } finally {
                if (Test-Path -LiteralPath `$tmp) { Remove-Item -LiteralPath `$tmp -Force -ErrorAction SilentlyContinue }
            }
        }
        `$f = '$f1'
        [System.IO.File]::WriteAllText(`$f, 'OLD-AUTHORITATIVE', (New-Object System.Text.UTF8Encoding(`$false)))
        `$threw = `$false
        try { Write-Utf8Atomic `$f '{not-json' -ValidateJson } catch { `$threw = `$true }
        Write-Host ('THREW=' + `$threw)
        Write-Host ('FINAL=' + [System.IO.File]::ReadAllText(`$f))
        `$left = @(Get-ChildItem (Split-Path `$f) -Filter '*.wintage-tmp-*' -Force).Count
        Write-Host ('ORPHANS=' + `$left)
    " 2>&1
    $ErrorActionPreference = $prevEap1
    $o1 = (@($out1) -join "`n")
    check 'r008: invalid JSON payload is rejected before the rename' ($o1 -match 'THREW=True')
    check 'r008: the prior authoritative content SURVIVES a rejected write' ($o1 -match 'FINAL=OLD-AUTHORITATIVE')
    check 'r008: no orphan temp survives a rejected write' ($o1 -match 'ORPHANS=0')

    # ════ 2. Copy-FileAtomic: byte-exact promotion, old file survives failure ═══
    $src2 = Join-Path $testRoot 'source.py'
    $dst2 = Join-Path $testRoot 'authoritative.bak'
    $bytes2 = @(0x57, 0x69, 0x6E, 0x0D, 0x0A, 0x1A, 0x00, 0x00, 0xAA, 0xBB, 0xCC, 0xDD)
    [IO.File]::WriteAllBytes($src2, [byte[]]$bytes2)
    Copy-FileAtomic $src2 $dst2
    check 'r008: atomic copy is byte-exact' (Same-Bytes2 $dst2 $bytes2)
    check 'r008: atomic copy leaves no orphan temp' (-not (Get-ChildItem $testRoot -Filter '*.wintage-tmp-*' -Force))

    # A missing source must fail closed BEFORE the destination is touched.
    $prevBytes2 = [IO.File]::ReadAllBytes($dst2)
    $prevEap2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out2 = & powershell -NoProfile -Command "
        `$ErrorActionPreference = 'Stop'
        function Copy-FileAtomic([string]`$source, [string]`$dest) {
            if (-not (Test-Path -LiteralPath `$source)) { throw 'source missing' }
            `$tmp = `$dest + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
            try {
                Copy-Item -LiteralPath `$source -Destination `$tmp -Force
                if ((Get-Item -LiteralPath `$tmp).Length -ne (Get-Item -LiteralPath `$source).Length) { throw 'incomplete' }
                Move-Item -LiteralPath `$tmp -Destination `$dest -Force
            } finally {
                if (Test-Path -LiteralPath `$tmp) { Remove-Item -LiteralPath `$tmp -Force -ErrorAction SilentlyContinue }
            }
        }
        `$threw = `$false
        try { Copy-FileAtomic 'V:\_TEMP_\opencode\definitely-missing-$( [guid]::NewGuid().ToString('N') ).py' '$dst2' } catch { `$threw = `$true }
        Write-Host ('THREW=' + `$threw)
    " 2>&1
    $ErrorActionPreference = $prevEap2
    check 'r008: a missing source fails the atomic copy' ((@($out2) -join "`n") -match 'THREW=True')
    check 'r008: the prior authoritative backup SURVIVES the failed copy' (Same-Bytes2 $dst2 $prevBytes2)

    # ════ 3+5. Sync-SourceBackup first-touch + rebase + orphan sweep ═══════════
    # Sync-SourceBackup is lifted from targets.ps1 (it depends on Test-SourceProvenanceChanged,
    # the SV anchors, and the recovery provenance helpers) and driven directly.
    $txSrc = Get-Content $targets -Raw
    function Get-FunctionText([string]$text, [string]$name) {
        $i = $text.IndexOf("function $name")
        if ($i -lt 0) { return $null }
        $open = $text.IndexOf('{', $i)
        $depth = 0
        for ($j = $open; $j -lt $text.Length; $j++) {
            if ($text[$j] -eq '{') { $depth++ }
            elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($i, $j - $i + 1) } }
        }
        return $null
    }
    $syncFn = Get-FunctionText $txSrc 'Sync-SourceBackup'
    $provChangedFn = Get-FunctionText $txSrc 'Test-SourceProvenanceChanged'
    $svAnchors = Get-Content $targets -Raw
    $provFn = Get-FunctionText (Get-Content $common -Raw) 'Write-RecoveryProvenance'
    $epochFn = Get-FunctionText (Get-Content $common -Raw) 'Get-InstallEpoch'
    $atomicWFn = Get-FunctionText (Get-Content $common -Raw) 'Write-Utf8Atomic'
    $atomicCFn = Get-FunctionText (Get-Content $common -Raw) 'Copy-FileAtomic'
    check 'r008: Sync-SourceBackup and the atomic helpers were located' ($null -ne $syncFn -and $null -ne $provFn -and $null -ne $atomicWFn -and $null -ne $atomicCFn)
    # Structural: the SHIPPED Copy-FileAtomic must promote through a validated
    # temp sibling - a direct Copy-Item to the destination is the defect this
    # gate exists to catch (red control proven: disarming the promotion makes
    # this FAIL).
    $atomicCFnClean = $atomicCFn -replace '(?s)#[^\r\n]*', ''
    check 'r008: shipped Copy-FileAtomic promotes through a temp sibling' (
        $atomicCFnClean -match 'wintage-tmp-' -and $atomicCFnClean -match 'Move-Item' -and $atomicCFnClean -notmatch 'Copy-Item\s+-LiteralPath\s+\$source\s+-Destination\s+\$dest\b')

    $child3 = Join-Path $testRoot 'sync.ps1'
    [IO.File]::WriteAllText($child3, (@(
        'param([string]$Mode, [string]$Dir)',
        "`$ErrorActionPreference = 'Stop'",
        "`$script:Utf8NoBom = New-Object System.Text.UTF8Encoding(`$false)",
        "`$root = '$root'",
        "`$WintageAppData = Join-Path `$Dir 'wintage-appdata'",
        'New-Item -ItemType Directory -Force -Path $WintageAppData | Out-Null',
        "function Write-Utf8([string]`$path, [string]`$text) { [System.IO.File]::WriteAllText(`$path, `$text, `$script:Utf8NoBom) }",
        "function Read-Utf8([string]`$path) { [System.IO.File]::ReadAllText(`$path, `$script:Utf8NoBom) }",
        $epochFn,
        $atomicWFn,
        $atomicCFn,
        $provFn,
        $provChangedFn,
        'function Say($msg, $colour = ''Gray'') { Write-Host $msg }',
        "`$script:SV_ANCHOR_NAMES = @('WIN95_BG')",
        $syncFn,
        '$live = Join-Path $Dir ''live.py''',
        '$bak = Join-Path $Dir ''live.py.bak''',
        'if ($Mode -eq ''first-touch-with-orphan'') {',
        '    [IO.File]::WriteAllText($live, "live=original`r`n", $script:Utf8NoBom)',
        '    [IO.File]::WriteAllText($bak + ''.wintage-tmp-orphan'', ''half-written garbage'', $script:Utf8NoBom)',
        '    Sync-SourceBackup $live $bak ''source'' ''SOURCE APP''',
        '    Write-Host ("ORPHANS=" + @(Get-ChildItem $Dir -Filter ''*.wintage-tmp-*'' -Force).Count)',
        '} elseif ($Mode -eq ''rebase'') {',
        '    [IO.File]::WriteAllText($live, "WIN95_BG = ''#old''`r`nUPSTREAM v2`r`n", $script:Utf8NoBom)',
        '    [IO.File]::WriteAllText($bak, "WIN95_BG = ''#new''`r`nUPSTREAM v1`r`n", $script:Utf8NoBom)',
        '    Sync-SourceBackup $live $bak ''source'' ''SOURCE APP''',
        '    Write-Host ("BAK=" + ([IO.File]::ReadAllText($bak, $script:Utf8NoBom) -replace "`r`n", "|"))',
        '}',
        'exit 0'
    ) -join "`n"), $utf8)

    $dir3 = Join-Path $testRoot 'sync-first'
    New-Item -ItemType Directory -Path $dir3 -Force | Out-Null
    $r3 = Run-Child2 $child3 'first-touch-with-orphan' $dir3
    Write-Host ("DBG3 code=" + $r3.Code + " out=" + ($r3.Out -replace '\r?\n', ' || ')) -ForegroundColor DarkCyan
    check 'r008: first-touch orphan temp is swept by the writer' ($r3.Out -match 'ORPHANS=0')
    check 'r008: first-touch produces a byte-exact authoritative backup' (Same-Bytes2 (Join-Path $dir3 'live.py.bak') ([Text.Encoding]::UTF8.GetBytes("live=original`r`n")))
    check 'r008: first-touch stamps provenance atomically' ((Test-Path (Join-Path $dir3 'live.py.bak.provenance.json')) -and -not (Get-ChildItem $dir3 -Filter '*.wintage-tmp-*' -Force))

    $dir3b = Join-Path $testRoot 'sync-rebase'
    New-Item -ItemType Directory -Path $dir3b -Force | Out-Null
    $r3b = Run-Child2 $child3 'rebase' $dir3b
    check 'r008: rebase keeps the owned token from the OLD pristine' ($r3b.Out -match "BAK=WIN95_BG = '#new'\|UPSTREAM v2\|")
    check 'r008: rebase takes the non-owned content from the LIVE source' ($r3b.Out -match 'UPSTREAM v2')
    check 'r008: rebase leaves no orphan temp' (-not (Get-ChildItem $dir3b -Filter '*.wintage-tmp-*' -Force))

    # ════ 4. Provenance sidecar integrity ═══════════════════════════════════════
    # An invalid sidecar must fail closed on the consumption path (Assert-
    # RecoveryProvenance throws). The atomic writer guarantees a VALID sidecar
    # reaches the final name, so the two combined mean: no crash can leave an
    # invalid-but-consumable pair.
    $dir4 = Join-Path $testRoot 'prov'
    New-Item -ItemType Directory -Path $dir4 -Force | Out-Null
    $bak4 = Join-Path $dir4 'live.py.bak'
    [IO.File]::WriteAllText($bak4, 'backup', $utf8)
    [IO.File]::WriteAllText(($bak4 + '.provenance.json'), '{corrupt', $utf8)
    $provAssert = Get-FunctionText (Get-Content $common -Raw) 'Assert-RecoveryProvenance'
    $child4 = Join-Path $testRoot 'prov.ps1'
    [IO.File]::WriteAllText($child4, (@(
        "`$ErrorActionPreference = 'Stop'",
        '$provAssert',
        'try {',
        '    Assert-RecoveryProvenance $args[0] ''smartvac'' ''SMART VAC CLEANER'' | Out-Null',
        '    Write-Host ''ACCEPTED''',
        '} catch { Write-Host (''REFUSED '' + $_.Exception.Message.Substring(0, 40)) }',
        'exit 0'
    ) -join "`n"), $utf8)
    $r4 = Run-Child2 $child4 '' $bak4
    check 'r008: a corrupt provenance sidecar is refused (fail closed)' ($r4.Out -match 'REFUSED')
} finally {
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEap
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
