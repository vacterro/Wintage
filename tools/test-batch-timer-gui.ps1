# Regression gate for the WinForms batch-timer exception class (T-240/E-891).
#
# DEFECT (user-reported dialog): System.Windows.Forms.Timer.OnTick ->
# "System.Management.Automation.RuntimeException: You cannot call a method on a
# null-valued expression" in an unhandled-exception dialog from the installer
# GUI. The pre-fix code called .ToString() on null lines of 2>&1 child output,
# parsed results without guards, and invoked the completion handler bare, so a
# blank output line (or any completion-handler throw) killed the message pump.
#
# CONTRACT under test -- the REAL Start-BatchJob / Say-Log / Get-BatchFailures /
# Invoke-ChildPowerShell functions, AST-extracted from the shipped
# desktop/WintageInstaller.ps1 and driven through a REAL Forms.Timer on a REAL
# message pump (no desktop automation, no mocked timer):
#  - a batch whose child emits null/blank output lines and exits nonzero still
#    reaches the completion handler and re-enables the buttons;
#  - a batch whose completion handler THROWS does not surface an unhandled
#    WinForms exception (the handler failure is reported in the log instead);
#  - the null-line guards survive: no .ToString() on a possibly-null line
#    anywhere in the shipped file;
#  - the tick is re-entrancy guarded ($finished) and the timer is stopped and
#    disposed exactly once.
# Application.ThreadException is hooked so a regression FAILS HERE with the
# recorded exception instead of showing the crash dialog on the user's desktop.

[CmdletBinding()]
param(
    [switch]$List,
    # Red control: extract from the last COMMITTED GUI (pre-$script:batchState)
    # instead of the working tree. The harness must FAIL against it - that is
    # the proof it still detects the crash-dialog defect.
    [switch]$RedControl
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$gui = Join-Path $root 'desktop\WintageInstaller.ps1'
$redCopy = $null
if ($RedControl) {
    $redCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-gui-head-" + [guid]::NewGuid().ToString('N') + ".ps1")
    $headText = & git -C $root 'show' 'HEAD:desktop/WintageInstaller.ps1' | Out-String
    [System.IO.File]::WriteAllText($redCopy, $headText, (New-Object System.Text.UTF8Encoding($false)))
    $gui = $redCopy
}
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-batch-timer-gui.ps1 (drives the REAL Start-BatchJob on a real Forms.Timer pump):"
    Write-Host "  1. structural: no unguarded .ToString() on child output lines in the shipped file"
    Write-Host "  2. structural: tick carries the re-entrancy guard and stop/dispose"
    Write-Host "  3. behavioural: null/blank child output lines + nonzero exit reach the completion handler"
    Write-Host "  4. behavioural: a throwing completion handler surfaces as a logged failure, never a crash dialog"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms

# ---- structural gates on the shipped source ----
$src = [System.IO.File]::ReadAllText($gui)
check 'struct: no "$line.ToString()" / "$out.ToString()" null-crash pattern remains' ($src -notmatch '\$line\.ToString\(\)|\$out\.ToString\(\)')
# The tick is re-bound against the SCRIPT scope when the pump invokes it, so
# function locals ($finished/$job/$timer) are null there. The shipped gate
# pins the script-scope holder contract instead of the dead local-variable shape.
check 'struct: tick state lives in the $script:batchState holder, not function locals' ($src -match '\$script:batchState = @\{ Job = \$job; Timer = \$timer' -and $src -match 'if \(\$null -eq \$st -or \$st\.Done\) \{ return \}')
check 'struct: tick stops and disposes the timer through the holder' ($src -match '\$st\.Timer\.Stop\(\)' -and $src -match '\$st\.Timer\.Dispose\(\)' -and $src -match 'if \(\$st\.Job\) \{ Remove-Job \$st\.Job')
check 'struct: completion handler invocation is wrapped in try/catch' ($src -match 'BATCH COMPLETION HANDLER FAILED')

# ---- behavioural gates: extract the REAL functions and drive the REAL timer ----
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($gui, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors -and @($parseErrors).Count) { throw "WintageInstaller.ps1 does not parse: $(@($parseErrors)[0].Message)" }

function Get-FunctionAst([string]$name) {
    $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $f) { throw "function $name not found in the shipped GUI" }
    return $f.Extent.Text
}

$form = New-Object System.Windows.Forms.Form
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$script:status = New-Object System.Windows.Forms.Label
$script:btnApply = New-Object System.Windows.Forms.Button
$script:btnRevert = New-Object System.Windows.Forms.Button

# Recorded unhandled exceptions: with these hooks a regression is a recorded
# failure here, never the JIT dialog on the user's desktop.
$script:unhandled = @()
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    $script:unhandled += $e.Exception
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    $script:unhandled += $e.ExceptionObject
})

. ([scriptblock]::Create((Get-FunctionAst 'Say-Log')))
. ([scriptblock]::Create((Get-FunctionAst 'Invoke-ChildPowerShell')))
. ([scriptblock]::Create((Get-FunctionAst 'Get-BatchFailures')))
. ([scriptblock]::Create((Get-FunctionAst 'Start-BatchJob')))

function Invoke-PumpedBatch([string[]]$childArgs, [scriptblock]$onDone) {
    # Mirror the real call shape: Start-BatchJob is entered from a click-handler
    # scope, so the tick scriptblock's declaring scope is this function's scope.
    $script:done = $false
    Start-BatchJob $childArgs $onDone
    try {
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $script:done) {
            foreach ($e in @($script:unhandled)) { Write-Host ("  recorded: {0}" -f $e.Message) -ForegroundColor Yellow }
            throw 'the batch timer never completed the job'
        }
    } catch {
        foreach ($e in @($script:unhandled)) { Write-Host ("  recorded: {0}" -f $e.Message) -ForegroundColor Yellow }
        throw
    }
}

# 3. child output with blank/null lines and a failing exit must reach onDone.
$blankLineArgs = @('-NoProfile', '-Command', "Write-Output 'workbuddy: FAILED - boom'; Write-Output ''; Write-Output ([NullString]::Value); Write-Output 'Install incomplete: 1 target(s) failed (workbuddy).'; exit 1")
$handlerRan = $false
$reportedExit = $null
$reportedFailures = $null
try {
    Invoke-PumpedBatch $blankLineArgs {
        param($child)
        $script:handlerRan = $true
        $script:reportedExit = $child.ExitCode
        $script:reportedFailures = @(Get-BatchFailures $child)
        $script:btnApply.Enabled = $true
        $script:btnRevert.Enabled = $true
        $script:done = $true
    }
} catch {
    # Red control: the pre-fix tick never completes - the recorded unhandled
    # exceptions below are the evidence, so swallow the timeout and continue.
    if (-not $RedControl) { throw }
}
check 'behaviour: completion handler ran on the UI thread after a messy child output' ($handlerRan)
check 'behaviour: nonzero child exit surfaced' ($reportedExit -eq 1)
check 'behaviour: null/blank lines did not kill the tick (per-target failure parsed)' ($reportedFailures -contains 'workbuddy')
check 'behaviour: buttons re-enabled by the handler' ($script:btnApply.Enabled -and $script:btnRevert.Enabled)

# 4. a throwing completion handler must be reported, never crash the pump.
$handlerThrew = $false
try {
    Invoke-PumpedBatch @('-NoProfile', '-Command', 'exit 0') {
        param($child)
        $script:handlerThrew = $true
        $script:done = $true
        throw 'simulated completion handler crash'
    }
} catch {
    if (-not $RedControl) { throw }
}
check 'behaviour: throwing completion handler still ran' ($handlerThrew)
check 'behaviour: handler crash reported in the log, not thrown at the pump' ($log.Text -match 'BATCH COMPLETION HANDLER FAILED' -and $log.Text -match 'simulated completion handler crash')

check 'behaviour: ZERO unhandled WinForms exceptions across the run' (@($script:unhandled).Count -eq 0)
if (@($script:unhandled).Count) {
    foreach ($e in $script:unhandled) { Write-Host ("  recorded: {0}" -f $e.Message) -ForegroundColor Yellow }
}

$form.Dispose()
if ($redCopy) { Remove-Item $redCopy -Force -ErrorAction SilentlyContinue }

if ($RedControl) {
    if ($script:unhandled.Count -gt 0 -and $fail -gt 0) {
        Write-Host "RED CONTROL PROVEN: the pre-fix GUI reproduces the crash dialog ($(@($script:unhandled).Count) recorded unhandled exception(s), $fail gate(s) red)." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "RED CONTROL NOT PROVEN: the broken GUI passed the harness - the gate is blind." -ForegroundColor Red
    exit 1
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
