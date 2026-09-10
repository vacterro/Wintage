# Restore-WindowsPreState verified-rollback regression suite
# (SRC-005:R009 / W2-005 -- "Restore-WindowsPreState does not prove the exact
# pre-operation state contract").
#
# The windows target's rollback primitive used to suppress every owned
# registry/file failure (-ErrorAction SilentlyContinue) and treat a successful
# ShellExecute dispatch as proof that CurrentTheme came back. Its caller then
# printed "restored to its exact pre-operation state" over a rollback nobody
# had checked. The repaired contract is fail-closed: every mutation is checked,
# the whole owned state is read back and verified, and the function returns
# successfully ONLY when the captured pre-state is proven. Anything less throws
# one aggregated error naming the failing resource, so Invoke-TargetCommit's
# double-failure path reports INCOMPLETE instead of a false success.
#
# Everything runs against fixture scratch space (a temp themes directory and a
# scratch HKCU key); no real theme is ever activated and the user's Windows
# state is never touched.
#
#   .\tools\test-windows-prestate.ps1          # all tests
#   .\tools\test-windows-prestate.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$targetsSrc = Join-Path $root 'desktop\modules\targets.ps1'
$pass = 0; $fail = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

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
    Write-Host "test-windows-prestate.ps1 (6 groups):"
    Write-Host "  1. Positive control: verified restore succeeds and Invoke-TargetCommit claims exact restoration"
    Write-Host "  2. A. Generated theme deletion failure -> rollback INCOMPLETE, no exact-restoration claim"
    Write-Host "  3. B. Registry rollback failure (write AND removal) -> INCOMPLETE, resource named"
    Write-Host "  4. C. Theme activation false success -> bounded verifier fails the rollback"
    Write-Host "  5. E. Activation-not-confirmed recovery: verified restoration AND restoration failure"
    Write-Host "  6. Structural: no silent suppression left in the rollback primitive"
    exit 0
}

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
$restoreFn = Get-FunctionText $txSrc 'Restore-WindowsPreState'
$bytesFn = Get-FunctionText $txSrc 'Test-WintageBytesEqual'
$activationFn = Get-FunctionText $txSrc 'Invoke-WindowsThemeActivation'
$recoveryFn = Get-FunctionText $txSrc 'Invoke-WindowsActivationRecovery'
$commitFn = Get-FunctionText $txSrc 'Invoke-TargetCommit'
$nativeFn = Get-FunctionText $txSrc 'Invoke-Native'
check 'r009: the rollback primitive and its helpers were located in targets.ps1' (
    $null -ne $restoreFn -and $null -ne $bytesFn -and $null -ne $activationFn -and $null -ne $recoveryFn)

# ════ 6. Structural: the primitive itself must be silent-suppression-free ════
check 'r009: the rollback primitive never suppresses a New-ItemProperty failure' ($restoreFn -notmatch 'New-ItemProperty[^\r\n]*SilentlyContinue')
check 'r009: the rollback primitive never suppresses a Remove-ItemProperty failure' ($restoreFn -notmatch 'Remove-ItemProperty[^\r\n]*SilentlyContinue')
check 'r009: the rollback primitive never suppresses a Remove-Item failure' ($restoreFn -notmatch 'Remove-Item\b[^\r\n]*SilentlyContinue')
check 'r009: the rollback primitive verifies after restoring (read-back present)' ($restoreFn -match 'rollback verification FAILED')
check 'r009: the rollback primitive polls CurrentTheme with a bounded window' ($restoreFn -match 'bounded rollback window')
$invokeThemeFn = Get-FunctionText $txSrc 'Invoke-WindowsTheme '
check 'r009: the activation-failure path is wired through the verified recovery helper' (
    $null -ne $invokeThemeFn -and $invokeThemeFn -match 'Invoke-WindowsActivationRecovery')

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-winpre-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$harness = Join-Path $testRoot 'rollback-harness.ps1'
$harnessBody = @(
    'param([string]$Mode, [string]$DwmKey, [string]$ThemeKey, [string]$ThemesDir, [string]$PreThemeFile, [string]$OpThemeFile)',
    '$ErrorActionPreference = ''Stop''',
    '$WINDOWS_DWM_KEY = $DwmKey',
    '$WINDOWS_THEME_KEY = $ThemeKey',
    '$WINDOWS_THEMES_DIR = $ThemesDir',
    'function Say($msg, $colour = ''Gray'') { Write-Host $msg }',
    $bytesFn,
    # The harness NEVER lets a fixture reach the real Windows personalization
    # host: the dispatch is replaced by a stub that only reports what it was
    # asked to do. Case C relies on the stub being a no-op (false success).
    'function Invoke-WindowsThemeActivation([string]$themePath) { Write-Host ("DISPATCH-STUB: " + $themePath) }',
    $restoreFn,
    $recoveryFn,
    $commitFn,
    $nativeFn,
    '# Capture the pre-state from the fixture exactly the way Invoke-WindowsTheme does.',
    '$preAccentItem = Get-Item -LiteralPath $WINDOWS_DWM_KEY -ErrorAction SilentlyContinue',
    '$preAccentExists = [bool]($preAccentItem -and ($preAccentItem.GetValueNames() -contains ''AccentColorInactive''))',
    '$preAccent = if ($preAccentExists) { $preAccentItem.GetValue(''AccentColorInactive'', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }',
    '$preThemeState = @(',
    '    [pscustomobject]@{ Path = $PreThemeFile; Exists = $true; Bytes = [IO.File]::ReadAllBytes($PreThemeFile) }',
    '    [pscustomobject]@{ Path = (Join-Path $ThemesDir ''Wintage.absent.theme''); Exists = $false; Bytes = $null }',
    ')',
    '$rollbackArgs = @{ PreAccentExists = $preAccentExists; PreAccent = $preAccent; PreCurrentTheme = $PreThemeFile; PreThemeState = $preThemeState }',
    'function Mutate-Fixture {',
    '    New-ItemProperty -LiteralPath $WINDOWS_DWM_KEY -Name AccentColorInactive -Value 12345 -PropertyType DWord -Force | Out-Null',
    '    Set-Content -LiteralPath $PreThemeFile -Value ''MUTATED'' -NoNewline',
    '    Set-Content -LiteralPath $OpThemeFile -Value ''op-created'' -NoNewline',
    '    Set-Content -LiteralPath (Join-Path $ThemesDir ''Wintage.absent.theme'') -Value ''leftover'' -NoNewline',
    '}',
    'switch ($Mode) {',
    '  ''commit-ok'' {',
    '    Mutate-Fixture',
    '    Invoke-TargetCommit ''windows'' ''Windows system theme'' { throw ''COMMIT-BOOM'' } { Restore-WindowsPreState @rollbackArgs }',
    '  }',
    '  ''commit-reg-fail'' {',
    '    # The DWM key path cannot be written: the accent restore fails closed.',
    '    $WINDOWS_DWM_KEY = ''HKCU:\Software\WintageWinPreMissing\Nope''',
    '    Invoke-TargetCommit ''windows'' ''Windows system theme'' { throw ''COMMIT-BOOM'' } { Restore-WindowsPreState @rollbackArgs }',
    '  }',
    '  ''commit-reg-removal-fail'' {',
    '    # Pre-state: the accent value is ABSENT, so the rollback contract is',
    '    # REMOVAL. The operation creates the value; the harness then removes it',
    '    # again (the platform offers no way to lock a registry value, and an',
    '    # already-vanished property is the one deterministic way to force',
    '    # Remove-ItemProperty itself to fail under -ErrorAction Stop). The',
    '    # rollback must refuse to interpret that as a verified restore.',
    '    $rollbackArgs.PreAccentExists = $false',
    '    $rollbackArgs.PreAccent = $null',
    '    New-ItemProperty -LiteralPath $WINDOWS_DWM_KEY -Name AccentColorInactive -Value 12345 -PropertyType DWord -Force | Out-Null',
    '    Remove-ItemProperty -LiteralPath $WINDOWS_DWM_KEY -Name AccentColorInactive -Force',
    '    Invoke-TargetCommit ''windows'' ''Windows system theme'' { throw ''COMMIT-BOOM'' } { Restore-WindowsPreState @rollbackArgs }',
    '  }',
    '  ''file-fail'' {',
    '    # The operation-created theme file is locked: the sweep removal fails.',
    '    Set-Content -LiteralPath $OpThemeFile -Value ''op-created'' -NoNewline',
    '    $script:heldLock = [System.IO.File]::Open($OpThemeFile, ''Open'', ''Read'', ''None'')',
    '    Invoke-TargetCommit ''windows'' ''Windows system theme'' { throw ''COMMIT-BOOM'' } { Restore-WindowsPreState @rollbackArgs }',
    '  }',
    '  ''theme-false'' {',
    '    # CurrentTheme is NOT the captured theme and the dispatch stub is a',
    '    # no-op: the bounded verifier must fail the rollback.',
    '    $fake = Join-Path $ThemesDir ''Other.theme''',
    '    Set-Content -LiteralPath $fake -Value ''other'' -NoNewline',
    '    Set-ItemProperty -LiteralPath $WINDOWS_THEME_KEY -Name CurrentTheme -Value $fake',
    '    $rollbackArgs.PreCurrentTheme = $PreThemeFile',
    '    Invoke-TargetCommit ''windows'' ''Windows system theme'' { throw ''COMMIT-BOOM'' } { Restore-WindowsPreState @rollbackArgs }',
    '  }',
    '  ''recovery-ok'' {',
    '    Mutate-Fixture',
    '    try {',
    '        Invoke-WindowsActivationRecovery -ActivationFailure ''Windows: theme activation was dispatched but Windows did not confirm it after both attempts.'' @rollbackArgs',
    '        Write-Host ''NO-THROW''',
    '    } catch { Write-Host ("RECOVERY-THREW " + $_.Exception.Message) }',
    '  }',
    '  ''recovery-fail'' {',
    '    Mutate-Fixture',
    '    Set-Content -LiteralPath $OpThemeFile -Value ''op-created'' -NoNewline',
    '    $script:heldLock = [System.IO.File]::Open($OpThemeFile, ''Open'', ''Read'', ''None'')',
    '    try {',
    '        Invoke-WindowsActivationRecovery -ActivationFailure ''Windows: theme activation was dispatched but Windows did not confirm it after both attempts.'' @rollbackArgs',
    '        Write-Host ''NO-THROW''',
    '    } catch { Write-Host ("RECOVERY-THREW " + $_.Exception.Message) }',
    '  }',
    '}',
    'exit 0'
) -join "`n"
[System.IO.File]::WriteAllText($harness, $harnessBody, $utf8)

# Scratch registry + fixture state. Everything under HKCU\Software\WintageWinPreTest
# and the temp themes dir is created and removed by this suite only.
$regRoot = 'HKCU:\Software\WintageWinPreTest'
$regBase = $regRoot.TrimStart('HKCU:').TrimStart('\')
if (Test-Path -LiteralPath $regRoot) { Remove-Item -LiteralPath $regRoot -Recurse -Force }
New-Item -Path $regRoot -Force | Out-Null
$dwmKey = Join-Path $regRoot 'Dwm'
$dwmNoAccent = Join-Path $regRoot 'DwmNoAccent'
$themeKey = Join-Path $regRoot 'Themes'
New-Item -Path $dwmKey, $dwmNoAccent, $themeKey -Force | Out-Null
# 0xFF98A4C8 as a signed Int32 - the exact representation registry reads return.
$preAccentValue = -6739256
New-ItemProperty -Path $dwmKey -Name AccentColorInactive -Value $preAccentValue -PropertyType DWord -Force | Out-Null

$themesDir = Join-Path $testRoot 'themes'
New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
$preThemeFile = Join-Path $themesDir 'Pre.theme'
$preBytes = @(0x57, 0x69, 0x6E, 0x0D, 0x0A, 0x1A, 0x00, 0x00, 0xAA, 0xBB, 0xCC, 0xDD)
[System.IO.File]::WriteAllBytes($preThemeFile, [byte[]]$preBytes)
$opThemeFile = Join-Path $themesDir 'Wintage-1a2b3c4d5e.theme'
Set-ItemProperty -Path $themeKey -Name CurrentTheme -Value $preThemeFile

$harnessArgs = @('-NoProfile', '-ExecutionPolicy', '-ExecutionPolicy', 'Bypass')
$prevKeys = $null
try {
    $run6 = { param($mode, $extra)
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness, '-Mode', $mode,
               '-DwmKey', $dwmKey, '-ThemeKey', $themeKey, '-ThemesDir', $themesDir,
               '-PreThemeFile', $preThemeFile, '-OpThemeFile', $opThemeFile)
        if ($extra) { $a += $extra }
        Run-Child powershell $a
    }

    # ════ 1. D. Positive control: verified restore + honest success claim ═══════
    $r = & $run6 'commit-ok' $null
    check 'r009 D: commit failure still exits NONZERO' ($r.Code -ne 0)
    check 'r009 D: the surfaced error is the COMMIT one' ($r.Out -match 'COMMIT-BOOM')
    check 'r009 D: the verified rollback DOES claim exact restoration' ($r.Out -match 'exact pre-operation state')
    check 'r009 D: no INCOMPLETE is reported' ($r.Out -notmatch 'INCOMPLETE')
    check 'r009 D: the DWM accent value is back to the captured pre-state' (
        ((Get-Item -LiteralPath $dwmKey).GetValue('AccentColorInactive', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)) -eq $preAccentValue)
    check 'r009 D: the pre-existing theme file is byte-identical again' (Same-Bytes $preThemeFile $preBytes)
    check 'r009 D: the operation-created theme file is gone' (-not (Test-Path $opThemeFile))
    check 'r009 D: the originally-absent owned path is absent again' (-not (Test-Path (Join-Path $themesDir 'Wintage.absent.theme')))

    # ════ 2. A. Generated theme deletion failure ════════════════════════════════
    $r = & $run6 'file-fail' $null
    check 'r009 A: the operation exits NONZERO' ($r.Code -ne 0)
    check 'r009 A: the rollback is reported INCOMPLETE' ($r.Out -match 'INCOMPLETE')
    check 'r009 A: the failing resource is named' ($r.Out -match [regex]::Escape($opThemeFile))
    check 'r009 A: no exact-restoration success claim' ($r.Out -notmatch 'exact pre-operation state')

    # ════ 3. B. Registry rollback failure (write) ═══════════════════════════════
    $r = & $run6 'commit-reg-fail' $null
    check 'r009 B: the operation exits NONZERO' ($r.Code -ne 0)
    check 'r009 B: the rollback failure is surfaced as INCOMPLETE' ($r.Out -match 'INCOMPLETE')
    check 'r009 B: the failing resource (AccentColorInactive) is named' ($r.Out -match 'AccentColorInactive')
    check 'r009 B: no exact-restoration success claim' ($r.Out -notmatch 'exact pre-operation state')
    check 'r009 B: the original commit failure survives' ($r.Out -match 'COMMIT-BOOM')

    # B2. Removal failure: absence can no longer be faked by a suppressed error.
    $r = & $run6 'commit-reg-removal-fail' $null
    check 'r009 B2: the forced removal failure exits NONZERO' ($r.Code -ne 0)
    check 'r009 B2: the rollback failure is surfaced as INCOMPLETE' ($r.Out -match 'INCOMPLETE')
    check 'r009 B2: AccentColorInactive is named' ($r.Out -match 'AccentColorInactive')
    check 'r009 B2: no exact-restoration success claim' ($r.Out -notmatch 'exact pre-operation state')

    # ════ 4. C. Theme activation false success ══════════════════════════════════
    $r = & $run6 'theme-false' $null
    check 'r009 C: the rollback exits NONZERO' ($r.Code -ne 0)
    check 'r009 C: the dispatch was attempted through the activation path' ($r.Out -match 'DISPATCH-STUB')
    check 'r009 C: the bounded verifier fails the rollback (INCOMPLETE)' ($r.Out -match 'INCOMPLETE')
    check 'r009 C: the CurrentTheme mismatch is named' ($r.Out -match 'CurrentTheme')
    check 'r009 C: no exact-restoration success claim' ($r.Out -notmatch 'exact pre-operation state')

    # ════ 5. E. Explicit activation-not-confirmed recovery ══════════════════════
    # Run recovery-fail FIRST: it leaves the fixture mutated (a locked
    # operation-created file keeps the rollback INCOMPLETE), so the positive
    # half must re-baseline its own fixture before asserting a verified restore.
    $r = & $run6 'recovery-fail' $null
    check 'r009 E2: a failed rollback does NOT claim the owned pre-state was restored' ($r.Out -notmatch 'verified restored')
    check 'r009 E2: it surfaces an INCOMPLETE double failure' ($r.Out -match 'ROLLBACK ALSO FAILED' -and $r.Out -match 'INCOMPLETE')
    check 'r009 E2: the failed rollback resource is named' ($r.Out -match [regex]::Escape($opThemeFile))
    check 'r009 E2: the original activation failure is kept' ($r.Out -match 'did not confirm it after both attempts')

    # C leaves CurrentTheme pointing at Other.theme BY DESIGN (its rollback
    # fails), and B2 leaves the DWM accent value absent (its rollback removes
    # it). Re-baseline the fixture so the positive recovery half captures and
    # verifies the full pre-state cleanly.
    Set-ItemProperty -Path $themeKey -Name CurrentTheme -Value $preThemeFile
    New-ItemProperty -Path $dwmKey -Name AccentColorInactive -Value $preAccentValue -PropertyType DWord -Force | Out-Null
    $r = & $run6 'recovery-ok' $null
    check 'r009 E: the recovery path still fails the OPERATION (activation was not confirmed)' ($r.Out -match 'RECOVERY-THREW')
    check 'r009 E: with a verified rollback it reports the activation failure honestly' ($r.Out -match 'verified restored')
    check 'r009 E: it does NOT report a double failure' ($r.Out -notmatch 'ROLLBACK ALSO FAILED')
    check 'r009 E: it never claims INCOMPLETE' ($r.Out -notmatch 'INCOMPLETE')
    check 'r009 E: the DWM accent value was actually restored' (
        ((Get-Item -LiteralPath $dwmKey).GetValue('AccentColorInactive', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)) -eq $preAccentValue)
    check 'r009 E: the theme file bytes were actually restored' (Same-Bytes $preThemeFile $preBytes)
    check 'r009 E: the operation-created theme file was actually removed' (-not (Test-Path $opThemeFile))

    # The DWM backup recovery authority must never be deleted by a rollback
    # attempt - verify the primitive never even references it.
    check 'r009: the rollback primitive never touches the DWM backup recovery authority' ($restoreFn -notmatch 'WINDOWS_DWM_BACKUP')
} finally {
    Remove-Item -LiteralPath $regRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
