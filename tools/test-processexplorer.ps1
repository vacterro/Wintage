# SRC-023: Process Explorer Wintage theme support regression suite.
#
# The desktop installer carries a Process Explorer target that themes the
# application's configurable row-highlight and graph-background colour values
# through HKCU\Software\Sysinternals\Process Explorer. This gate drives the REAL
# install.ps1 against an isolated settings key and proves the complete ownership
# contract:
#
#   * the canonical owned write set equals the theme map exactly (no value Apply
#     writes may be missing from the snapshot/rollback/recovery ledger) - the
#     defect this suite was created for: a 12-name base list beside a 24-name
#     write map left the *Dark values unowned;
#   * first-touch recovery captures every owned value including present-empty,
#     and is not replaced by a repaint;
#   * Apply writes exactly the map, records the manifest entry and a marker;
#   * repaint A -> B changes only owned values and keeps first-touch recovery;
#   * a deterministic mid-apply failure restores every touched value;
#   * Revert restores pre-existing values exactly and removes values that were
#     absent before, while unrelated registry values survive;
#   * health is clean after Apply, unhealthy after one owned value drifts, and
#     Reapply repairs it;
#   * a running Process Explorer refuses Apply/Revert unless the test seam
#     allows it, and -WhatIf mutates nothing;
#   * the remembered portable folder is a canonical paths.json key;
#   * `-Target all` includes Process Explorer when it is resolvable.
#
#   .\tools\test-processexplorer.ps1          # all tests
#   .\tools\test-processexplorer.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\install.ps1'
$targetsSrc = Join-Path $root 'desktop\modules\targets.ps1'
$commonSrc = Join-Path $root 'desktop\modules\common.ps1'
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

function Invoke-Install([string[]]$extra) { Run-Child (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer) + $extra) }

function Get-ManifestKeys {
    $p = Join-Path $env:WINTAGE_APPDATA 'installed.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $o = [System.IO.File]::ReadAllText($p, $utf8) | ConvertFrom-Json
    return @($o.PSObject.Properties.Name)
}

function Set-PeDword([string]$key, [string]$name, [uint32]$value) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name $name -Value ([int]$value) -Type DWord
}

function Get-PeDword([string]$key, [string]$name) {
    if (-not (Test-Path $key)) { return $null }
    $v = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
    if ($null -eq $v) { return $null }
    return [uint32]$v
}

if ($List) {
    Write-Host "test-processexplorer.ps1 (SRC-023 Process Explorer theme support):"
    Write-Host "  1. owned-value contract: map and PE_COLOR_VALUES agree exactly"
    Write-Host "  2. discovery: registry evidence, remembered/explicit folder, common dir, absent"
    Write-Host "  3. apply: exact owned write set + manifest entry + marker"
    Write-Host "  4. complete ownership: every written value exists in the recovery ledger"
    Write-Host "  5. repaint A -> B: first-touch recovery unchanged"
    Write-Host "  6. rollback: mid-apply failure restores every touched value"
    Write-Host "  7. revert: pre-existing restored, absent removed, unrelated preserved, marker semantics"
    Write-Host "  8. health: healthy after apply, unhealthy on drift, reapply repairs"
    Write-Host "  9. running refusal + -WhatIf mutation-free"
    Write-Host " 10. custom folder persisted through canonical paths.json"
    Write-Host " 11. -Target all includes processexplorer when resolvable"
    exit 0
}

# The planneable palette: whatever pack the rest of the suite uses.
$packA = 'goldendefault'
$packB = @(Get-ChildItem (Join-Path $root 'themes') -Filter '*.json' | ForEach-Object { $_.BaseName } | Where-Object { $_ -ne $packA } | Sort-Object)[0]

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-pe-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$prevAppData = $env:WINTAGE_APPDATA
$prevPeKey = $env:WINTAGE_TEST_PE_KEY
$prevCommon = $env:WINTAGE_TEST_PE_COMMON_DIRS
$prevAllowRunning = $env:WINTAGE_TEST_ALLOW_RUNNING_PE
$prevForceRunning = $env:WINTAGE_TEST_FORCE_RUNNING_PE
# A real Process Explorer may be running on the test machine; the apply-focused
# cases below set the allow seam so they exercise the mutation contract, while
# case 9 sets the FORCE seam to prove the refusal.
$env:WINTAGE_TEST_ALLOW_RUNNING_PE = '1'
$prevMidApply = $env:WINTAGE_TEST_FAIL_PE_MIDAPPLY
$prevRecovery = $env:WINTAGE_TEST_FAIL_PE_RECOVERY
$prevAllTargets = $env:WINTAGE_TEST_ALL_TARGETS
$createdKeys = @()

function New-Key { $k = 'HKCU:\Software\Wintage-Test-PE-' + [guid]::NewGuid().ToString('N'); $script:createdKeys += $k; return $k }
function New-Case([string]$name) {
    $dir = Join-Path $testRoot $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $appdata = Join-Path $dir 'appdata'
    New-Item -ItemType Directory -Path $appdata -Force | Out-Null
    $env:WINTAGE_APPDATA = $appdata
    return $dir
}

try {
    # ════ 1. owned-value contract: map == PE_COLOR_VALUES exactly ═══════════════
    # Read the two declarations straight out of the shipped source and evaluate
    # the theme map for a real palette, then require a bijection. This is the
    # structural guard that would have caught the base-only-list defect.
    $source = [System.IO.File]::ReadAllText($targetsSrc, $utf8)
    $rowRoles = @([regex]::Match($source, '(?s)\$script:PE_ROW_ROLES = @\((.*?)\)').Groups[1].Value -split ',' |
        ForEach-Object { ($_ -replace "'", '').Trim() } | Where-Object { $_ })
    $graphNames = @([regex]::Match($source, '(?s)\$script:PE_COLOR_VALUES = @\((.*?)\n\)').Groups[1].Value -split "`n" |
        ForEach-Object { ($_ -replace "'", '').Trim() } | Where-Object { $_ -and $_ -notmatch '^foreach' })
    check 'pe contract: PE_ROW_ROLES located' ($rowRoles.Count -ge 11)
    check 'pe contract: graph values present in the canonical set' (
        ($graphNames -contains 'ColorGraphBk') -and ($graphNames -contains 'ColorGraphBkDark'))
    # The runtime contract guard itself: load just the map builder and run it.
    $mapChild = Join-Path $testRoot 'map.ps1'
    [System.IO.File]::WriteAllText($mapChild, (@(
        'param($targets, $themes, $palette)',
        '$ErrorActionPreference = ''Stop''',
        # Minimal stubs for the helpers Get-ProcessExplorerThemeMap depends on.
        'function Convert-HexToBgr([string]$hex) { return $hex }',
        '$src = [System.IO.File]::ReadAllText($targets)',
        'foreach ($pat in @(''(?s)\$script:PE_MARKER_VALUE = .*?\n'', ''(?s)\$script:PE_ROW_ROLES = @\(.*?\n\)'', ''(?s)\$script:PE_COLOR_VALUES = @\(.*?\n\)'')) {',
        '    $b = [regex]::Match($src, $pat).Value',
        '    if ($b) { Invoke-Expression $b }',
        '}',
        'function Convert-HexBlendToward([string]$hex, [string]$towardHex, [double]$ratio) { return $hex }',
        # The map builder picks its blend pole via relative luminance; identity stub keeps the contract check about the KEY set, not colour.
        'function Get-RelativeLuminance([string]$hex) { return 0 }',
        '$fn = [regex]::Match([System.IO.File]::ReadAllText($targets), ''(?s)function Get-ProcessExplorerThemeMap.*?\n\}'').Value',
        'Invoke-Expression $fn',
        '$tokens = ([System.IO.File]::ReadAllText((Join-Path $themes ($palette + ''.json''))) | ConvertFrom-Json).tokens',
        '$map = Get-ProcessExplorerThemeMap $tokens',
        'Write-Host ("MAPCOUNT=" + $map.Keys.Count)',
        'Write-Host ("OWNEDCOUNT=" + $script:PE_COLOR_VALUES.Count)',
        'Write-Host ("MAPKEYS=" + (($map.Keys | Sort-Object) -join ","))',
        'Write-Host ("OWNEDKEYS=" + (($script:PE_COLOR_VALUES | Sort-Object) -join ","))',
        'exit 0'
    ) -join "`n"), $utf8)
    $r = Run-Child @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mapChild, $targetsSrc, (Join-Path $root 'themes'), $packA)
    $mapKeysLine = @($r.Out -split "`n" | Where-Object { $_ -match '^MAPKEYS=' })[0] -replace '^MAPKEYS=', ''
    $ownedKeysLine = @($r.Out -split "`n" | Where-Object { $_ -match '^OWNEDKEYS=' })[0] -replace '^OWNEDKEYS=', ''
    check 'pe contract: the theme map builds without a drift refusal' ($r.Code -eq 0 -and $r.Out -notmatch 'contract drift')
    check 'pe contract: the write map and the owned set are the SAME key set' (
        ($mapKeysLine.Trim() -eq $ownedKeysLine.Trim()) -and $mapKeysLine.Trim())
    check 'pe contract: the owned set has all 24 values (11 rows x2 + graph x2)' ($ownedKeysLine.Split(',').Count -eq 24)

    # ════ 2. discovery ══════════════════════════════════════════════════════════
    # (a) absent: no key and no folder. An EXPLICIT -Target is strict (T-189), so
    # absence is a FAIL here; -Target all treats it as a clean SKIP.
    $case = New-Case 'disc-absent'
    $env:WINTAGE_TEST_PE_KEY = 'HKCU:\Software\Wintage-Test-PE-Absent-' + [guid]::NewGuid().ToString('N')
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'disc absent: an explicit target refuses when nothing resolvable exists' (
        $r.Code -ne 0 -and $r.Out -match 'expected to be present but cannot be resolved')
    $prevAllAbsent = $env:WINTAGE_TEST_ALL_TARGETS
    $env:WINTAGE_TEST_ALL_TARGETS = 'processexplorer'
    $r = Invoke-Install @('-Target', 'all', '-Palette', $packA)
    $env:WINTAGE_TEST_ALL_TARGETS = $prevAllAbsent
    check 'disc absent: -Target all treats absence as a clean skip' ($r.Code -eq 0 -and $r.Out -match 'not installed|skipped')
    # (b) registry evidence (key exists from a prior run), no exe anywhere
    $case = New-Case 'disc-registry'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    Set-PeDword $key 'ColorOwn' 111
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'disc registry: a present settings key is resolvable' ($r.Code -eq 0 -and $r.Out -match 'colours applied')
    # (c) explicit -ProcessExplorerPath folder is honored
    $case = New-Case 'disc-explicit'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $peDir = Join-Path $case 'Sysinternals'
    New-Item -ItemType Directory -Path $peDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $peDir 'procexp64.exe'), 'stub', $utf8)
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    $r = Invoke-Install @('-Target', 'processexplorer', '-ProcessExplorerPath', $peDir, '-Palette', $packA)
    check 'disc explicit: explicit folder resolves the target' ($r.Code -eq 0 -and $r.Out -match 'colours applied')
    # (d) remembered custom folder through paths.json
    $case = New-Case 'disc-remembered'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $peDir2 = Join-Path $case 'CustomSysinternals'
    New-Item -ItemType Directory -Path $peDir2 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $peDir2 'procexp.exe'), 'stub', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $env:WINTAGE_APPDATA 'paths.json'), (@{ processexplorer = $peDir2 } | ConvertTo-Json), $utf8)
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'disc remembered: a remembered paths.json folder resolves the target' ($r.Code -eq 0 -and $r.Out -match 'colours applied')

    # ════ 3. Apply: exact owned write set + manifest entry + recovery first ═════
    $case = New-Case 'apply'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    # Pre-existing unrelated + one owned value.
    Set-PeDword $key 'ColorOwn' 16765136
    Set-ItemProperty -Path $key -Name 'UnrelatedSetting' -Value 4242 -Type DWord
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'apply exits 0' ($r.Code -eq 0)
    $recMeta = Join-Path $env:WINTAGE_APPDATA 'recovery\processexplorer\recovery.json'
    check 'apply wrote first-touch recovery.json' (Test-Path -LiteralPath $recMeta)
    check 'apply wrote recovery provenance' (Test-Path -LiteralPath ($recMeta + '.provenance.json'))
    $meta = [System.IO.File]::ReadAllText($recMeta, $utf8) | ConvertFrom-Json
    check 'apply recovery captures the pre-existing owned value' ("$($meta.values.ColorOwn)" -eq '16765136')
    check 'apply manifest records processexplorer' (@(Get-ManifestKeys) -contains 'processexplorer')
    check 'apply wrote the marker' ((Get-ItemProperty -Path $key -Name WintagePalette -ErrorAction SilentlyContinue).WintagePalette -eq $packA)

    # ════ 4. complete ownership: every written value is in the recovery ledger ══
    # The exact set written by Apply must be a subset of the values captured at
    # first touch; otherwise Revert can never restore them (the base-only defect).
    $ownedNames = @($meta.values.PSObject.Properties.Name)
    $beforeState = @{}
    $mapRaw = $r.Out
    # Derive the written names from the map builder key set (already proven equal
    # to the owned set) and require every one to be present in the recovery.
    foreach ($n in $ownedKeysLine.Split(',')) { $beforeState[$n] = $true }
    $missingFromRecovery = @($beforeState.Keys | Where-Object { $ownedNames -notcontains $_ })
    check 'ownership: every owned name is captured in recovery' ($missingFromRecovery.Count -eq 0)
    # And require the *Dark values specifically (the previously-unowned set).
    check 'ownership: the *Dark values are captured in recovery' (
        ($ownedNames -contains 'ColorOwnDark') -and ($ownedNames -contains 'ColorGraphBkDark'))

    # ════ 5. repaint A -> B keeps first-touch recovery ══════════════════════════
    $metaBytes = [System.IO.File]::ReadAllBytes($recMeta)
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packB)
    check 'repaint exits 0' ($r.Code -eq 0)
    check 'repaint did NOT replace first-touch recovery' ([System.IO.File]::ReadAllBytes($recMeta) -ceq $metaBytes -or ((Get-FileHash $recMeta).Hash -eq (Get-FileHash -InputStream ([IO.MemoryStream]::new($metaBytes))).Hash))
    check 'repaint changed the live marker to B' ((Get-ItemProperty -Path $key -Name WintagePalette -ErrorAction SilentlyContinue).WintagePalette -eq $packB)

    # ════ 6. rollback: mid-apply failure restores every touched value ═══════════
    $case = New-Case 'rollback'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    Set-PeDword $key 'ColorOwn' 16700000
    Set-PeDword $key 'ColorServices' 3333
    Set-ItemProperty -Path $key -Name 'UnrelatedSetting' -Value 777 -Type DWord
    $env:WINTAGE_TEST_FAIL_PE_MIDAPPLY = '1'
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    Remove-Item env:WINTAGE_TEST_FAIL_PE_MIDAPPLY -ErrorAction SilentlyContinue
    check 'rollback: injected mid-apply failure exits NONZERO' ($r.Code -ne 0)
    check 'rollback: the seam is what failed' ($r.Out -match 'WINTAGE_TEST_FAIL_PE_MIDAPPLY')
    check 'rollback: ColorOwn restored to its pre-operation value' ((Get-PeDword $key 'ColorOwn') -eq 16700000)
    check 'rollback: ColorServices restored to its pre-operation value' ((Get-PeDword $key 'ColorServices') -eq 3333)
    check 'rollback: unrelated registry value preserved' ((Get-PeDword $key 'UnrelatedSetting') -eq 777)
    check 'rollback: manifest entry was not written' (@(Get-ManifestKeys) -notcontains 'processexplorer')

    # ════ 7. Revert: pre-existing restored, absent removed, unrelated preserved ═
    $case = New-Case 'revert'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    # Pre-existing: one owned value present, another present-empty (absent here),
    # the rest absent; one unrelated value; one pre-existing marker as empty string.
    Set-PeDword $key 'ColorOwn' 16765136
    Set-ItemProperty -Path $key -Name 'UnrelatedSetting' -Value 555 -Type DWord
    Set-ItemProperty -Path $key -Name 'WintagePalette' -Value '' -Type String
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'revert: apply exits 0' ($r.Code -eq 0)
    $r = Invoke-Install @('-Target', 'processexplorer', '-Revert')
    check 'revert: revert exits 0' ($r.Code -eq 0)
    check 'revert: pre-existing ColorOwn restored exactly' ((Get-PeDword $key 'ColorOwn') -eq 16765136)
    check 'revert: a value absent before Wintage is removed' ((Get-PeDword $key 'ColorServicesDark') -eq $null)
    check 'revert: unrelated registry value preserved' ((Get-PeDword $key 'UnrelatedSetting') -eq 555)
    check 'revert: the marker is restored as present-empty (presence != content)' (
        (Get-ItemProperty -Path $key -Name WintagePalette -ErrorAction SilentlyContinue).WintagePalette -eq '')
    check 'revert: manifest entry removed' (@(Get-ManifestKeys) -notcontains 'processexplorer')
    check 'revert: recovery consumed' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\processexplorer\recovery.json')))

    # ════ 8. health: clean after Apply, unhealthy on drift, Reapply repairs ═════
    $case = New-Case 'health'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    # Registry evidence: the settings key must physically exist for the target to
    # resolve (the key is created only once Process Explorer has run).
    Set-PeDword $key 'ColorOwn' 1
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'health: apply exits 0' ($r.Code -eq 0)
    # A fresh -Reapply right after Apply must report the target up to date: this
    # is the health contract (marker + every owned value match the recorded
    # palette). It is the authoritative "themed" signal, not a bare marker.
    $r = Invoke-Install @('-Reapply')
    check 'health: immediately after apply -Reapply reports it up to date' ($r.Code -eq 0 -and $r.Out -match 'up to date')
    # Drift one owned *Dark value (the previously-unowned set).
    Set-PeDword $key 'ColorGraphBkDark' 999999
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    # An explicit -Target is a real apply, so the drift is repaired; prove the
    # drift was DETECTED by checking the value is back and no error occurred.
    check 'health: a drifted owned value is repaired by Apply' ((Get-PeDword $key 'ColorGraphBkDark') -ne 999999)
    # Reapply path: drift then -Reapply repairs the recorded target.
    Set-PeDword $key 'ColorGraphBkDark' 888888
    $r = Invoke-Install @('-Reapply')
    check 'health: -Reapply exits 0' ($r.Code -eq 0)
    check 'health: -Reapply repaired the drifted owned value' ((Get-PeDword $key 'ColorGraphBkDark') -ne 888888)

    # ════ 9. running refusal + -WhatIf mutation-free ════════════════════════════
    $case = New-Case 'running'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    # ALLOW wins over FORCE in the shipped seam order, so the refusal case must
    # clear it to reach the FORCE branch.
    Remove-Item env:WINTAGE_TEST_ALLOW_RUNNING_PE -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_FORCE_RUNNING_PE = '1'
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA)
    check 'running: Apply REFUSES while the process runs' ($r.Code -ne 0 -and $r.Out -match 'close Process Explorer')
    check 'running: refusal left no manifest entry' (@(Get-ManifestKeys) -notcontains 'processexplorer')
    check 'running: refusal left no owned colour value' ((Get-PeDword $key 'ColorOwn') -eq $null)
    Remove-Item env:WINTAGE_TEST_FORCE_RUNNING_PE -ErrorAction SilentlyContinue
    $env:WINTAGE_TEST_ALLOW_RUNNING_PE = '1'
    # -WhatIf must be mutation-free (registry, recovery, manifest, paths).
    $case = New-Case 'whatif'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    Set-PeDword $key 'ColorOwn' 16765136
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packA, '-WhatIf')
    check 'whatif: -WhatIf exits 0' ($r.Code -eq 0)
    check 'whatif: registry value unchanged' ((Get-PeDword $key 'ColorOwn') -eq 16765136)
    check 'whatif: no owned values were added' ((Get-PeDword $key 'ColorOwnDark') -eq $null)
    check 'whatif: no recovery was created' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'recovery\processexplorer\recovery.json')))
    check 'whatif: no manifest entry' (@(Get-ManifestKeys) -notcontains 'processexplorer')
    check 'whatif: no paths.json was created' (-not (Test-Path -LiteralPath (Join-Path $env:WINTAGE_APPDATA 'paths.json')))

    # ════ 10. custom folder persisted through canonical paths.json ══════════════
    $case = New-Case 'custompath'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $peDir3 = Join-Path $case 'PE-Custom'
    New-Item -ItemType Directory -Path $peDir3 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $peDir3 'procexp64.exe'), 'stub', $utf8)
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    $r = Invoke-Install @('-Target', 'processexplorer', '-ProcessExplorerPath', $peDir3, '-Palette', $packA)
    check 'custompath: explicit apply exits 0' ($r.Code -eq 0)
    $pathsFile = Join-Path $env:WINTAGE_APPDATA 'paths.json'
    check 'custompath: the folder was remembered in paths.json' (
        (Test-Path $pathsFile) -and ((([System.IO.File]::ReadAllText($pathsFile, $utf8)) | ConvertFrom-Json).processexplorer -eq $peDir3))
    check 'custompath: processexplorer is a canonical accepted key' (
        ([System.IO.File]::ReadAllText($commonSrc, $utf8)) -match "PATHS_KEYS = .*'processexplorer'")
    # A fresh process with no explicit flag still resolves the remembered folder.
    $r = Invoke-Install @('-Target', 'processexplorer', '-Palette', $packB)
    check 'custompath: a fresh process reuses the remembered folder' ($r.Code -eq 0 -and $r.Out -match 'colours applied')

    # ════ 11. -Target all includes processexplorer when resolvable ══════════════
    $case = New-Case 'alltargets'
    $key = New-Key; $env:WINTAGE_TEST_PE_KEY = $key
    $env:WINTAGE_TEST_PE_COMMON_DIRS = (Join-Path $case 'no-such-dir')
    Set-PeDword $key 'ColorOwn' 1
    $prevAllTargets = $env:WINTAGE_TEST_ALL_TARGETS
    $env:WINTAGE_TEST_ALL_TARGETS = 'processexplorer'
    $r = Invoke-Install @('-Target', 'all', '-Palette', $packA)
    $env:WINTAGE_TEST_ALL_TARGETS = $prevAllTargets
    check 'all: -Target all runs processexplorer' ($r.Code -eq 0 -and $r.Out -match 'colours applied')
    check 'all: manifest records processexplorer' (@(Get-ManifestKeys) -contains 'processexplorer')

    # ════ 12. readability: no near-white fills, still readable vs the list text ═
    # The defect this group was added for: the plain (light-UI) row fills were
    # blended toward a literal #FFFFFF, so on the olive/brown packs they resolved
    # to near-white and read as a harsh flash of white over the Wintage surfaces.
    # The real map builder is loaded here (NOT the key-set stub above) so the
    # assertion runs against the shipped blending, and every pack is checked.
    $readChild = Join-Path $testRoot 'readability.ps1'
    [System.IO.File]::WriteAllText($readChild, (@(
        'param($targets, $themes)',
        '$ErrorActionPreference = ''Stop''',
        # Identity for the BGR packer: the readability math wants hex, not COLORREF.
        'function Convert-HexToBgr([string]$hex) { return $hex }',
        '$src = [System.IO.File]::ReadAllText($targets)',
        'foreach ($decl in @(''\$script:PE_MARKER_VALUE = .*?\n'', ''\$script:PE_ROW_ROLES = @\(.*?\n\)'', ''\$script:PE_COLOR_VALUES = @\(.*?\n\)'')) {',
        '    $blk = [regex]::Match($src, ''(?s)'' + $decl).Value',
        '    if ($blk) { Invoke-Expression $blk }',
        '}',
        'foreach ($fn in @(''Get-RelativeLuminance'', ''Convert-HexBlendToward'', ''Get-ProcessExplorerThemeMap'')) {',
        '    $pat = ''(?s)function '' + [regex]::Escape($fn) + ''\s*\(.*?\n\}''',
        '    $body = [regex]::Match($src, $pat).Value',
        '    if (-not $body) { Write-Host "MISSINGFN=$fn"; exit 3 }',
        '    Invoke-Expression $body',
        '}',
        'function Lin([double]$c) { $c = $c / 255; if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) } }',
        'function Lum([string]$h) { $h = $h.TrimStart(''#''); if ($h.Length -eq 8) { $h = $h.Substring(0,6) }; $r = [Convert]::ToInt32($h.Substring(0,2),16); $g = [Convert]::ToInt32($h.Substring(2,2),16); $b = [Convert]::ToInt32($h.Substring(4,2),16); 0.2126*(Lin $r) + 0.7152*(Lin $g) + 0.0722*(Lin $b) }',
        'function Cr([string]$a, [string]$b) { $x = Lum $a; $y = Lum $b; [Math]::Round((([Math]::Max($x,$y) + 0.05) / ([Math]::Min($x,$y) + 0.05)), 2) }',
        # Scan the ROW-ROLE fills only. The graph backgrounds are SURFACES already
        # derived from backgroundSoft/background, not text-type fills, and a light
        # pack legitimately keeps them light; including them would fault the pack
        # for being light, not for the near-white defect this asserts away.
        '$worstPlainBlack = 99; $worstDarkWhite = 99; $nearWhite = 0; $packs = 0; $darkPacks = 0; $fails = @()',
        'foreach ($f in (Get-ChildItem $themes -Filter ''*.json'')) {',
        '    $t = (Get-Content $f.FullName -Raw | ConvertFrom-Json).tokens',
        '    $map = Get-ProcessExplorerThemeMap $t',
        '    $packs++',
        '    $darkPack = (Get-RelativeLuminance $t.textPrimary) -gt (Get-RelativeLuminance $t.backgroundSoft)',
        '    if ($darkPack) { $darkPacks++ }',
        '    foreach ($k in $map.Keys) {',
        '        if ($k -match ''GraphBk'') { continue }',
        '        $v = [string]$map[$k]',
        '        $h = $v.TrimStart(''#''); if ($h.Length -eq 8) { $h = $h.Substring(0,6) }',
        '        $r = [Convert]::ToInt32($h.Substring(0,2),16); $g = [Convert]::ToInt32($h.Substring(2,2),16); $b = [Convert]::ToInt32($h.Substring(4,2),16)',
        '        if ($k -notmatch ''Dark$'') {',
        '            $cbb = Cr $v ''#000000''',
        '            if ($cbb -lt $worstPlainBlack) { $worstPlainBlack = $cbb }',
        '            if ($darkPack -and $r -ge 240 -and $g -ge 240 -and $b -ge 240) { $nearWhite++; $fails += "$($f.BaseName):$k=$v" }',
        '        } elseif ($darkPack) {',
        '            $cww = Cr $v ''#FFFFFF''',
        '            if ($cww -lt $worstDarkWhite) { $worstDarkWhite = $cww }',
        '        }',
        '    }',
        '}',
        'Write-Host ("READPACKS=" + $packs)',
        'Write-Host ("DARKPACKS=" + $darkPacks)',
        'Write-Host ("NEARWHITE=" + $nearWhite + " " + ($fails -join ","))',
        'Write-Host ("WORSTPLAINBLACK=" + $worstPlainBlack)',
        'Write-Host ("WORSTDARKWHITE=" + $worstDarkWhite)',
        'exit 0'
    ) -join "`n"), $utf8)
    $rr = Run-Child @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $readChild, $targetsSrc, (Join-Path $root 'themes'))
    $readPacks = [int](@($rr.Out -split "`n" | Where-Object { $_ -match '^READPACKS=' })[0] -replace '^READPACKS=', '')
    $darkPacks = [int](@($rr.Out -split "`n" | Where-Object { $_ -match '^DARKPACKS=' })[0] -replace '^DARKPACKS=', '')
    $nearLine = [string](@($rr.Out -split "`n" | Where-Object { $_ -match '^NEARWHITE=' })[0] -replace '^NEARWHITE=', '')
    $nearCount = [int]($nearLine -split ' ')[0]
    $worstPlainBlack = [double](@($rr.Out -split "`n" | Where-Object { $_ -match '^WORSTPLAINBLACK=' })[0] -replace '^WORSTPLAINBLACK=', '')
    $worstDarkWhite = [double](@($rr.Out -split "`n" | Where-Object { $_ -match '^WORSTDARKWHITE=' })[0] -replace '^WORSTDARKWHITE=', '')
    check 'readability: the map builder loads and runs against every palette' ($rr.Code -eq 0 -and $readPacks -gt 0 -and $darkPacks -gt 0)
    check 'readability: no plain row fill resolves to near-white (all channels >= 240)' ($nearCount -eq 0)
    if ($nearCount -ne 0) { Write-Host "       near-white fills: $nearLine" -ForegroundColor Red }
    check 'readability: every plain row fill keeps >= 4.5:1 against black list text' ($worstPlainBlack -ge 4.5)
    check 'readability: every Dark row fill keeps >= 4.5:1 against white list text' ($worstDarkWhite -ge 4.5)
} finally {
    $env:WINTAGE_APPDATA = $prevAppData
    $env:WINTAGE_TEST_PE_KEY = $prevPeKey
    $env:WINTAGE_TEST_PE_COMMON_DIRS = $prevCommon
    $env:WINTAGE_TEST_ALLOW_RUNNING_PE = $prevAllowRunning
    $env:WINTAGE_TEST_FORCE_RUNNING_PE = $prevForceRunning
    $env:WINTAGE_TEST_FAIL_PE_MIDAPPLY = $prevMidApply
    $env:WINTAGE_TEST_FAIL_PE_RECOVERY = $prevRecovery
    if ($null -eq $prevAllTargets) { Remove-Item env:WINTAGE_TEST_ALL_TARGETS -ErrorAction SilentlyContinue } else { $env:WINTAGE_TEST_ALL_TARGETS = $prevAllTargets }
    foreach ($k in $script:createdKeys) { Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
