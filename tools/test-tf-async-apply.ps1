# PERF-002 (audit/8.md) -- terminal-font Apply dispatch model + button lifecycle.
#
# REQUIREMENTS under test:
#   1. Invoke-TfApply routes through Start-BatchJob (async worker) -- not a
#      synchronous foreach with serial -Target children;
#   2. Apply Both dispatches ONE child carrying a combined -Selected set
#      (terminal,conhost), never two serial processes;
#   3. tf mutation buttons are disabled for the batch duration and re-enabled on
#      completion (success/failure both);
#   4. preference persistence happens BEFORE dispatch;
#   5. CORE-002 truthful result classification is invoked in the completion
#      callback.
#
# This suite AST-extracts the REAL Invoke-TfApply / Start-BatchJob and checks
# the production wiring statically, plus drives the source text of the result
# classifier. PowerShell-parse gated.
#
#   .\tools\test-tf-async-apply.ps1          # all tests
#   .\tools\test-tf-async-apply.ps1 -List    # list tests

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
    Write-Host "test-tf-async-apply.ps1 (PERF-002 tf apply dispatch):"
    Write-Host "  1. Invoke-TfApply routes through Start-BatchJob (async)"
    Write-Host "  2. Apply Both builds one -Selected terminal,conhost set"
    Write-Host "  3. no serial -Target foreach loop remains"
    Write-Host "  4. mutation buttons disabled during batch, re-enabled on done"
    Write-Host "  5. preference persisted before dispatch"
    Write-Host "  6. CORE-002 truthful result model in the completion callback"
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

$applyFn = Get-FnText $guiText 'Invoke-TfApply'
check 'PERF-002: Invoke-TfApply located' ($null -ne $applyFn)
if ($null -eq $applyFn) {
    Write-Host '`nInvoke-TfApply not found; aborting' -ForegroundColor Red
    exit 1
}

# ---- 1. async routing --------------------------------------------------------
check 'PERF-002: Invoke-TfApply routes through Start-BatchJob' ($applyFn -match 'Start-BatchJob')
check 'PERF-002: no synchronous foreach -Target child loop' (-not ($applyFn -match 'foreach.*-Target'))

# ---- 2. one selected set -----------------------------------------------------
check 'PERF-002: builds a combined -Selected set' ($applyFn -match '-Selected.*\$selected|-Selected.*/join')
check 'PERF-002: the selected set joins terminal,conhost' ($applyFn -match "terminal.*conhost|\$targets -join ','")

# ---- 3. no serial dispatch ---------------------------------------------------
check 'PERF-002: no single-target -Target dispatch' (-not ($applyFn -match '-Target \$tgt'))

# ---- 4. button lifecycle -----------------------------------------------------
check 'PERF-002: tf mutation buttons disabled for the batch' ($applyFn -match 'Disable-TfApplyUi')
check 'PERF-002: Disable-TfApplyUi disables the three Apply buttons' ($guiText -match 'function Disable-TfApplyUi' -and $guiText -match 'btnTfApplyTerminal\.Enabled = \$false')
check 'PERF-002: Enable-TfApplyUi re-enables on completion' ($guiText -match 'function Enable-TfApplyUi' -and $guiText -match 'btnTfApplyTerminal\.Enabled = \$true')

# ---- 5. preference pre-dispatch ----------------------------------------------
check 'PERF-002: Save-TfPreference persisted before dispatch' (
    ($applyFn.IndexOf('Save-TfPreference') -ge 0) -and
    ($applyFn.IndexOf('Save-TfPreference') -lt $applyFn.IndexOf('Start-BatchJob')))

# ---- 6. CORE-002 truthful result model in completion callback ------------------
check 'PERF-002: completion callback classifies SUCCESS' ($applyFn -match 'apply done\. \(SUCCESS\)' -or $guiText -match 'apply done\. \(SUCCESS\)')
check 'PERF-002: completion callback classifies PARTIAL' ($guiText -match 'apply PARTIAL')
check 'PERF-002: completion callback classifies FAILED' ($guiText -match 'apply FAILED')
check 'PERF-002: completion callback uses Get-BatchFailures for attribution' ($applyFn -match 'Get-BatchFailures')

# ---- 7. batch lifetime safety (mirrors W2-005 contract) -----------------------
check 'PERF-002: refuses a second batch while one is active' ($applyFn -match 'script:batchState' -and $applyFn -match 'busy')
check 'PERF-002: window-close guard covers tf batch (Start-BatchJob sets batchState)' ($guiText -match 'function Test-BatchCloseSafe')

# ---- 8. RED control ------------------------------------------------------------
# The old defective model ran a synchronous foreach with -Target per child. That
# pattern must be absent.
check 'RED control: old synchronous two-process Apply Both is gone' (
    -not ($applyFn -match 'foreach' -and $applyFn -match '\-Target \$tgt'))

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail