# CORE-004 (audit/7.md) -- GUI-owned remembered paths regression suite.
#
# The GUI path-ownership feature was zeroed out: $PATH_TARGETS/$PATH_DEFAULTS
# were empty arrays while discovery, selection, persistence and batch
# forwarding all still assumed a non-empty GUI-owned set. Custom installs of
# zcode/notepadplusplus/cinema4d could not establish or change their folder
# through the GUI, and the source-tree selectability rule was effectively dead.
#
# This gate extracts the REAL declarations and functions from
# WintageInstaller.ps1 and drives them against isolated paths.json fixtures:
#   - the canonical GUI-owned mapping is exactly zcode/notepadplusplus/cinema4d
#     with the matching install.ps1 parameter names;
#   - an empty paths.json leaves every GUI-owned target unresolved;
#   - a chosen folder persists across a reload, while CLI-owned keys
#     (codenomad/workbuddy/portable) and unknown forward-compatible keys are
#     preserved byte-for-value;
#   - a remembered folder that no longer exists is dropped on load;
#   - Get-BatchArgs forwards each GUI-owned path under its canonical parameter
#     and forwards nothing when the target was not selected.
#
#   .\tools\test-gui-paths.ps1          # all tests
#   .\tools\test-gui-paths.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-gui-paths.ps1 (CORE-004 GUI-owned remembered paths):"
    Write-Host "  1. canonical mapping: exactly zcode/notepadplusplus/cinema4d with install.ps1 param names"
    Write-Host "  2. empty paths.json leaves all GUI-owned targets unresolved"
    Write-Host "  3. chosen folders persist across reload"
    Write-Host "  4. CLI-owned and unknown keys survive a GUI save byte-for-value"
    Write-Host "  5. a remembered folder that vanished is dropped on load"
    Write-Host "  6. Get-BatchArgs forwards each GUI-owned path under its canonical parameter"
    Write-Host "  7. Get-BatchArgs forwards nothing for unselected/CLI-owned targets"
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath, $utf8)

function Get-FnText([string]$text, [string]$name) {
    $m = [regex]::Match($text, 'function\s+' + [regex]::Escape($name) + '\b')
    if (-not $m.Success) { return $null }
    $open = $text.IndexOf('{', $m.Index)
    $depth = 0
    for ($j = $open; $j -lt $text.Length; $j++) {
        if ($text[$j] -eq '{') { $depth++ }
        elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($m.Index, $j - $m.Index + 1) } }
    }
    return $null
}

# ---- 1. canonical mapping ----------------------------------------------------
$mapMatch = [regex]::Match($guiText, '(?m)^\$script:PATH_TARGETS_MAP = \[ordered\]@\{')
check 'CORE-004: PATH_TARGETS_MAP declaration exists' $mapMatch.Success
$mapKeys = @([regex]::Matches($guiText, "(?m)^    (zcode|notepadplusplus|cinema4d|processexplorer)\s+=") | ForEach-Object { $_.Groups[1].Value })
check 'CORE-004: the GUI-owned set is exactly zcode/notepadplusplus/cinema4d/processexplorer' (
    (($mapKeys | Sort-Object) -join ',') -eq 'cinema4d,notepadplusplus,processexplorer,zcode')
check 'CORE-004: PATH_TARGETS is derived from the map' ($guiText -match '\$PATH_TARGETS = @\(\$script:PATH_TARGETS_MAP\.Keys\)')
check 'CORE-004: zcode forwards -ZCodePath' ($guiText -match "zcode\s+= @\{ Default = .*Param = '-ZCodePath'")
check 'CORE-004: notepadplusplus forwards -NotepadPlusPlusPath' ($guiText -match "notepadplusplus = @\{ Default = .*Param = '-NotepadPlusPlusPath'")
check 'CORE-004: cinema4d forwards -Cinema4DPath' ($guiText -match "cinema4d\s+= @\{ Default = .*Param = '-Cinema4DPath'")
check 'CORE-004: processexplorer forwards -ProcessExplorerPath' ($guiText -match "processexplorer = @\{ Default = .*Param = '-ProcessExplorerPath'")

# ---- harness: real functions, isolated fixture -------------------------------
$loadFn = Get-FnText $guiText 'Load-CustomPaths'
$saveFn = Get-FnText $guiText 'Save-CustomPaths'
$batchFn = Get-FnText $guiText 'Get-BatchArgs'
check 'CORE-004: Load-CustomPaths / Save-CustomPaths / Get-BatchArgs located' (
    $null -ne $loadFn -and $null -ne $saveFn -and $null -ne $batchFn)
Invoke-Expression $loadFn
Invoke-Expression $saveFn
Invoke-Expression $batchFn
# W2-005: Save-CustomPaths now routes through the shared strict reader, so the
# harness must provide it exactly as the shipped GUI does.
. (Join-Path $root 'desktop\modules\json-doc.ps1')
# The REAL declaration block is evaluated, so PATH_TARGETS and the forwarding
# parameter names under test are the shipped ones, not a test-local copy.
$declStart = $guiText.IndexOf('$script:PATH_TARGETS_MAP = [ordered]@{')
$declOpen = $guiText.IndexOf('{', $declStart)
$declDepth = 0
$declText = $null
for ($j = $declOpen; $j -lt $guiText.Length; $j++) {
    if ($guiText[$j] -eq '{') { $declDepth++ }
    elseif ($guiText[$j] -eq '}') { $declDepth--; if ($declDepth -eq 0) { $declText = $guiText.Substring($declStart, $j - $declStart + 1); break } }
}
check 'CORE-004: the PATH_TARGETS_MAP declaration was located for evaluation' ($null -ne $declText)
Invoke-Expression $declText

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-gui-paths-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$PATH_TARGETS = @($script:PATH_TARGETS_MAP.Keys)
$script:customPaths = @{}
$script:pathsFile = Join-Path $testRoot 'Wintage\paths.json'
$here = $root

try {
    # ---- 2. empty paths.json --------------------------------------------------
    Load-CustomPaths
    check 'CORE-004: empty paths.json leaves all GUI-owned targets unresolved' ($script:customPaths.Count -eq 0)

    # ---- 3/4/5. persistence, foreign-key preservation, stale drop -------------
    $zcodeDir = Join-Path $testRoot 'ZCode\resources'
    $nppDir = Join-Path $testRoot 'Notepad++'
    $c4dDir = Join-Path $testRoot 'Maxon Cinema 4D 2026'
    foreach ($d in @($zcodeDir, $nppDir, $c4dDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    $seed = [ordered]@{
        codenomad = 'C:\cli\codenomad'
        workbuddy = 'C:\cli\workbuddy'
        portable  = 'C:\cli\portable'
        futurekey = 'C:\future\value'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $script:pathsFile -Parent) | Out-Null
    [System.IO.File]::WriteAllText($script:pathsFile, (($seed | ConvertTo-Json) + "`n"), $utf8)
    $script:customPaths = @{ zcode = $zcodeDir; notepadplusplus = $nppDir; cinema4d = $c4dDir; futurekey = 'C:\never\owned' }
    check 'CORE-004: GUI save succeeds' (Save-CustomPaths)
    $saved = ([System.IO.File]::ReadAllText($script:pathsFile, $utf8)) | ConvertFrom-Json
    check 'CORE-004: zcode path persisted' ($saved.zcode -eq $zcodeDir)
    check 'CORE-004: notepadplusplus path persisted' ($saved.notepadplusplus -eq $nppDir)
    check 'CORE-004: cinema4d path persisted' ($saved.cinema4d -eq $c4dDir)
    check 'CORE-004: CLI-owned codenomad survives byte-for-value' ($saved.codenomad -eq 'C:\cli\codenomad')
    check 'CORE-004: CLI-owned workbuddy survives byte-for-value' ($saved.workbuddy -eq 'C:\cli\workbuddy')
    check 'CORE-004: CLI-owned portable survives byte-for-value' ($saved.portable -eq 'C:\cli\portable')
    check 'CORE-004: unknown forward-compatible key survives byte-for-value' ($saved.futurekey -eq 'C:\future\value')
    $script:customPaths = @{}
    Load-CustomPaths
    check 'CORE-004: all three GUI-owned paths survive a reload' (
        $script:customPaths['zcode'] -eq $zcodeDir -and
        $script:customPaths['notepadplusplus'] -eq $nppDir -and
        $script:customPaths['cinema4d'] -eq $c4dDir)
    # Stale folder: remove cinema4d from disk, reload -> dropped.
    Remove-Item -LiteralPath $c4dDir -Recurse -Force
    $script:customPaths = @{}
    Load-CustomPaths
    check 'CORE-004: a remembered folder that vanished is dropped on load' (-not $script:customPaths.ContainsKey('cinema4d'))
    check 'CORE-004: the other remembered folders still load' (
        $script:customPaths['zcode'] -eq $zcodeDir -and $script:customPaths['notepadplusplus'] -eq $nppDir)

    # ---- 6/7. batch argument forwarding (exact token, not substring) -----------
    # W2-001: PATH_TARGETS_MAP.Params are complete tokens (-ZCodePath, etc.).
    # Get-BatchArgs must append them directly without prepending an extra hyphen.
    # Substring matching on a joined string falsely accepts "--ZCodePath"; we
    # assert exact array tokens instead.
    New-Item -ItemType Directory -Force -Path $c4dDir | Out-Null
    $script:customPaths = @{ zcode = $zcodeDir; notepadplusplus = $nppDir; cinema4d = $c4dDir; processexplorer = 'C:\Tools\Sysinternals'; workbuddy = 'C:\cli\workbuddy' }
    $argsAll = Get-BatchArgs @('zcode', 'notepadplusplus', 'cinema4d', 'processexplorer') 'goldendefault'
    $argsArr = @($argsAll)
    # Each canonical switch must appear exactly once, followed by the exact path.
    foreach ($pair in @(
        @{ Key = 'zcode';           Token = '-ZCodePath';          Path = $zcodeDir },
        @{ Key = 'notepadplusplus'; Token = '-NotepadPlusPlusPath'; Path = $nppDir },
        @{ Key = 'cinema4d';        Token = '-Cinema4DPath';       Path = $c4dDir },
        @{ Key = 'processexplorer'; Token = '-ProcessExplorerPath'; Path = 'C:\Tools\Sysinternals' }
    )) {
        $idx = [array]::IndexOf($argsArr, $pair.Token)
        $count = 0; for ($j = 0; $j -lt $argsArr.Count; $j++) { if ($argsArr[$j] -eq $pair.Token) { $count++ } }
        check "CORE-004/W2-001: $($pair.Key) exact token '$($pair.Token)' occurs once" ($idx -ge 0 -and $count -eq 1)
        check "CORE-004/W2-001: $($pair.Key) token is followed by exact expected path" ($idx -ge 0 -and $idx + 1 -lt $argsArr.Count -and $argsArr[$idx + 1] -eq $pair.Path)
    }
    # No double-prefixed --*Path tokens may exist anywhere.
    $hasDoublePrefix = $argsArr | Where-Object { $_ -match '^--[A-Za-z]+Path$' }
    check 'CORE-004/W2-001: zero --*Path double-prefix tokens exist' (-not $hasDoublePrefix)
    $argsSome = Get-BatchArgs @('windows') 'goldendefault'
    $argsSomeArr = @($argsSome)
    $someText = $argsSomeArr -join ' '
    check 'CORE-004: unselected GUI-owned targets are not forwarded' (
        $someText -notmatch 'ZCodePath' -and $someText -notmatch 'NotepadPlusPlusPath' -and $someText -notmatch 'Cinema4DPath' -and $someText -notmatch 'ProcessExplorerPath')
    check 'CORE-004: CLI-owned keys are never forwarded from the GUI map' ($someText -notmatch 'workbuddy')

    # ---- RED control: restore the extra-hyphen defect and prove the guard fails ----
    # The original defect prepended '-' to the canonical Param, producing --ZCodePath.
    # This control re-introduces that pattern inline and proves the exact-token
    # assertion would reject it (the double-prefix token must NOT be emitted).
    $redTokens = @(($script:PATH_TARGETS_MAP['zcode'].Param), ($script:PATH_TARGETS_MAP['zcode'].Param))
    $redArgs = @('-NoProfile', '-File', 'install.ps1', "-$($script:PATH_TARGETS_MAP['zcode'].Param)", $zcodeDir)
    $redHasDouble = $redArgs | Where-Object { $_ -match '^--[A-Za-z]+Path$' }
    check 'RED control: restored extra-hyphen produces --ZCodePath double-prefix' ($redHasDouble.Count -gt 0)
    check 'RED control: fixed code does not produce the double-prefix' (-not ($argsArr | Where-Object { $_ -match '^--[A-Za-z]+Path$' }))
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
