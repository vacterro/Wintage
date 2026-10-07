# Red control for the release gate derivation (T-394, T-395; SRC-063 CORE-001
# and CORE-002). Every case here is a STRING. This file never reads or writes
# release.ps1 except to prove the real one still derives what it always did —
# which is the entire point: T-390 proved its guard by editing the live release
# entrypoint for the duration of a full suite run, and an external audit
# archived that mutant and reported it as a real missing release gate.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tests/lib/ReleaseGateAudit.ps1')

$script:errors = 0
function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { Write-Host "[PASS] $Label" }
    else { Write-Host "[FAIL] $Label" -ForegroundColor Red; $script:errors++ }
}

function Paths-Of {
    param([string] $Source)
    return @((Get-ReleaseToolInvocations -Source $Source) | ForEach-Object { $_.Path })
}

# --- The four spellings the T-390 regex could not see ------------------------

$direct = @'
node "$PSScriptRoot\tools\test-imaginary.js"
'@
Assert-True ((Paths-Of $direct) -contains 'tools/test-imaginary.js') 'derives a backslash-spelled $PSScriptRoot path'

$joinOne = @'
node (Join-Path $PSScriptRoot 'tools/verify-imaginary.js')
'@
Assert-True ((Paths-Of $joinOne) -contains 'tools/verify-imaginary.js') 'derives a single Join-Path form'

$joinNested = @'
node (Join-Path (Join-Path $PSScriptRoot 'tools') 'verify-nested.js')
'@
Assert-True ((Paths-Of $joinNested) -contains 'tools/verify-nested.js') 'derives a NESTED Join-Path form (CORE-002)'

$viaVariable = @'
$toolDir = Join-Path $PSScriptRoot 'tools'
node (Join-Path $toolDir 'verify-var.js')
'@
Assert-True ((Paths-Of $viaVariable) -contains 'tools/verify-var.js') 'derives a VARIABLE-BOUND tools directory (CORE-002)'

# --- What must NOT be counted -----------------------------------------------

$notTools = @'
$script = Join-Path $PSScriptRoot 'wintage.user.js'
node --check $script
'@
Assert-True (@(Paths-Of $notTools).Count -eq 0) 'a non-tools script argument derives nothing'

$runtimeOnly = "node (`$runtimePath)"
Assert-True (@(Paths-Of $runtimeOnly).Count -eq 0) 'an unresolvable path derives nothing rather than guessing'

# --- The real release script ------------------------------------------------

$releaseCode = [System.IO.File]::ReadAllText((Join-Path $root 'release.ps1'))
$real = @(Get-ReleaseToolInvocations -Source $releaseCode)
$realPaths = @($real | ForEach-Object { $_.Path } | Sort-Object -Unique)
Assert-True ($realPaths.Count -eq 18) "the real release.ps1 derives its 18 tool steps (got $($realPaths.Count))"
foreach ($n in (Get-ReleaseNonGatePaths)) {
    Assert-True ($realPaths -contains $n) "real release.ps1 still invokes the BUILD_IMPORT step $n"
}

# --- Coverage decisions, all on strings -------------------------------------

$covered = Get-ReleaseGateCoverage -Source $joinOne -Root $root
Assert-True ($covered.MustRun -contains 'tools/verify-imaginary.js') 'an imaginary gate enters the must-run set'
Assert-True ($covered.Missing -contains 'tools/verify-imaginary.js') 'an imaginary gate on disk does not exist, and is reported missing'

$withNonGate = @'
node (Join-Path $PSScriptRoot 'tools/verify-imaginary.js')
node (Join-Path $PSScriptRoot 'tools/build-desktop.js')
'@
$cov2 = Get-ReleaseGateCoverage -Source $withNonGate -Root $root
Assert-True ($cov2.MustRun -notcontains 'tools/build-desktop.js') 'a BUILD_IMPORT step is exempt from must-run'
Assert-True ($cov2.Missing.Count -eq 1 -and $cov2.Missing[0] -eq 'tools/verify-imaginary.js') 'the exempt step is still existence-checked'

$dropped = @'
node (Join-Path $PSScriptRoot 'tools/verify-imaginary.js')
'@
$cov3 = Get-ReleaseGateCoverage -Source $dropped -Root $root
Assert-True ($cov3.DroppedNonGates -contains 'tools/build-desktop.js') 'dropping a BUILD_IMPORT step from release.ps1 is reported, not silently excused'

$cov4 = Get-ReleaseGateCoverage -Source $joinOne -Root $root -Executed @('check-css.js')
Assert-True ($cov4.Unrun -contains 'tools/verify-imaginary.js') 'a suite that runs only check-css.js leaves verify-imaginary.js unrun (mislabeled-metadata case)'

# --- Argv is captured, so a check-only import is distinguishable -------------

$checked = @'
node (Join-Path $PSScriptRoot 'tools/derive-palette.js') --check
'@
$inv = @(Get-ReleaseToolInvocations -Source $checked)
Assert-True ($inv.Count -eq 1 -and ($inv[0].Args -contains '--check')) 'argv is captured alongside the path'

Write-Host ""
Write-Host "======================="
if ($script:errors -gt 0) {
    Write-Host "TESTS FAILED ($($script:errors) errors)" -ForegroundColor Red
    exit 1
}
Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
exit 0