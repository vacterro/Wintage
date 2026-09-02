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

Remove-Item $itRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
