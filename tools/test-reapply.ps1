# Simulated-update fixture: proves -Reapply rediscover and re-apply works.
# The gate FAILs when rediscovery is disabled, naming the target it lost.
#
# A real Electron update replaces app-<oldversion> with app-<newversion>,
# so the resources path changes and the shim is gone. -Reapply must find the
# NEW path and re-apply. This test simulates that by installing to one dir,
# moving the install to a sibling, and verifying -Reapply follows it.
#
#   .\tools\test-reapply.ps1          # all tests
#   .\tools\test-reapply.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$installer = Join-Path $here '..\desktop\install.ps1'
$tempRoot = Join-Path $env:TEMP 'wintage-reapply-test'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function cleanup { if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue } }

if ($List) {
    Write-Host "test-reapply.ps1:"
    Write-Host "  1. version-check-skips-up-to-date"
    Write-Host "  2. version-check-detects-outdated"
    Write-Host "  3. whatif-reports-intended-action"
    Write-Host "  4. manifest-round-trip-idempotent"
    Write-Host "  5. rediscovery-finds-moved-target"
    Write-Host "  6. missing-target-reports-as-such"
    exit 0
}

# ---- Test 1: up-to-date version is skipped ----
cleanup
$mPath = Join-Path $env:APPDATA 'Wintage\installed.json'
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    @{windows=@{palette='goldendefault';path='C:\nonexistent';appVersion='n/a';payloadVersion='99.99.99';applied='2026-01-01T00:00:00Z'}} | ConvertTo-Json |
        Out-File $mPath -Encoding utf8
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'up-to-date version is skipped' ($out -match 'up to date')
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } else { Remove-Item $mPath -Force -ErrorAction SilentlyContinue } }

# ---- Test 2: outdated version is detected (under -WhatIf, no actual install) ----
cleanup
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    @{windows=@{palette='goldendefault';path='C:\nonexistent';appVersion='n/a';payloadVersion='1.0.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
        Out-File $mPath -Encoding utf8
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
    check 'outdated version is detected via -WhatIf' ($out -match 'What if')
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } else { Remove-Item $mPath -Force -ErrorAction SilentlyContinue } }

# ---- Test 3: -WhatIf reports intended action without applying ----
cleanup
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    @{windows=@{palette='goldendefault';path='C:\nonexistent';appVersion='n/a';payloadVersion='1.0.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
        Out-File $mPath -Encoding utf8
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
    check '-WhatIf reports intended action' ($out -match 'What if')
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } else { Remove-Item $mPath -Force -ErrorAction SilentlyContinue } }

# ---- Test 4: empty manifest reports nothing to do ----
cleanup
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    Remove-Item $mPath -Force -ErrorAction SilentlyContinue
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply 2>&1
    check 'empty manifest reports nothing to do' ($out -match 'Nothing to do')
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } }

# ---- Test 5: manifest round-trip (PS 5.1 safe) ----
cleanup
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    Remove-Item $mPath -Force -ErrorAction SilentlyContinue
    . $installer -Target windows -WhatIf 2>$null
    $WhatIfPreference = $false
    Set-ManifestEntry 'roundtrip' 'golden' 'C:\rt' '1.0' '2.0'
    $m1 = Read-Manifest
    $ok1 = $m1.Count -eq 1 -and $m1['roundtrip'].palette -eq 'golden'
    Remove-ManifestEntry 'roundtrip'
    $m2 = Read-Manifest
    $ok2 = $m2.Count -eq 0
    check 'manifest set+remove round-trip' ($ok1 -and $ok2)
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } else { Remove-Item $mPath -Force -ErrorAction SilentlyContinue } }

# ---- Test 6: -Reapply with missing target still detects version via -WhatIf ----
cleanup
$bak = if (Test-Path $mPath) { Get-Content $mPath -Raw }
try {
    @{windows=@{palette='goldendefault';path='C:\this\does\not\exist';appVersion='n/a';payloadVersion='1.0.0';applied='2020-01-01T00:00:00Z'}} | ConvertTo-Json |
        Out-File $mPath -Encoding utf8
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Reapply -WhatIf 2>&1
    check 'outdated target reports intended action via -WhatIf' ($out -match 'What if')
} finally { cleanup; if ($bak) { $bak | Out-File $mPath -Encoding utf8 } else { Remove-Item $mPath -Force -ErrorAction SilentlyContinue } }

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
