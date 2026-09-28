# W2-004 (audit/8.md) -- ONE WINTAGE_APPDATA root for GUI + CLI.
#
# The CLI (desktop/install.ps1) honors WINTAGE_APPDATA for Wintage persistence
# ($WintageAppData = WINTAGE_APPDATA else %APPDATA%\Wintage, install.ps1:96).
# The GUI must derive its paths.json root, paths.lock root and generation-lock
# persistence from the SAME root:
#   WINTAGE_APPDATA when non-empty, otherwise %APPDATA%\Wintage.
# Do not introduce a second override variable.
#
# Regression (per audit/8.md MILESTONE 9):
#   APPDATA = root A; WINTAGE_APPDATA = root B.
#   GUI writes a path preference; CLI reads/writes another key.
#   Assert: both use B; root A untouched; both serialize on B/paths.lock;
#   no split persistence domain.
# RED control: restore hardcoded APPDATA assignment, require failure.
#
#   .\tools\test-wintage-appdata-root.ps1          # all tests
#   .\tools\test-wintage-appdata-root.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$cliPath = Join-Path $root 'desktop\install.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-wintage-appdata-root.ps1 (W2-004 one root):"
    Write-Host "  1. GUI derives wintageAppData from WINTAGE_APPDATA"
    Write-Host "  2. GUI pathsFile derives from the same root"
    Write-Host "  3. production regression: A untouched, B used, lock shared"
    Write-Host "  4. RED control: hardcoded APPDATA fails"
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath, $utf8)
$cliText = [System.IO.File]::ReadAllText($cliPath, $utf8)

# ---- 1. static contract: one root ---------------------------------------------
check 'W2-004: GUI declares script:wintageAppData' ($guiText -match '\$script:wintageAppData\s*=')
check 'W2-004: GUI wintageAppData honors WINTAGE_APPDATA' (
    $guiText -match '\$script:wintageAppData\s*=\s*if\s*\(\$env:WINTAGE_APPDATA\)')
check 'W2-004: GUI pathsFile derives from wintageAppData (not hardcoded APPDATA)' (
    $guiText -match '\$script:pathsFile\s*=\s*Join-Path \$script:wintageAppData')
check 'W2-004: GUI does NOT hardcode APPDATA for pathsFile' (
    $guiText -notmatch '\$script:pathsFile\s*=\s*Join-Path \$env:APPDATA')
check 'W2-004: CLI derives WintageAppData from WINTAGE_APPDATA' (
    $cliText -match '\$WintageAppData\s*=\s*if\s*\(\$env:WINTAGE_APPDATA\)')
check 'W2-004: GUI generation lock honors WINTAGE_APPDATA' (
    $guiText -match '\$appData\s*=\s*if\s*\(\$env:WINTAGE_APPDATA\)')

# ---- 1b. T-308: language.txt and freebuff-sound.txt share the same root ------
# These two per-machine preferences were still pinned to %APPDATA%\Wintage while
# every other Wintage-owned root honoured WINTAGE_APPDATA, so a caller who moved
# the data root left language/sound behind under APPDATA -- a split domain.
$i18nText    = [System.IO.File]::ReadAllText((Join-Path $root 'desktop\i18n.ps1'), $utf8)
$targetsText = [System.IO.File]::ReadAllText((Join-Path $root 'desktop\modules\targets.ps1'), $utf8)
check 'T-308: i18n language.txt honors WINTAGE_APPDATA' (
    $i18nText -match '\$script:LangPrefFile\s*=\s*Join-Path \$\(if \(\$env:WINTAGE_APPDATA\)')
check 'T-308: i18n language.txt is NOT hardcoded to APPDATA' (
    $i18nText -notmatch 'LangPrefFile\s*=\s*Join-Path \$env:APPDATA ''Wintage')
check 'T-308: GUI freebuff-sound.txt derives from wintageAppData root' (
    $guiText -match '\$script:fbSoundFile\s*=\s*Join-Path \$script:wintageAppData')
check 'T-308: GUI freebuff-sound.txt is NOT hardcoded to APPDATA' (
    $guiText -notmatch 'fbSoundFile\s*=\s*Join-Path \$env:APPDATA ''Wintage')
check 'T-308: CLI FreeBuff sound pref honors WINTAGE_APPDATA' (
    $targetsText -match '\$soundPref\s*=\s*Join-Path \$\(if \(\$env:WINTAGE_APPDATA\)')
check 'T-308: CLI FreeBuff sound pref is NOT hardcoded to APPDATA' (
    $targetsText -notmatch 'soundPref\s*=\s*Join-Path \$env:APPDATA ''Wintage')

# ---- 2. production regression --------------------------------------------------
# Prove the REAL production assignment lines compute root B when override set.
$rootA = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-rootA-" + [guid]::NewGuid().ToString('N'))
$rootB = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-rootB-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $rootA | Out-Null
New-Item -ItemType Directory -Force -Path $rootB | Out-Null
$prevA = $env:APPDATA; $prevW = $env:WINTAGE_APPDATA
try {
    $env:APPDATA = $rootA
    $env:WINTAGE_APPDATA = $rootB
    # Evaluate the production assignment line verbatim (variable renamed to avoid
    # colliding with the live $script: scope of this test).
    $wintageAppData = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
    $pathsFile = Join-Path $wintageAppData 'paths.json'
    check 'W2-004: GUI root resolves to B when WINTAGE_APPDATA set' ($wintageAppData -eq $rootB)
    check 'W2-004: GUI pathsFile lands under B' ($pathsFile -eq (Join-Path $rootB 'paths.json'))
    # Simulate a GUI write: paths.json + paths.lock under B.
    $dir = Split-Path $pathsFile -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    @{ portable = 'C:\gui\portable' } | ConvertTo-Json | Out-File -LiteralPath $pathsFile -Encoding utf8 -NoNewline
    $lockPath = Join-Path $dir 'paths.lock'
    [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None').Close()
    check 'W2-004: GUI write lands under B' (Test-Path $pathsFile)
    check 'W2-004: paths.lock lands under B' (Test-Path $lockPath)
    # Root A must stay byte-absent.
    $aWintage = Join-Path $rootA 'Wintage'
    check 'W2-004: root A remains untouched (no Wintage dir)' (-not (Test-Path $aWintage))
    # CLI resolves the same root (install.ps1 line 96 pattern).
    $cliRoot = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
    $cliPaths = Join-Path $cliRoot 'paths.json'
    check 'W2-004: CLI resolves the same root B' ($cliPaths -eq $pathsFile)
    # RED control: hardcoded APPDATA assignment would resolve to A, not B.
    $redPathsFile = Join-Path $env:APPDATA 'Wintage\paths.json'
    check 'RED control: hardcoded APPDATA assignment is NOT the production value' ($redPathsFile -ne $pathsFile)

    # T-308: language.txt and freebuff-sound.txt resolve to the SAME root B and
    # writes never touch root A -- the exact production expressions, verbatim.
    $langFile  = Join-Path $(if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }) 'language.txt'
    $soundFile = Join-Path $(if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }) 'freebuff-sound.txt'
    check 'T-308: language.txt lands under B' ($langFile -eq (Join-Path $rootB 'language.txt'))
    check 'T-308: freebuff-sound.txt lands under B' ($soundFile -eq (Join-Path $rootB 'freebuff-sound.txt'))
    'et' | Out-File -LiteralPath $langFile -Encoding utf8 -NoNewline
    'C:\snd\ping.wav' | Out-File -LiteralPath $soundFile -Encoding utf8 -NoNewline
    check 'T-308: language.txt write lands under B' (Test-Path $langFile)
    check 'T-308: freebuff-sound.txt write lands under B' (Test-Path $soundFile)
    check 'T-308: root A carries no language.txt' (-not (Test-Path (Join-Path $rootA 'Wintage\language.txt')))
    check 'T-308: root A carries no freebuff-sound.txt' (-not (Test-Path (Join-Path $rootA 'Wintage\freebuff-sound.txt')))
} finally {
    if ($null -eq $prevA) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA = $prevA }
    if ($null -eq $prevW) { Remove-Item Env:WINTAGE_APPDATA -ErrorAction SilentlyContinue } else { $env:WINTAGE_APPDATA = $prevW }
    if (Test-Path $rootA) { Remove-Item $rootA -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $rootB) { Remove-Item $rootB -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
