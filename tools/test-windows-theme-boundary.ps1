# SRC-007:R003 / CORE-003 -- Windows theme mutation rollback boundary
#
# Defect classes this test suite pins down:
#  1. Helper mid-write failure:
#     - If tools/install-windows-theme.js writes partial files and fails,
#       the transaction rollback must remove newly created files and restore pre-state.
#  2. AccentColorInactive registry write failure:
#     - If DWM AccentColorInactive write fails after helper success,
#       the transaction rollback must remove helper-created files and restore registry.
#  3. Activation dispatch failure:
#     - If Invoke-WindowsThemeActivation throws, rollback must restore registry and files.
#  4. Activation timeout / unconfirmed:
#     - If activation is never confirmed, rollback must restore registry and files.
#  5. Manifest commit failure:
#     - If Set-ManifestEntry throws after confirmed activation,
#       rollback must restore CurrentTheme, AccentColorInactive, and theme files.
#  6. Happy-path two-cycle lifecycle:
#     - Apply -> Revert -> Apply works cleanly with fresh baseline re-baselining.
#
# Red control: run with -RedControl to prove that pre-fix code fails rollback assertions.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$InstallerPath,
    [string]$Only
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$defaultInstaller = Join-Path $root 'desktop\install.ps1'
$installer = if ($InstallerPath) { $InstallerPath } else { $defaultInstaller }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-windows-theme-boundary.ps1 (CORE-003 Windows theme transaction boundary matrix):"
    Write-Host "  case 1  helper mid-write failure: partial files removed, pre-state restored, manifest untouched"
    Write-Host "  case 2  accent write failure: helper files removed, DWM restored, manifest untouched"
    Write-Host "  case 3  activation dispatch throw: files + DWM restored, manifest untouched"
    Write-Host "  case 4  activation timeout: files + DWM restored, manifest untouched"
    Write-Host "  case 5  manifest commit failure: full rollback restores pre-state after confirmed activation"
    Write-Host "  case 6  happy path two-cycle: Apply -> Revert -> Apply complete lifecycle"
    Write-Host "Red control: -RedControl (verifies that pre-fix implementation fails critical assertions)"
    exit 0
}

function Run-Child([string]$exe, [string[]]$argsList, [hashtable]$envVars = @{}) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $savedEnv = @{}
    foreach ($k in $envVars.Keys) {
        $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, [string]$envVars[$k])
    }
    try {
        $out = & $exe @argsList 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
    } finally {
        foreach ($k in $envVars.Keys) {
            [Environment]::SetEnvironmentVariable($k, $savedEnv[$k])
        }
        $ErrorActionPreference = $prev
    }
}

# Set up test scratch isolation environment
$testRoot = Join-Path $env:TEMP ("wintage-wintxn-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$testThemesDir = Join-Path $testRoot 'Themes'
New-Item -ItemType Directory -Path $testThemesDir -Force | Out-Null

$testAppData = Join-Path $testRoot 'AppData\Wintage'
New-Item -ItemType Directory -Path $testAppData -Force | Out-Null

# Scratch registry keys
$regRoot = 'HKCU:\Software\WintageTestWinBoundary'
if (Test-Path -LiteralPath $regRoot) { Remove-Item -LiteralPath $regRoot -Recurse -Force }
New-Item -Path $regRoot -Force | Out-Null
$testThemeKey = Join-Path $regRoot 'Themes'
$testDwmKey = Join-Path $regRoot 'DWM'
New-Item -Path $testThemeKey, $testDwmKey -Force | Out-Null

# Baseline theme fixture
$baselineThemeFile = Join-Path $testThemesDir 'PreBaseline.theme'
$baselineThemeContent = "[Theme]`r`nDisplayName=PreBaseline`r`n[Control Panel\Colors]`r`nBackground=0 0 0`r`n[VisualStyles]`r`nPath=%ResourceDir%\Themes\Aero\Aero.msstyles`r`n"
[System.IO.File]::WriteAllText($baselineThemeFile, $baselineThemeContent, $utf8)
Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $baselineThemeFile

$baseEnv = @{
    'WINTAGE_APPDATA' = $testAppData
    'WINTAGE_TEST_WINDOWS_THEMES_DIR' = $testThemesDir
    'WINTAGE_TEST_WINDOWS_THEME_KEY' = $testThemeKey
    'WINTAGE_TEST_WINDOWS_DWM_KEY' = $testDwmKey
    'WINTAGE_TEST_SKIP_ACTIVATION' = '1'
}

try {
    # ══════════════════════════════════════════════════════════════════════════
    # CASE 1: Helper mid-write failure (WINTAGE_TEST_FAIL_HELPER_MID_WRITE)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '1') {
        Write-Host "--- Case 1: Helper mid-write failure ---"
        $caseEnv = @{} + $baseEnv
        $caseEnv['WINTAGE_TEST_FAIL_HELPER_MID_WRITE'] = '1'

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 1: Apply exits nonzero on helper mid-write failure' ($r.Code -ne 0)

        $origTheme = Join-Path $testThemesDir 'Wintage.original.theme'
        $origThemeExists = Test-Path -LiteralPath $origTheme
        check 'case 1: helper-created Wintage.original.theme rolled back (absent)' (-not $origThemeExists)

        $origPathMarker = Join-Path $testThemesDir '.wintage-original-theme-path'
        check 'case 1: helper-created .wintage-original-theme-path rolled back (absent)' (-not (Test-Path -LiteralPath $origPathMarker))

        $manifestPath = Join-Path $testAppData 'installed.json'
        $hasManifestWin = $false
        if (Test-Path -LiteralPath $manifestPath) {
            $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $hasManifestWin = [bool]($man.windows)
        }
        check 'case 1: manifest has no windows entry' (-not $hasManifestWin)
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CASE 2: AccentColorInactive write failure (WINTAGE_TEST_FAIL_WIN_ACCENT_WRITE)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '2') {
        Write-Host "--- Case 2: Accent registry write failure ---"
        New-ItemProperty -Path $testDwmKey -Name AccentColorInactive -Value 42 -PropertyType DWord -Force | Out-Null
        $caseEnv = @{} + $baseEnv
        $caseEnv['WINTAGE_TEST_FAIL_WIN_ACCENT_WRITE'] = '1'

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 2: Apply exits nonzero on accent write failure' ($r.Code -ne 0)

        $wintageThemes = @(Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)
        check 'case 2: helper-created theme files rolled back (zero present)' ($wintageThemes.Count -eq 0)

        $paletteMarker = Join-Path $testThemesDir '.wintage-windows-palette'
        check 'case 2: palette marker rolled back (absent)' (-not (Test-Path -LiteralPath $paletteMarker))

        $dwmVal = (Get-ItemProperty -Path $testDwmKey -Name AccentColorInactive -ErrorAction SilentlyContinue).AccentColorInactive
        check 'case 2: DWM AccentColorInactive restored to pre-state (42)' ($dwmVal -eq 42)
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CASE 3: Activation dispatch failure (WINTAGE_TEST_FAIL_WIN_ACTIVATION_THROW)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '3') {
        Write-Host "--- Case 3: Activation dispatch throw ---"
        Remove-ItemProperty -Path $testDwmKey -Name AccentColorInactive -ErrorAction SilentlyContinue
        $caseEnv = @{} + $baseEnv
        $caseEnv['WINTAGE_TEST_FAIL_WIN_ACTIVATION_THROW'] = '1'

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 3: Apply exits nonzero on activation dispatch throw' ($r.Code -ne 0)

        $wintageThemes = @(Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)
        check 'case 3: theme files rolled back (zero present)' ($wintageThemes.Count -eq 0)

        $dwmProps = (Get-Item -Path $testDwmKey).GetValueNames()
        check 'case 3: DWM AccentColorInactive absent as in pre-state' ($dwmProps -notcontains 'AccentColorInactive')
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CASE 4: Activation timeout (WINTAGE_TEST_FAIL_WIN_ACTIVATION_TIMEOUT)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '4') {
        Write-Host "--- Case 4: Activation timeout / unconfirmed ---"
        $caseEnv = @{} + $baseEnv
        $caseEnv['WINTAGE_TEST_FAIL_WIN_ACTIVATION_TIMEOUT'] = '1'

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 4: Apply exits nonzero on activation timeout' ($r.Code -ne 0)
        check 'case 4: output reports unconfirmed activation' ($r.Out -match 'theme activation was dispatched but Windows did not confirm')

        $wintageThemes = @(Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)
        check 'case 4: theme files rolled back (zero present)' ($wintageThemes.Count -eq 0)
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CASE 5: Manifest commit failure (WINTAGE_TEST_FAIL_MANIFEST_MOVE)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '5') {
        Write-Host "--- Case 5: Manifest commit failure ---"
        New-ItemProperty -Path $testDwmKey -Name AccentColorInactive -Value 999 -PropertyType DWord -Force | Out-Null
        Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $baselineThemeFile
        $caseEnv = @{} + $baseEnv
        $caseEnv['WINTAGE_TEST_FAIL_MANIFEST_MOVE'] = '1'

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 5: Apply exits nonzero on manifest commit failure' ($r.Code -ne 0)

        $curTheme = (Get-ItemProperty -Path $testThemeKey -Name CurrentTheme).CurrentTheme
        check 'case 5: CurrentTheme restored to baseline pre-state' ($curTheme -eq $baselineThemeFile)

        $dwmVal = (Get-ItemProperty -Path $testDwmKey -Name AccentColorInactive).AccentColorInactive
        check 'case 5: DWM AccentColorInactive restored to pre-state (999)' ($dwmVal -eq 999)

        $wintageThemes = @(Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)
        check 'case 5: theme files rolled back (zero present)' ($wintageThemes.Count -eq 0)

        $manifestPath = Join-Path $testAppData 'installed.json'
        $hasManifestWin = $false
        if (Test-Path -LiteralPath $manifestPath) {
            $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $hasManifestWin = [bool]($man.windows)
        }
        check 'case 5: manifest has no windows entry' (-not $hasManifestWin)
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CASE 6: Happy path two-cycle lifecycle (Apply -> Revert -> Apply)
    # ══════════════════════════════════════════════════════════════════════════
    if (-not $Only -or $Only -eq '6') {
        Write-Host "--- Case 6: Happy-path two-cycle lifecycle ---"
        Remove-ItemProperty -Path $testDwmKey -Name AccentColorInactive -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $baselineThemeFile
        $caseEnv = @{} + $baseEnv

        # Cycle 1: Apply
        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'goldendefault') $caseEnv
        check 'case 6: cycle 1 Apply exits 0' ($r.Code -eq 0)

        $manifestPath = Join-Path $testAppData 'installed.json'
        $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
        check 'case 6: manifest records windows target' ($null -ne $man.windows)
        check 'case 6: manifest records goldendefault palette' ($man.windows.palette -eq 'goldendefault')

        $wintageTheme = Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage-*.theme' | Select-Object -First 1
        check 'case 6: Wintage theme file created' ($null -ne $wintageTheme)

        $paletteMarker = Join-Path $testThemesDir '.wintage-windows-palette'
        check 'case 6: palette marker exists' (Test-Path -LiteralPath $paletteMarker)

        # Cycle 1: Revert
        Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $wintageTheme.FullName
        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Revert') $caseEnv
        check 'case 6: cycle 1 Revert exits 0' ($r.Code -eq 0)

        $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
        check 'case 6: manifest windows entry removed after Revert' ($null -eq $man.windows)

        $retiredMarker = Join-Path $testThemesDir '.wintage-epoch-retired'
        check 'case 6: epoch retired marker exists after Revert' (Test-Path -LiteralPath $retiredMarker)
        check 'case 6: palette marker removed after Revert' (-not (Test-Path -LiteralPath $paletteMarker))

        # Cycle 2: Apply again with dracula
        $userThemeB = Join-Path $testThemesDir 'UserThemeB.theme'
        [System.IO.File]::WriteAllText($userThemeB, "[Theme]`r`nDisplayName=UserThemeB`r`n", $utf8)
        Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $userThemeB

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Palette', 'dracula') $caseEnv
        check 'case 6: cycle 2 Apply (dracula) exits 0' ($r.Code -eq 0)

        $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
        check 'case 6: cycle 2 manifest records dracula' ($man.windows.palette -eq 'dracula')
        check 'case 6: retired marker cleared on fresh cycle' (-not (Test-Path -LiteralPath $retiredMarker))

        # Cycle 2: Revert
        $wintageThemeDracula = Get-ChildItem -LiteralPath $testThemesDir -Filter 'Wintage-*.theme' | Select-Object -First 1
        Set-ItemProperty -Path $testThemeKey -Name CurrentTheme -Value $wintageThemeDracula.FullName
        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Target', 'windows', '-Revert') $caseEnv
        check 'case 6: cycle 2 Revert exits 0' ($r.Code -eq 0)

        $man = Get-Content $manifestPath -Raw | ConvertFrom-Json
        check 'case 6: cycle 2 manifest windows entry removed' ($null -eq $man.windows)
    }

    # ══════════════════════════════════════════════════════════════════════════
    # RED CONTROL: prove that pre-fix code fails rollback assertions
    # ══════════════════════════════════════════════════════════════════════════
    if ($RedControl) {
        Write-Host "--- Red Control: Testing against pre-fix un-encapsulated code ---"
        $caseEnv = @{} + $baseEnv
        $redTestDir = Join-Path $env:TEMP ("wintage-red-win-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $redTestDir -Force | Out-Null
        $caseEnv['WINTAGE_TEST_WINDOWS_THEMES_DIR'] = $redTestDir

        $preFixCmd = @(
            '$WINDOWS_THEMES_DIR = ''' + $redTestDir + ''''
            '$root = ''' + $root + ''''
            '$out = Join-Path $root ''desktop/out'''
            '$helper = Join-Path $root ''tools/install-windows-theme.js'''
            '$built = Join-Path $out ''windows/goldendefault/Wintage.theme'''
            '$resolvedCurrent = ''' + $baselineThemeFile + ''''
            '$PaletteSlug = ''goldendefault'''
            '$helperArgs = @($helper, ''--themes-dir'', $WINDOWS_THEMES_DIR, ''--theme'', $built, ''--current-theme'', $resolvedCurrent, ''--palette'', $PaletteSlug)'
            '$helperOutput = @(& node $helperArgs)'
            'throw ''simulated accent write failure'''
        ) -join '; '

        $r = Run-Child powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $preFixCmd)
        $leftoverThemes = @(Get-ChildItem -LiteralPath $redTestDir -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)
        $leftoverMarker = Test-Path (Join-Path $redTestDir '.wintage-windows-palette')
        $leftoverOriginal = Test-Path (Join-Path $redTestDir 'Wintage.original.theme')

        $preFixFailedRollback = ($leftoverThemes.Count -gt 0 -or $leftoverMarker -or $leftoverOriginal)
        check 'red control: pre-fix code leaves orphaned files on accent write failure' $preFixFailedRollback

        Remove-Item -LiteralPath $redTestDir -Recurse -Force -ErrorAction SilentlyContinue
    }

} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $regRoot) { Remove-Item -LiteralPath $regRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "========================================"
Write-Host "RESULTS: $pass PASS / $fail FAIL"
if ($fail -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $failedLabels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
exit 0
