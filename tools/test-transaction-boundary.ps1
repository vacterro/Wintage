# Transaction-boundary + recovery-honesty regression suite
# (SRC-004: CORE-005 / W2-004 / W2-005 / W2-006 / W2-007).
#
# Five findings, one shared shape: the code NAMED a transaction that started too
# late, or reported a success it had not verified. Every one of them is invisible
# on the happy path, which is why no existing gate saw them.
#
#   CORE-005  ownership restore used string-emptiness as an absence sentinel, so
#             an owned INI key that originally existed as `Key=` came back ABSENT
#             -- the parser already had $null for absence and the capture kept
#             all three states; only the restore collapsed two of them.
#   W2-004    the target mutation ran BEFORE Invoke-TargetCommit, so the
#             byte-exact pre-state snapshot taken one line earlier protected only
#             the manifest write. A failure during the mutation itself threw past
#             it: application half-themed, ledger untouched.
#   W2-005    rollback callbacks invoked native programs (node, reg) without
#             checking their exit status, and the wrapper then printed "restored
#             to its exact pre-operation state". A double failure also discarded
#             the ORIGINAL commit error in favour of the rollback error.
#   W2-006    first-touch recovery creation sat before the ShouldProcess gate, so
#             `-WhatIf` -- whose entire contract is read-only -- became the first
#             writer of persistent recovery state.
#   W2-007    paths.json has two writers with atomic REPLACE but no atomic
#             UPDATE, so a concurrent GUI+CLI save lost one writer's key while
#             both reported success; and the GUI turned a known save failure into
#             "folder set to ...".
#
#   .\tools\test-transaction-boundary.ps1          # all tests
#   .\tools\test-transaction-boundary.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\install.ps1'
$targetsSrc = Join-Path $root 'desktop\modules\targets.ps1'
$commonSrc = Join-Path $root 'desktop\modules\common.ps1'
$guiSrc = Join-Path $root 'desktop\WintageInstaller.ps1'
$pass = 0; $fail = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Native stderr under $ErrorActionPreference='Stop' is promoted to a terminating
# NativeCommandError, which would abort this suite on the very refusals it
# asserts. Read exit codes the way every other suite here does.
function Run-Child([string]$exe, [string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $exe @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}

function Same-Bytes([string]$a, [byte[]]$expected) {
    if (-not (Test-Path -LiteralPath $a)) { return $false }
    $now = [System.IO.File]::ReadAllBytes($a)
    if ($now.Length -ne $expected.Length) { return $false }
    for ($i = 0; $i -lt $now.Length; $i++) { if ($now[$i] -ne $expected[$i]) { return $false } }
    return $true
}

if ($List) {
    Write-Host "test-transaction-boundary.ps1 (5 groups):"
    Write-Host "  1. CORE-005 present-empty owned INI keys survive Apply -> Revert (TotalCmd + qBittorrent)"
    Write-Host "  2. W2-006 first-ever generic extension -WhatIf writes NOTHING"
    Write-Host "  3. W2-004 mutation failure inside the transaction restores exact pre-state (extension + OBS + qBittorrent preflight)"
    Write-Host "  4. W2-005 checked rollback: native exits fail loudly, double failure keeps BOTH errors"
    Write-Host "  5. W2-007 paths.json serialized update + GUI save-failure propagation"
    exit 0
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-txn-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# ════ 1. CORE-005: present-empty is a THIRD state, not absence ══════════════
# `Key=` (present, empty) and no key at all are different configuration shapes.
# Get-IniKey has always returned '' vs $null for them and the snapshot has
# always kept that, so Revert deleting a `Key=` line was a pure restore defect.

$tcRoot = Join-Path $testRoot 'totalcmd'
New-Item -ItemType Directory -Path $tcRoot -Force | Out-Null
$tcIni = Join-Path $tcRoot 'wincmd.ini'
$tcTheme = Join-Path $tcRoot 'Current.ini'
[System.IO.File]::WriteAllText($tcIni, "[Colors]`r`nRedirectSection=`"%COMMANDER_PATH%\Current.ini`"`r`n", $utf8)
# BackColor exists as present-empty; ForeColor is genuinely absent. Both are
# Wintage-owned, so Revert has to reproduce BOTH shapes.
[System.IO.File]::WriteAllText($tcTheme, "[ColorTheme]`r`nEnableColorFilters=1`r`n[Colors]`r`nBackColor=`r`n[ColorsDark]`r`nBackColor=`r`n", $utf8)
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'totalcmd', '-TotalCmdIni', $tcIni, '-Palette', 'goldendefault')
check 'core005 totalcmd: apply exits 0' ($r.Code -eq 0)
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'totalcmd', '-TotalCmdIni', $tcIni, '-Revert')
check 'core005 totalcmd: revert exits 0' ($r.Code -eq 0)
$tcAfter = [System.IO.File]::ReadAllText($tcTheme, $utf8)
check 'core005 totalcmd: present-empty BackColor is still PRESENT and empty in [Colors]' ($tcAfter -match '(?m)^BackColor=\r?$')
check 'core005 totalcmd: present-empty BackColor restored in BOTH owned sections' ((([regex]::Matches($tcAfter, '(?m)^BackColor=\r?$')).Count) -eq 2)
check 'core005 totalcmd: genuinely absent ForeColor stays absent' ($tcAfter -notmatch '(?m)^ForeColor=')

$prevApp1 = $env:APPDATA
$prevWin1 = $env:WINTAGE_APPDATA
$prevRun1 = $env:WINTAGE_TEST_ALLOW_RUNNING_QBT
try {
    $fakeApp1 = Join-Path $testRoot 'appdata-qbt-empty'
    $qbtDir1 = Join-Path $fakeApp1 'qBittorrent'
    New-Item -ItemType Directory -Path $qbtDir1, (Join-Path $fakeApp1 'Wintage') -Force | Out-Null
    $qbtIni1 = Join-Path $qbtDir1 'qBittorrent.ini'
    # UseCustomUITheme is present-empty; CustomUIThemePath is absent.
    [System.IO.File]::WriteAllText($qbtIni1, "[Preferences]`r`nGeneral\UseCustomUITheme=`r`nGeneral\Locale=en`r`n", $utf8)
    $env:APPDATA = $fakeApp1
    $env:WINTAGE_APPDATA = Join-Path $fakeApp1 'Wintage'
    $env:WINTAGE_TEST_ALLOW_RUNNING_QBT = '1'
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'qbittorrent', '-Palette', 'goldendefault')
    check 'core005 qbt: apply exits 0' ($r.Code -eq 0)
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'qbittorrent', '-Revert')
    check 'core005 qbt: revert exits 0' ($r.Code -eq 0)
    $qbtAfter1 = [System.IO.File]::ReadAllText($qbtIni1, $utf8)
    check 'core005 qbt: present-empty UseCustomUITheme is still PRESENT and empty' ($qbtAfter1 -match '(?m)^General\\UseCustomUITheme=\r?$')
    check 'core005 qbt: absent CustomUIThemePath stays absent' ($qbtAfter1 -notmatch '(?m)^General\\CustomUIThemePath=')
    check 'core005 qbt: unrelated Locale untouched' ($qbtAfter1 -match '(?m)^General\\Locale=en\r?$')
} finally { $env:APPDATA = $prevApp1; $env:WINTAGE_APPDATA = $prevWin1; $env:WINTAGE_TEST_ALLOW_RUNNING_QBT = $prevRun1 }

# ════ 2. W2-006: -WhatIf is read-only, including first-touch recovery ═══════
# The dry run must not be the first writer of persistent recovery state, and it
# must not fail because a direct .NET write escaped a suppressed New-Item.

$prevHome2 = $env:HOME
$prevWin2 = $env:WINTAGE_APPDATA
try {
    foreach ($case in @('created', 'replaced')) {
        $home2 = Join-Path $testRoot "whatif-$case"
        $ext2 = Join-Path $home2 '.vscode\extensions'
        $app2 = Join-Path $home2 'appdata'
        New-Item -ItemType Directory -Path $ext2, $app2 -Force | Out-Null
        $dest2 = Join-Path $ext2 'wintage-themes'
        if ($case -eq 'replaced') {
            New-Item -ItemType Directory -Path $dest2 -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dest2 'user-owned.txt'), 'not ours', $utf8)
        }
        $env:HOME = $home2
        $env:WINTAGE_APPDATA = $app2
        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'vscode', '-Palette', 'goldendefault', '-WhatIf')
        check "w2006 $case`: -WhatIf exits 0" ($r.Code -eq 0)
        check "w2006 $case`: -WhatIf created NO recovery directory" (-not (Test-Path (Join-Path $app2 'recovery')))
        check "w2006 $case`: -WhatIf wrote NO recovery.json" (-not (Test-Path (Join-Path $app2 "recovery\vscode\recovery.json")))
        check "w2006 $case`: -WhatIf wrote NO manifest" (-not (Test-Path (Join-Path $app2 'installed.json')))
        if ($case -eq 'created') {
            check 'w2006 created: -WhatIf did not create the destination' (-not (Test-Path $dest2))
        } else {
            check 'w2006 replaced: destination still holds ONLY the user file' (
                (Test-Path (Join-Path $dest2 'user-owned.txt')) -and
                -not (Test-Path (Join-Path $dest2 'themes')))
        }
    }
} finally { $env:HOME = $prevHome2; $env:WINTAGE_APPDATA = $prevWin2 }

# ════ 3. W2-004: the transaction covers the MUTATION, not just the ledger ═══
# Each case injects a failure AFTER the target was mutated and BEFORE the
# manifest commit -- the window the pre-state snapshot was always taken for and
# the window it never actually covered.

# 3a. Generic VS Code-family extension: fail after the recursive copy.
$prevHome3 = $env:HOME
$prevWin3 = $env:WINTAGE_APPDATA
$prevFail3 = $env:WINTAGE_TEST_FAIL_AFTER_EXT_COPY
try {
    $home3 = Join-Path $testRoot 'ext-fail'
    $ext3 = Join-Path $home3 '.vscode\extensions'
    $app3 = Join-Path $home3 'appdata'
    New-Item -ItemType Directory -Path $ext3, $app3 -Force | Out-Null
    $dest3 = Join-Path $ext3 'wintage-themes'
    New-Item -ItemType Directory -Path $dest3 -Force | Out-Null
    $userFile3 = Join-Path $dest3 'user-owned.txt'
    [System.IO.File]::WriteAllText($userFile3, "the user's own extension content`r`n", $utf8)
    $pre3 = [System.IO.File]::ReadAllBytes($userFile3)
    $env:HOME = $home3
    $env:WINTAGE_APPDATA = $app3
    $env:WINTAGE_TEST_FAIL_AFTER_EXT_COPY = '1'
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'vscode', '-Palette', 'goldendefault')
    $env:WINTAGE_TEST_FAIL_AFTER_EXT_COPY = $prevFail3
    check 'w2004 ext: post-copy failure exits NONZERO' ($r.Code -ne 0)
    check 'w2004 ext: the user file is byte-identical again' (Same-Bytes $userFile3 $pre3)
    check 'w2004 ext: no Wintage themes left in the destination' (-not (Test-Path (Join-Path $dest3 'themes')))
    check 'w2004 ext: no manifest entry was written' (-not (Test-Path (Join-Path $app3 'installed.json')))
    check 'w2004 ext: the rollback claim is present (restore verified)' ($r.Out -match 'exact pre-operation state')
} finally { $env:HOME = $prevHome3; $env:WINTAGE_APPDATA = $prevWin3; $env:WINTAGE_TEST_FAIL_AFTER_EXT_COPY = $prevFail3 }

# 3b. OBS: the helper mutates user.ini + the .ovt + its own recovery artifacts,
# then fails before its last write. That is the audit's reproduced case.
$prevApp3b = $env:APPDATA
$prevWin3b = $env:WINTAGE_APPDATA
$prevFail3b = $env:WINTAGE_TEST_FAIL_AFTER_OBS_THEME
$prevRun3b = $env:WINTAGE_TEST_ALLOW_RUNNING_OBS
try {
    $fakeApp3b = Join-Path $testRoot 'appdata-obs'
    $obsCfg = Join-Path $fakeApp3b 'obs-studio'
    New-Item -ItemType Directory -Path $obsCfg, (Join-Path $fakeApp3b 'Wintage') -Force | Out-Null
    $obsIni = Join-Path $obsCfg 'user.ini'
    [System.IO.File]::WriteAllText($obsIni, "[Appearance]`r`nTheme=System`r`nLanguage=en-US`r`n", $utf8)
    $preObs = [System.IO.File]::ReadAllBytes($obsIni)
    $env:APPDATA = $fakeApp3b
    $env:WINTAGE_APPDATA = Join-Path $fakeApp3b 'Wintage'
    # The fixture config is not the one a locally running OBS owns. Without this
    # the run refuses BEFORE mutating anything on any machine with OBS open,
    # which looks identical to a clean rollback and would make this gate pass
    # for the wrong reason.
    $env:WINTAGE_TEST_ALLOW_RUNNING_OBS = '1'
    $env:WINTAGE_TEST_FAIL_AFTER_OBS_THEME = '1'
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'obs', '-Palette', 'goldendefault')
    $env:WINTAGE_TEST_FAIL_AFTER_OBS_THEME = $prevFail3b
    check 'w2004 obs: late-write failure exits NONZERO' ($r.Code -ne 0)
    check 'w2004 obs: the injected seam is what failed (not a refusal before mutating)' ($r.Out -match 'WINTAGE_TEST_FAIL_AFTER_OBS_THEME')
    check 'w2004 obs: user.ini is byte-identical again (Theme=System)' (Same-Bytes $obsIni $preObs)
    check 'w2004 obs: the Wintage theme file is gone' (-not (Test-Path (Join-Path $obsCfg 'themes\Wintage.ovt')))
    check 'w2004 obs: the helper recovery artifacts are gone' (
        -not (Test-Path (Join-Path $obsCfg 'user.ini.wintage.bak')) -and
        -not (Test-Path (Join-Path $obsCfg 'user.ini.wintage-created')))
    check 'w2004 obs: no manifest entry was written' (-not (Test-Path (Join-Path $fakeApp3b 'Wintage\installed.json')))
} finally {
    $env:APPDATA = $prevApp3b
    $env:WINTAGE_APPDATA = $prevWin3b
    $env:WINTAGE_TEST_FAIL_AFTER_OBS_THEME = $prevFail3b
    $env:WINTAGE_TEST_ALLOW_RUNNING_OBS = $prevRun3b
}

# 3c. qBittorrent Revert: a missing required pristine must be caught BEFORE the
# first mutation. Pre-fix it threw after the INI had already been rewritten.
$prevApp3c = $env:APPDATA
$prevWin3c = $env:WINTAGE_APPDATA
$prevRun3c = $env:WINTAGE_TEST_ALLOW_RUNNING_QBT
try {
    $fakeApp3c = Join-Path $testRoot 'appdata-qbt-preflight'
    $qbtDir3c = Join-Path $fakeApp3c 'qBittorrent'
    $wintage3c = Join-Path $fakeApp3c 'Wintage'
    New-Item -ItemType Directory -Path $qbtDir3c, $wintage3c -Force | Out-Null
    # A pre-existing theme directory makes the recovery mode 'replaced', so the
    # pristine copy becomes a REQUIRED revert dependency.
    $userTheme3c = Join-Path $qbtDir3c 'themes\wintage'
    New-Item -ItemType Directory -Path $userTheme3c -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $userTheme3c 'config.json'), '{"user":"theme"}', $utf8)
    $qbtIni3c = Join-Path $qbtDir3c 'qBittorrent.ini'
    [System.IO.File]::WriteAllText($qbtIni3c, "[Preferences]`r`nGeneral\UseCustomUITheme=false`r`nGeneral\Locale=en`r`n", $utf8)
    $env:APPDATA = $fakeApp3c
    $env:WINTAGE_APPDATA = $wintage3c
    $env:WINTAGE_TEST_ALLOW_RUNNING_QBT = '1'
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'qbittorrent', '-Palette', 'goldendefault')
    check 'w2004 qbt-preflight: apply exits 0' ($r.Code -eq 0)
    $themedIni3c = [System.IO.File]::ReadAllBytes($qbtIni3c)
    $manifestBefore3c = [System.IO.File]::ReadAllBytes((Join-Path $wintage3c 'installed.json'))
    # Destroy ONLY the pristine recovery, leaving recovery.json and the manifest.
    Remove-Item (Join-Path $wintage3c 'recovery\qbittorrent\pristine') -Recurse -Force
    $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'qbittorrent', '-Revert')
    check 'w2004 qbt-preflight: revert with a missing pristine exits NONZERO' ($r.Code -ne 0)
    check 'w2004 qbt-preflight: it says nothing was changed' ($r.Out -match 'nothing was changed')
    check 'w2004 qbt-preflight: the live INI was NOT touched' (Same-Bytes $qbtIni3c $themedIni3c)
    check 'w2004 qbt-preflight: the theme directory is still installed' (Test-Path (Join-Path $qbtDir3c 'themes\wintage\config.json'))
    check 'w2004 qbt-preflight: the manifest still records the install' (Same-Bytes (Join-Path $wintage3c 'installed.json') $manifestBefore3c)
} finally { $env:APPDATA = $prevApp3c; $env:WINTAGE_APPDATA = $prevWin3c; $env:WINTAGE_TEST_ALLOW_RUNNING_QBT = $prevRun3c }

# ════ 4. W2-005: rollback is CHECKED, and a double failure keeps both errors ══
# Invoke-TargetCommit and Invoke-Native are lifted out of targets.ps1 and driven
# directly: the rest of that file pulls in the whole target universe ($root,
# $node, $WintageAppData) which has nothing to do with the contract under test.

$txSrc = Get-Content $targetsSrc -Raw
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
$commitFn = Get-FunctionText $txSrc 'Invoke-TargetCommit'
$nativeFn = Get-FunctionText $txSrc 'Invoke-Native'
check 'w2005: Invoke-TargetCommit and Invoke-Native were located in targets.ps1' (
    $null -ne $commitFn -and $null -ne $nativeFn)

$harness4 = Join-Path $testRoot 'commit-harness.ps1'
$harnessBody = @(
    'param([string]$Mode)',
    '$ErrorActionPreference = ''Stop''',
    'function Say($msg, $colour = ''Gray'') { Write-Host $msg }',
    $nativeFn,
    $commitFn,
    'switch ($Mode) {',
    '  ''native-nonzero'' {',
    '    # The rollback runs a native program that exits 3. Unchecked, this used',
    '    # to return quietly and the wrapper printed exact restoration.',
    '    Invoke-TargetCommit ''t'' ''Target'' { throw ''COMMIT-BOOM'' } {',
    '      Invoke-Native ''rollback native'' { & cmd /c exit 3 }',
    '    }',
    '  }',
    '  ''rollback-throws'' {',
    '    Invoke-TargetCommit ''t'' ''Target'' { throw ''COMMIT-BOOM'' } { throw ''ROLLBACK-BOOM'' }',
    '  }',
    '  ''rollback-ok'' {',
    '    Invoke-TargetCommit ''t'' ''Target'' { throw ''COMMIT-BOOM'' } { }',
    '  }',
    '  ''commit-ok'' {',
    '    Invoke-TargetCommit ''t'' ''Target'' { Write-Host ''committed'' } { throw ''must not run'' }',
    '  }',
    '}'
) -join "`n"
[System.IO.File]::WriteAllText($harness4, $harnessBody, $utf8)

$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness4, '-Mode', 'native-nonzero')
check 'w2005 native: a non-zero native exit in the rollback FAILS the operation' ($r.Code -ne 0)
check 'w2005 native: it does NOT claim exact restoration' ($r.Out -notmatch 'exact pre-operation state')
check 'w2005 native: the native exit code is named' ($r.Out -match 'exit 3')
check 'w2005 native: the ORIGINAL commit failure survives the rollback failure' ($r.Out -match 'COMMIT-BOOM')

$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness4, '-Mode', 'rollback-throws')
check 'w2005 double: exits NONZERO' ($r.Code -ne 0)
check 'w2005 double: reports the commit error' ($r.Out -match 'COMMIT-BOOM')
check 'w2005 double: reports the rollback error' ($r.Out -match 'ROLLBACK-BOOM')
check 'w2005 double: says the target state is INCOMPLETE' ($r.Out -match 'INCOMPLETE')
check 'w2005 double: does NOT claim exact restoration' ($r.Out -notmatch 'exact pre-operation state')

$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness4, '-Mode', 'rollback-ok')
check 'w2005 restored: a successful rollback still exits NONZERO' ($r.Code -ne 0)
check 'w2005 restored: it DOES claim exact restoration' ($r.Out -match 'exact pre-operation state')
check 'w2005 restored: the surfaced error is the COMMIT one' ($r.Out -match 'COMMIT-BOOM')

$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness4, '-Mode', 'commit-ok')
check 'w2005 happy: a successful commit exits 0 and never runs the rollback' ($r.Code -eq 0 -and $r.Out -match 'committed')

# Structural sweep, because the audit's bar is "audit ALL restore callbacks, not
# only Terminal and MPC-HC": no restore scriptblock may invoke a native program
# without Invoke-Native. Restores are the SECOND scriptblock of each call.
function Get-RestoreBlocks([string]$text) {
    $blocks = @()
    $idx = 0
    while ($true) {
        $i = $text.IndexOf('Invoke-TargetCommit', $idx)
        if ($i -lt 0) { break }
        $idx = $i + 1
        if ($text.Substring([Math]::Max(0, $i - 9), 9) -match 'function') { continue }
        # Walk the first scriptblock, then capture the second.
        $found = 0
        $depth = 0
        $start = -1
        for ($j = $i; $j -lt $text.Length; $j++) {
            $c = $text[$j]
            if ($c -eq '{') { if ($depth -eq 0 -and $found -eq 1) { $start = $j }; $depth++ }
            elseif ($c -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $found++
                    if ($found -eq 2) { $blocks += $text.Substring($start, $j - $start + 1); break }
                }
            }
            elseif ($depth -eq 0 -and $found -ge 1 -and $c -notmatch '\s') {
                # Anything other than whitespace between the two scriptblocks
                # means this call has no restore callback at all.
                if ($c -ne '{') { break }
            }
        }
    }
    return $blocks
}
$restoreBlocks = Get-RestoreBlocks $txSrc
check 'w2005 sweep: restore callbacks were located' ($restoreBlocks.Count -ge 10)
$unchecked = @($restoreBlocks | Where-Object { $_ -match '&\s+(node|reg|cmd|powershell|pwsh)\b' -and $_ -notmatch 'Invoke-Native' })
check 'w2005 sweep: NO restore callback runs a native program without Invoke-Native' ($unchecked.Count -eq 0)

# A restore that cannot reproduce the snapshot must say INCOMPLETE, not stay
# quiet and let the wrapper print exact restoration. OBS's restore is the one
# with a byte snapshot to verify against, so it is the one that can be checked.
# The two nested helpers are lifted from targets.ps1 and driven directly.
$obsSave = Get-FunctionText $txSrc 'Save-ObsPreState'
$obsRestore = Get-FunctionText $txSrc 'Restore-ObsPreState'
check 'w2005 verify: the OBS pre-state helpers were located' ($null -ne $obsSave -and $null -ne $obsRestore)
$verifyDir = Join-Path $testRoot 'obs-verify'
New-Item -ItemType Directory -Path $verifyDir -Force | Out-Null
$verifyChild = Join-Path $verifyDir 'verify.ps1'
[System.IO.File]::WriteAllText($verifyChild, (@(
    'param($cfg, $Mode)',
    '$ErrorActionPreference = ''Stop''',
    '$OBS_CONFIG = $cfg',
    $obsSave,
    $obsRestore,
    '$snap = Save-ObsPreState',
    'if ($Mode -eq ''blocked'') {',
    '    # Make restoration impossible for user.ini: a DIRECTORY now occupies its',
    '    # path, so WriteAllBytes cannot put the captured bytes back.',
    '    Remove-Item (Join-Path $cfg ''user.ini'') -Force',
    '    New-Item -ItemType Directory -Path (Join-Path $cfg ''user.ini'') -Force | Out-Null',
    '} else {',
    '    Set-Content -LiteralPath (Join-Path $cfg ''user.ini'') -Value ''MUTATED'' -NoNewline',
    '}',
    'try { Restore-ObsPreState $snap; Write-Host ''RESTORE=OK'' }',
    'catch { Write-Host ("RESTORE=THREW " + $_.Exception.Message) }',
    'exit 0'
) -join "`n"), $utf8)

$verifyCfgOk = Join-Path $verifyDir 'cfg-ok'
New-Item -ItemType Directory -Path $verifyCfgOk -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $verifyCfgOk 'user.ini'), "[Appearance]`r`nTheme=System`r`n", $utf8)
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifyChild, $verifyCfgOk, 'ok')
check 'w2005 verify: a restore that DID reproduce the snapshot returns quietly' ($r.Out -match 'RESTORE=OK')
check 'w2005 verify: and it really restored the bytes' (
    ([System.IO.File]::ReadAllText((Join-Path $verifyCfgOk 'user.ini'), $utf8)) -match 'Theme=System')

$verifyCfgBad = Join-Path $verifyDir 'cfg-bad'
New-Item -ItemType Directory -Path $verifyCfgBad -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $verifyCfgBad 'user.ini'), "[Appearance]`r`nTheme=System`r`n", $utf8)
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifyChild, $verifyCfgBad, 'blocked')
check 'w2005 verify: a restore that could NOT reproduce the snapshot THROWS' ($r.Out -match 'RESTORE=THREW')
check 'w2005 verify: and the message says INCOMPLETE' ($r.Out -match 'INCOMPLETE')
check 'w2005 verify: and it names the file it could not restore' ($r.Out -match 'user\.ini')

# ════ 5. W2-007: serialized paths.json update + honest GUI save failure ══════
# Atomic replace is not atomic update. Both writers are driven concurrently with
# the read -> write window deliberately widened, so the only thing that can keep
# both keys is the shared lock.

$guiText = Get-Content $guiSrc -Raw
$saveFn = Get-FunctionText $guiText 'Save-CustomPaths'
$askFn = Get-FunctionText $guiText 'Ask-CustomPath'
check 'w2007: the GUI save and ask functions were located' ($null -ne $saveFn -and $null -ne $askFn)

function Invoke-PathsRace([string]$label, [bool]$cliFirst) {
    $dir = Join-Path $testRoot ("paths-race-" + $label)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $pathsFile = Join-Path $dir 'paths.json'
    # Seed with a third key so a lost update is visible as a MISSING key rather
    # than as an empty file.
    [System.IO.File]::WriteAllText($pathsFile, '{"codenomad":"C:\\cn"}' + "`n", $utf8)
    $goFile = Join-Path $dir 'go'

    $cliChild = Join-Path $dir 'cli.ps1'
    [System.IO.File]::WriteAllText($cliChild, (@(
        'param($dir, $common, $goFile)',
        '$ErrorActionPreference = ''Stop''',
        '$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)',
        '$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)',
        '. $common',
        '$PathsPath = Join-Path $dir ''paths.json''',
        '$env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS = ''400''',
        'Set-Content -LiteralPath (Join-Path $dir ''ready-cli'') -Value ''r''',
        '$deadline = (Get-Date).AddSeconds(30)',
        'while (-not (Test-Path $goFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }',
        'Save-PathPreference ''portable'' ''C:\pb-from-cli''',
        'exit 0'
    ) -join "`n"), $utf8)

    $guiChild = Join-Path $dir 'gui.ps1'
    [System.IO.File]::WriteAllText($guiChild, (@(
        'param($dir, $goFile)',
        '$ErrorActionPreference = ''Stop''',
        '$PATH_TARGETS = @(''saipenview'', ''smartvac'', ''wildrift'')',
        '$script:pathsFile = Join-Path $dir ''paths.json''',
        '$script:customPaths = @{ ''smartvac'' = ''C:\sv-from-gui'' }',
        '$env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS = ''400''',
        $saveFn,
        'Set-Content -LiteralPath (Join-Path $dir ''ready-gui'') -Value ''r''',
        '$deadline = (Get-Date).AddSeconds(30)',
        'while (-not (Test-Path $goFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }',
        'if (-not (Save-CustomPaths)) { exit 3 }',
        'exit 0'
    ) -join "`n"), $utf8)

    $cliArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cliChild, $dir, (Join-Path $root 'desktop\modules\common.ps1'), $goFile)
    $guiArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $guiChild, $dir, $goFile)
    $procs = if ($cliFirst) {
        @((Start-Process powershell -ArgumentList $cliArgs -PassThru -WindowStyle Hidden),
          (Start-Process powershell -ArgumentList $guiArgs -PassThru -WindowStyle Hidden))
    } else {
        @((Start-Process powershell -ArgumentList $guiArgs -PassThru -WindowStyle Hidden),
          (Start-Process powershell -ArgumentList $cliArgs -PassThru -WindowStyle Hidden))
    }
    $deadline = (Get-Date).AddSeconds(30)
    while (((Test-Path (Join-Path $dir 'ready-cli')) -eq $false -or (Test-Path (Join-Path $dir 'ready-gui')) -eq $false) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 20
    }
    Set-Content -LiteralPath $goFile -Value 'go'
    $procs | ForEach-Object { $_.WaitForExit(60000) | Out-Null }
    $exitSum = ($procs | ForEach-Object { $_.ExitCode }) -join ','
    $raw = [System.IO.File]::ReadAllText($pathsFile, $utf8)
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ Exits = $exitSum; Parsed = $parsed; Raw = $raw }
}

foreach ($order in @($true, $false)) {
    $label = if ($order) { 'cli-first' } else { 'gui-first' }
    $res = Invoke-PathsRace $label $order
    check "w2007 $label`: both writers exited 0" ($res.Exits -eq '0,0')
    check "w2007 $label`: the file is valid JSON" ($null -ne $res.Parsed)
    check "w2007 $label`: the CLI-owned key survived" ($res.Parsed -and $res.Parsed.portable -eq 'C:\pb-from-cli')
    check "w2007 $label`: the GUI-owned key survived" ($res.Parsed -and $res.Parsed.smartvac -eq 'C:\sv-from-gui')
    check "w2007 $label`: the pre-existing foreign key survived" ($res.Parsed -and $res.Parsed.codenomad -eq 'C:\cn')
}

# Ask-CustomPath must PROPAGATE a save failure. The FolderBrowserDialog cannot
# open in a headless child, so exactly one line -- the dialog construction -- is
# replaced by a stub that answers OK with a chosen path. Everything the finding
# is about (the return value, the in-memory rollback) is the real source text.
$askDir = Join-Path $testRoot 'ask-failure'
New-Item -ItemType Directory -Path $askDir -Force | Out-Null
# Make the save fail for a reason the function cannot work around: paths.json's
# PARENT is a file, so neither the directory nor the lock can be created.
$blocker = Join-Path $askDir 'blocker'
[System.IO.File]::WriteAllText($blocker, 'not a directory', $utf8)
$askStubbed = $askFn -replace [regex]::Escape('$dlg = New-Object Windows.Forms.FolderBrowserDialog'),
    '$dlg = [pscustomobject]@{ Description = ''''; SelectedPath = '''' }; $dlg | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value { $this.SelectedPath = $env:WINTAGE_TEST_PICKED_PATH; return ''OK'' }'
check 'w2007 ask: the dialog line was the only substitution' ($askStubbed -ne $askFn -and $askStubbed -match 'Save-CustomPaths')
$askChild = Join-Path $askDir 'ask.ps1'
[System.IO.File]::WriteAllText($askChild, (@(
    'param($pathsFile, $picked)',
    '$ErrorActionPreference = ''Stop''',
    '$PATH_TARGETS = @(''saipenview'', ''smartvac'', ''wildrift'')',
    '$PATH_DEFAULTS = @{ ''smartvac'' = ''C:\'' }',
    '$script:pathsFile = $pathsFile',
    '$script:customPaths = @{}',
    '$env:WINTAGE_TEST_PICKED_PATH = $picked',
    'function Say-Log($m) { Write-Host $m }',
    $saveFn,
    $askStubbed,
    '$result = Ask-CustomPath ''smartvac''',
    'Write-Host ("RESULT=" + [bool]$result)',
    'Write-Host ("REMEMBERED=" + [bool]$script:customPaths.ContainsKey(''smartvac''))',
    'exit 0'
) -join "`n"), $utf8)
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $askChild, (Join-Path $blocker 'paths.json'), 'C:\picked-folder')
check 'w2007 ask: a failed save makes Ask-CustomPath return FALSE' ($r.Out -match 'RESULT=False')
check 'w2007 ask: the unsaved path is NOT left in the in-memory map' ($r.Out -match 'REMEMBERED=False')
check 'w2007 ask: the failure is reported to the log' ($r.Out -match 'could not save paths\.json')
# The same harness with a WRITABLE preferences file must still succeed, or the
# assertions above would pass on a function that always fails.
$r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $askChild, (Join-Path $askDir 'ok\paths.json'), 'C:\picked-folder')
check 'w2007 ask: a successful save returns TRUE (the gate can distinguish)' ($r.Out -match 'RESULT=True')
check 'w2007 ask: a successful save remembers the path' ($r.Out -match 'REMEMBERED=True')
check 'w2007 ask: a successful save actually wrote the file' (Test-Path (Join-Path $askDir 'ok\paths.json'))

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
exit $fail
