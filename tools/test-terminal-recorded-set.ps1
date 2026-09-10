# Terminal recorded-set Reapply health regression suite (T-210 / CORE-011).
#
# Terminal's health probe in targets.ps1 used to walk the FULL set of currently
# discovered settings files and demand a marker on every one of them. That
# contradicts the target's own multi-item ownership contract (T-189/T-190):
# a newly installed Preview / unpackaged settings file that Wintage never
# themed is NOT unhealthy, and an automatic Reapply must not adopt / theme it.
# The fix narrows the marker probe to the manifest-recorded item set, so a
# newly discovered unowned file does not turn a healthy existing install into
# an unhealthy one that -Reapply would theme.
#
#   .\tools\test-terminal-recorded-set.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$targets = Join-Path $here '..\desktop\modules\targets.ps1'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

$src = Get-Content $targets -Raw

# ---- Test 1: the production source uses the recorded set, not the full discovery ----
$terminalBranchStart = $src.IndexOf("if (`$key -eq 'terminal') {")
if ($terminalBranchStart -lt 0) {
    Write-Host "FAIL: cannot locate the Terminal health branch in targets.ps1" -ForegroundColor Red
    exit 1
}

$terminalBranchEnd = $src.IndexOf('} else {', $terminalBranchStart)
$terminalBranch = $src.Substring($terminalBranchStart, $terminalBranchEnd - $terminalBranchStart)

$usesRecorded = $terminalBranch -match '\$paths\s*=\s*@\(\$recorded\)'
check 'static: Terminal health branch uses $recorded (not Get-WindowsTerminalSettingsPaths)' $usesRecorded

$usesDiscovery = $terminalBranch -match '\$paths\s*=\s*@\(Get-WindowsTerminalSettingsPaths\)'
check 'static: Terminal health branch no longer queries Get-WindowsTerminalSettingsPaths' (-not $usesDiscovery)

$hasComment = $src -match 'CORE-011: probe the EFFECTIVE marker/palette state only for the'
check 'static: CORE-011 fix comment is in the production source' $hasComment

# ---- Test 2: behavioural -- the recorded-set marker probe sees ONLY recorded items ----
# Simulate the exact computation the fixed branch performs: given the recorded
# set and a discovery that includes a NEW unowned file, the marker count must
# be computed against the recorded set only, so the new file cannot cause a
# spurious "marker(s) missing".
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-recorded-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$recorded1 = Join-Path $testRoot 'settings-recorded-1.json'
$recorded2 = Join-Path $testRoot 'settings-recorded-2.json'
$newPreview = Join-Path $testRoot 'settings-new-preview.json'
foreach ($f in @($recorded1, $recorded2, $newPreview)) { '' | Set-Content $f }
# The two RECORDED items carry Wintage markers (the new Preview file does not),
# each stamped with the recorded palette value.
'goldendefault' | Set-Content ($recorded1 + '.wintage-palette')
'goldendefault' | Set-Content ($recorded2 + '.wintage-palette')

$recorded = @($recorded1, $recorded2)
$discovered = @($recorded1, $recorded2, $newPreview)

# The fixed branch probes the recorded set.
$markers = @($recorded | ForEach-Object { $_ + '.wintage-palette' } | Where-Object { Test-Path $_ })
check 'behavioural: recorded-set markers all present (2/2)' ($markers.Count -eq 2)
check 'behavioural: no spurious marker(s) missing on the recorded set' ($markers.Count -ge $recorded.Count)

# The OLD (buggy) branch probed discovery -- the new unowned Preview file
# would drop the marker count to 2/3 and flag "marker(s) missing".
$oldMarkers = @($discovered | ForEach-Object { $_ + '.wintage-palette' } | Where-Object { Test-Path $_ })
check 'behavioural: the buggy full-discovery probe WOULD have flagged 2/3 missing' ($oldMarkers.Count -lt $discovered.Count)

# Simulate the actual marker VALUE check on the recorded set -- both markers
# carry the recorded palette, so health is satisfied.
$palette = 'goldendefault'
$mismatch = @()
foreach ($marker in $markers) { $mv = (Get-Content $marker -Raw).Trim(); if ($mv -ne $palette) { $mismatch += $marker } }
check 'behavioural: recorded-set markers all match the recorded palette' ($mismatch.Count -eq 0)

# ---- Test 3 (W2-007): install-terminal.js --revert --keep-recovery preserves the
# recovery artifacts so a failed sibling revert leaves the already-reverted
# items rollback-able. A standalone --finalize-recovery call must refuse to
# consume artifacts while a palette marker is still present (the manifest
# still claims ownership) and must consume them once the marker is gone.
$itRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-it-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $itRoot -Force | Out-Null
$itSettings = Join-Path $itRoot 'settings.json'
$itSettingsBak = "$itSettings.wintage.bak"
$itSettingsMarker = "$itSettings.wintage-palette"
$itSettingsCreated = "$itSettings.wintage-created"

# Build a minimal settings file with one of the OWNED_FIELDS so the helper
# captures a real owned-field backup at Apply time.
$seed = '{"profiles":{"defaults":{"colorScheme":"Stock"}},"schemes":[]}'
[IO.File]::WriteAllText($itSettings, $seed)

# Apply a real palette to seed the backup.
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings --palette (Join-Path $root 'themes/goldendefault.json') | Out-Null
check 'W2-007: Apply wrote the palette marker' (Test-Path $itSettingsMarker)
check 'W2-007: Apply captured the owned-field backup' (Test-Path $itSettingsBak)

# Revert with --keep-recovery: marker, backup, settings merged back to pre-state.
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings --revert --keep-recovery | Out-Null
check 'W2-007: --keep-recovery leaves the palette marker in place' (Test-Path $itSettingsMarker)
check 'W2-007: --keep-recovery leaves the owned-field backup in place' (Test-Path $itSettingsBak)
$kept = (Get-Content $itSettings -Raw) | ConvertFrom-Json
check 'W2-007: --keep-recovery restored the owned field value' ($kept.profiles.defaults.colorScheme -eq 'Stock')

# --finalize-recovery must REFUSE while the marker is still present.
# T-231: the refusal is a NATIVE stderr line, and under $ErrorActionPreference =
# 'Stop' PowerShell 5.1 promotes any native stderr into a terminating
# NativeCommandError -- so the suite died on the exact refusal it was written to
# assert, and the four checks after this point never ran. Every other suite in
# this repo already reads children with Continue and judges them by
# $LASTEXITCODE alone (test-ownership.ps1's Run-TestChild); this does the same.
$finRefused = $false
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = & node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings --finalize-recovery 2>&1
$finCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
if ($finCode -ne 0) { $finRefused = $true }
check 'W2-007: --finalize-recovery refuses while the marker is present' $finRefused
check 'W2-007: the refusal names the marker as the reason' ([bool](@($out) -match 'palette marker is still present'))
check 'W2-007: refusal leaves the marker untouched' (Test-Path $itSettingsMarker)
check 'W2-007: refusal leaves the owned-field backup untouched' (Test-Path $itSettingsBak)

# Simulate the manifest commit: remove the marker, then --finalize-recovery consumes the artifacts.
Remove-Item $itSettingsMarker -Force
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out2 = & node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings --finalize-recovery 2>&1
$finCode2 = $LASTEXITCODE
$ErrorActionPreference = $prevEap
check 'W2-007: --finalize-recovery exits 0' ($finCode2 -eq 0)
check 'W2-007: --finalize-recovery consumes the owned-field backup' (-not (Test-Path $itSettingsBak))

# ---- Test 4 (SRC-002 CORE-001): the COMMITTED finalize contract ----
# Production removes the manifest entry BEFORE finalizing and never touches
# the palette marker itself, so the old contract (finalize only after the
# marker vanished) described a transition no production path performed. The
# caller that actually committed now passes --manifest-committed and the
# helper consumes marker + recovery artifacts together.
$itRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-fin2-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $itRoot2 -Force | Out-Null
$itSettings2 = Join-Path $itRoot2 'settings.json'
[IO.File]::WriteAllText($itSettings2, $seed)
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings2 --palette (Join-Path $root 'themes/goldendefault.json') | Out-Null
check 'CORE-001: Apply wrote the marker (fixture sanity)' (Test-Path "$itSettings2.wintage-palette")
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$outFin = & node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings2 --finalize-recovery --manifest-committed 2>&1
$finCode3 = $LASTEXITCODE
$ErrorActionPreference = $prevEap
check 'CORE-001: --manifest-committed finalize exits 0 while the marker is present' ($finCode3 -eq 0)
check 'CORE-001: --manifest-committed consumes the marker' (-not (Test-Path "$itSettings2.wintage-palette"))
check 'CORE-001: --manifest-committed consumes the backup' (-not (Test-Path "$itSettings2.wintage.bak"))

# ---- Test 5 (SRC-002 CORE-001): the created-file cycle ----
# settings.json did not exist before Apply. Revert must delete it again
# (keeping recovery under --keep-recovery), and the committed finalize must
# consume the created marker and the palette marker. Final state: no
# settings.json, no recovery artifacts.
$itRoot3 = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-fin3-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $itRoot3 -Force | Out-Null
$itSettings3 = Join-Path $itRoot3 'settings.json'
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings3 --palette (Join-Path $root 'themes/goldendefault.json') | Out-Null
check 'CORE-001: Apply created the settings file' (Test-Path $itSettings3)
check 'CORE-001: Apply wrote the created marker' (Test-Path "$itSettings3.wintage-created")
check 'CORE-001: Apply wrote the palette marker' (Test-Path "$itSettings3.wintage-palette")
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings3 --revert --keep-recovery | Out-Null
check 'CORE-001: revert of a created file deletes settings.json' (-not (Test-Path $itSettings3))
check 'CORE-001: --keep-recovery keeps the created marker' (Test-Path "$itSettings3.wintage-created")
check 'CORE-001: --keep-recovery keeps the palette marker' (Test-Path "$itSettings3.wintage-palette")
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& node (Join-Path $root 'tools/install-terminal.js') --settings $itSettings3 --finalize-recovery --manifest-committed 2>&1 | Out-Null
$finCode4 = $LASTEXITCODE
$ErrorActionPreference = $prevEap
check 'CORE-001: committed finalize of a created item exits 0' ($finCode4 -eq 0)
check 'CORE-001: created marker consumed' (-not (Test-Path "$itSettings3.wintage-created"))
check 'CORE-001: palette marker consumed' (-not (Test-Path "$itSettings3.wintage-palette"))
check 'CORE-001: settings.json still absent after the full created-file cycle' (-not (Test-Path $itSettings3))

# ---- Test 6 (SRC-002 CORE-001): cross-cycle preservation ----
# The stale-snapshot data-loss bug: cycle 1 leaves its recovery artifact
# behind, cycle 2 reuses it, and the final Revert restores cycle-1 values
# over the user's newer choices. With the committed finalize closing every
# cycle, cycle 2 must capture a FRESH baseline.
$itRoot4 = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-fin4-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $itRoot4 -Force | Out-Null
$itSettings4 = Join-Path $itRoot4 'settings.json'
$seedA = '{"profiles":{"defaults":{"colorScheme":"Stock-A","historySize":111}},"schemes":[]}'
[IO.File]::WriteAllText($itSettings4, $seedA)
$helperPath = Join-Path $root 'tools/install-terminal.js'
$gold = Join-Path $root 'themes/goldendefault.json'
& node $helperPath --settings $itSettings4 --palette $gold | Out-Null
& node $helperPath --settings $itSettings4 --revert --keep-recovery | Out-Null
& node $helperPath --settings $itSettings4 --finalize-recovery --manifest-committed | Out-Null
$seedB = '{"profiles":{"defaults":{"colorScheme":"Stock-B","historySize":222}},"schemes":[]}'
[IO.File]::WriteAllText($itSettings4, $seedB)
& node $helperPath --settings $itSettings4 --palette $gold | Out-Null
& node $helperPath --settings $itSettings4 --revert --keep-recovery | Out-Null
& node $helperPath --settings $itSettings4 --finalize-recovery --manifest-committed | Out-Null
$final4 = (Get-Content $itSettings4 -Raw) | ConvertFrom-Json
check 'CORE-001: cycle-2 Revert restores the cycle-2 user values (colorScheme Stock-B)' ($final4.profiles.defaults.colorScheme -eq 'Stock-B')
check 'CORE-001: cycle-2 Revert restores the cycle-2 historySize 222' ($final4.profiles.defaults.historySize -eq 222)
check 'CORE-001: no artifacts survive the closed cycle 2' (-not (Test-Path "$itSettings4.wintage-palette") -and -not (Test-Path "$itSettings4.wintage.bak") -and -not (Test-Path "$itSettings4.wintage-created"))

# ---- Test 7 (SRC-002 CORE-001): production wiring ----
# Static checks that targets.ps1 finalizes with --manifest-committed (the
# old test manually deleted the marker to simulate a transition production
# never performed) and that the manifest-commit rollback re-themes EVERY
# reverted item, including an originally absent one.
$src2 = Get-Content $targets -Raw
check 'CORE-001: production finalize passes --manifest-committed' ([bool]($src2 -match '--finalize-recovery --manifest-committed'))
check 'CORE-001: no Test-Path guard suppresses the rollback re-theme' (-not ($src2 -match 'if \(Test-Path \$settings\) \{\s*# W2-005'))

Remove-Item $itRoot2 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $itRoot3 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $itRoot4 -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
