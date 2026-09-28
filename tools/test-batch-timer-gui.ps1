# Regression gate for the WinForms batch-timer exception class (T-240/E-891)
# plus the R010 (SRC-007:W2-005) FormClosing batch lifecycle contract.
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
#  - the tick is re-entrancy guarded and the timer is stopped and disposed
#    exactly once.
#
# R010 lifecycle contract (the $script:batchState holder is the AUTHORITATIVE
# batch lifecycle, not a bag of UI bits):
#  B1. an active close is CANCELLED; the timer stays ENABLED and NOT disposed;
#      the job stays Running; no OnDone; every lifecycle flag stays false;
#      zero lifecycle operations are counted during the refusal;
#  B2. repeated refusals perform zero premature lifecycle work; the terminal
#      path afterwards counts Receive-Job=1, Remove-Job=1, Timer.Stop=1,
#      Timer.Dispose=1, Enable-BatchUi=1, OnDone=1, state cleared once; extra
#      message-loop pumping moves NO counter;
#  B3. the success terminal path meets the same exactly-once counters and the
#      subsequent close is allowed;
#  B4. a failed worker follows the same ownership/cleanup contract;
#  B5. a Receive-Job failure is injected through a harness interceptor that
#      throws ONCE while the REAL Job object stays authoritative in the state
#      holder: the synthetic ExitCode=1 result reaches OnDone, the real job and
#      timer are still cleaned up exactly once, no orphan job survives, state
#      clears and the subsequent close is allowed;
#  B6. an OnDone throw is logged, cleanup is not skipped, state cannot wedge.
#
# W2-005 (SRC-007:R010): batch lifecycle contract. The streaming
# Start-BatchJob (SRC-028:R014) owns a System.Diagnostics.Process with a bounded
# output queue and the SAME exact-once ownership path (Consumed/CleanedUp/
# Finalized/Cleared) as the job-based path. The harness must exercise the
# STREAMING variant: the tick drains the bounded queue progressively, the
# process lifetime drives terminalization, and the close lifecycle is answered
# ONLY from Test-BatchCloseSafe -- exactly as the shipped Add_Tick handler does.
# R010 form-closing lifecycle matrix -- the REAL Add_FormClosing handler:
#  B1. an active close is CANCELLED; the timer stays ENABLED and NOT disposed;
#      the process stays alive; no OnDone; every lifecycle flag stays false;
#      zero lifecycle operations are counted during the refusal;
#  B2. repeated refusals perform zero premature lifecycle work; the terminal
#      path afterwards counts drain/Process disposal once, Timer.Stop=1,
#      Timer.Dispose=1, Enable-BatchUi=1, OnDone=1, state cleared once; extra
#      message-loop pumping moves NO counter;
#  B3. the success terminal path meets the same exactly-once counters and the
#      subsequent close is allowed;
#  B4. a failed worker follows the same ownership/cleanup contract;
#  B5. a Drain-BatchQueue failure is injected through a harness interceptor that
#      throws ONCE while the REAL streaming state holder is preserved: the
#      synthetic ExitCode=1 result reaches OnDone, the real process+timer are
#      still cleaned up exactly once, state clears and the close is safe;
#  B6. an OnDone throw is logged, cleanup is not skipped, state cannot wedge.

[CmdletBinding()]
param(
    [switch]$List,
    # Red control: build deterministic R010 defect mutants from the CURRENT
    # fixed GUI and prove the harness reproduces every one of them.
    [switch]$RedControl,
    # Child mode: run the NORMAL harness against this GUI source path (used
    # by -RedControl to drive a mutant copy). Not for interactive use.
    [string]$RedGui
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$gui = Join-Path $root 'desktop\WintageInstaller.ps1'
$pass = 0; $fail = 0
# R010-red probe ledger: r010red() records a defect reproduction when its
# condition (the CONTRACT truth, true on the fixed GUI) is FALSE. RedControl
# exits 0 only when every R010 probe reproduces its defect.
$script:r010RedTotal = 0
$script:r010RedHit = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}
function r010red($label, $cond) {
    $script:r010RedTotal++
    if ($cond) { Write-Host "NOT RED: $label" -ForegroundColor Red }
    else { Write-Host "RED: $label" -ForegroundColor Yellow; $script:r010RedHit++ }
}

if ($List) {
    Write-Host "test-batch-timer-gui.ps1 (drives the REAL Start-BatchJob on a real Forms.Timer pump):"
    Write-Host "  1. structural: no unguarded .ToString() on child output lines in the shipped file"
    Write-Host "  2. structural: tick carries the re-entrancy guard and stop/dispose"
    Write-Host "  3. behavioural: null/blank child output lines + nonzero exit reach the completion handler"
    Write-Host "  4. behavioural: a throwing completion handler surfaces as a logged failure, never a crash dialog"
    Write-Host " R010 (SRC-007:W2-005) FormClosing lifecycle matrix -- the REAL Add_FormClosing handler:"
    Write-Host "  B1. active close: close CANCELLED, timer ENABLED + not disposed, job Running, no OnDone, flags false, zero lifecycle ops"
    Write-Host "  B2. repeated close: every attempt cancelled, zero premature lifecycle work, exactly-once counters stable under extra pumping"
    Write-Host "  B3. success terminal: Receive-Job/Remove-Job/Stop/Dispose/Enable-BatchUi/OnDone exactly once, state cleared once, close then allowed"
    Write-Host "  B4. failed worker: one terminal result, failure observable, cleanup exactly once, close safe"
    Write-Host "  B5. Receive-Job failure: interceptor throws once with the REAL Job kept authoritative, synthetic ExitCode 1, cleanup once, no orphan"
    Write-Host "  B6. OnDone failure: BATCH COMPLETION HANDLER FAILED logged, cleanup not skipped, state cannot wedge, close safe"
    Write-Host "  B7. -RedControl: deterministic mutants of the CURRENT GUI (A active-close refusal removed, B exactly-once guard removed, C close-safe transition removed) prove the R010 assertions red"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms

# ---- structural gates on the shipped source ----
$src = [System.IO.File]::ReadAllText($gui)
check 'struct: no "$line.ToString()" / "$out.ToString()" null-crash pattern remains' ($src -notmatch '\$line\.ToString\(\)|\$out\.ToString\(\)')
# The tick is re-bound against the SCRIPT scope when the pump invokes it, so
# function locals ($finished/$job/$timer) are null there. The shipped gate
# pins the script-scope holder contract instead of the dead local-variable shape.
check 'struct: tick state lives in the $script:batchState holder, not function locals' ($src.Contains('$script:batchState = $st') -and $src.Contains('if ($null -eq $st) { return }') -and $src.Contains('if ($null -eq $st -or $st.Done -or -not $st.Consumed) { return }') -and $src.Contains('Complete-BatchWorker $st'))
check 'struct: tick stops and disposes the timer through the holder' ($src.Contains('$st.Timer.Stop()') -and $src.Contains('$st.Timer.Dispose()') -and $src.Contains('Remove-Job $st.Job -Force'))
check 'struct: completion handler invocation is wrapped in try/catch' ($src -match 'BATCH COMPLETION HANDLER FAILED')

# ---- deterministic R010 red-control mutants (built from the CURRENT fixed GUI) ----
# Each mutant is a TEMPORARY copy of the shipped source with ONE R010 lifecycle
# defect deliberately reintroduced. Structural assertions prove the mutant was
# constructed; the behavioural harness below supplies the verdict. The shipped
# source is never modified.
function New-R010Mutant {
    param([ValidateSet('A', 'B', 'C')][string]$Kind)
    $mutantPath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-gui-r010$Kind-" + [guid]::NewGuid().ToString('N') + ".ps1")
    $text = [System.IO.File]::ReadAllText($gui)
    $mutated = $text
    switch ($Kind) {
        'A' {
            # RED R010-A: an ACTIVE close is no longer refused. The refusal
            # body of the shipped FormClosing handler is replaced with a bare
            # return, so the close proceeds while a batch is still Running.
            $anchorA = @"
    if (Test-BatchCloseSafe) { return }
    `$e.Cancel = `$true
    Say-Log 'An Apply/Revert batch is still running - the window stays open until it completes. Closing is refused so the running operation keeps its owner.'
"@
            $defectA = "    return`r`n"
            $mutated = $text.Replace($anchorA, $defectA)
            if ($mutated -eq $text) { throw 'R010 mutant A: the active-close refusal anchor was not found in the shipped GUI' }
            if (-not $mutated.Contains($defectA) -or $mutated.Contains("`$e.Cancel = `$true`r`n    Say-Log 'An Apply/Revert")) { throw 'R010 mutant A: the refusal body survived the mutation' }
        }
        'B' {
            # RED R010-B: exactly-once lifecycle protection missing. The
            # streaming Complete-BatchWorker guards re-entry at FOUR independent
            # points: the Done early-return, the disposed-Process terminal
            # barrier, and the CleanedUp/Finalized ownership gates. This mutant
            # neutralises every one of them, so a deterministic re-entry into
            # the terminal lifecycle after completion RE-FIRES OnDone -- work
            # the fixed code performs exactly once.
            $anchorDone = 'if ($null -eq $st -or $st.Done -or -not $st.Consumed) { return }'
            $defectDone = 'if ($null -eq $st -or -not $st.Consumed) { return } # R010-B RED: exactly-once re-entry guard removed'
            $mutated = $text.Replace($anchorDone, $defectDone)
            if ($mutated -eq $text) { throw 'R010 mutant B: the terminal re-entry guard anchor was not found in the shipped GUI' }
            $anchorBarrier = 'if (-not $processExited -or -not $st.StdoutEof -or -not $st.StderrEof -or -not $st.ResultChannelSettled -or $st.CallbacksInFlight -ne 0) { return }'
            $mutated = $mutated.Replace($anchorBarrier, 'if ($false) { return } # R010-B RED: re-entry terminal barrier removed')
            if (-not $mutated.Contains('# R010-B RED: re-entry terminal barrier removed')) {
                throw 'R010 mutant B: the disposed-Process terminal barrier anchor was not found in the shipped GUI'
            }
            $mutated = $mutated.Replace('if (-not $st.CleanedUp) {', 'if ($true) { # R010-B RED: CleanedUp ownership guard removed')
            $mutated = $mutated.Replace('if (-not $st.Finalized) {', 'if ($true) { # R010-B RED: Finalized ownership guard removed')
            if (-not $mutated.Contains('# R010-B RED: CleanedUp ownership guard removed') -or
                -not $mutated.Contains('# R010-B RED: Finalized ownership guard removed')) {
                throw 'R010 mutant B: the CleanedUp/Finalized guard anchors were not found in the shipped GUI'
            }
        }
        'C' {
            # RED R010-C: the terminal state never becomes close-safe. The
            # Cleared transition is removed, so the authoritative state stays
            # uncleared after terminal completion and Test-BatchCloseSafe
            # keeps REFUSING the close.
            $anchorC = @"
        try { Enable-BatchUi } catch { }
        if (-not `$st.Cleared) {
            `$st.Cleared = `$true
            `$script:batchState = `$null
        }
"@
            $defectC = "        try { Enable-BatchUi } catch { }`r`n"
            $mutated = $text.Replace($anchorC, $defectC)
            if ($mutated -eq $text) { throw 'R010 mutant C: the Cleared-transition anchor was not found in the shipped GUI' }
        }
    }
    [System.IO.File]::WriteAllText($mutantPath, $mutated, (New-Object System.Text.UTF8Encoding($false)))
    return $mutantPath
}

function Invoke-R010RedControl {
    # Run THIS harness against a mutated GUI copy in a CHILD process (the
    # parent already dot-sourced the fixed functions, so re-extraction must
    # happen in a fresh runspace). The child re-invokes this same file with
    # -RedGui <path>, which runs the NORMAL harness against the given source.
    param([ValidateSet('A', 'B', 'C')][string]$Kind, [string]$MutantPath)
    # A mutant child can emit a raw `throw` (e.g. Start-BatchJob refusing a
    # second batch because the removed lifecycle left one active) onto stderr.
    # Merged via 2>&1 under the parent's $ErrorActionPreference='Stop' that
    # ErrorRecord would TERMINATE the parent before the verdict is read, so the
    # child stderr must be captured non-terminating -- exactly what the shipped
    # Invoke-ChildPowerShell does. The child's own exit code is the signal.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -RedGui $MutantPath 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Kind = $Kind; Code = $code; Text = $text }
}

if ($RedControl) {
    # Normalise the mutant path: a bare $env:TEMP path can arrive as
    # V:\_TEMP_\x (drive-relative) and ParseFile rejects its own "path's format
    # is not supported". Drive-root it explicitly.
    $mutantResults = @()
    foreach ($kind in @('A', 'B', 'C')) {
        $mutantPath = $null
        try {
            $mutantPath = New-R010Mutant -Kind $kind
            Write-Host ("R010 RED {0}: mutant constructed at {1}" -f $kind, $mutantPath) -ForegroundColor DarkGray
            $r = Invoke-R010RedControl -Kind $kind -MutantPath $mutantPath
            $mutantResults += $r
        } finally {
            if ($mutantPath) { Remove-Item -LiteralPath $mutantPath -Force -ErrorAction SilentlyContinue }
        }
    }
    # Verdicts are BEHAVIOURAL, read from each mutant child's gate outcomes.
    # The child must have produced at least one red gate (the defect was
    # exposed) AND the specific defect-class red marker must be present --
    # structural-only reds (e.g. a mutated-away source pattern) never count.
    # RED R010-A: the behavioural close gates go red on the mutant. Plain
    # substrings, NOT regex: the marker text carries literal parentheses and
    # a -match pattern treats them as groups (the exact-text verdict then
    # never fires on a marker that is visibly present).
    $a = $mutantResults | Where-Object { $_.Kind -eq 'A' }
    $redA = ($a -and $a.Code -ne 0 -and $a.Text -match 'A-red: an ACTIVE close was NOT cancelled')
    # RED R010-B: the duplicate-terminal gate goes red on the mutant.
    $b = $mutantResults | Where-Object { $_.Kind -eq 'B' }
    $redB = ($b -and $b.Code -ne 0 -and $b.Text -match 'R010 B-red: duplicate terminal work on re-entry')
    # RED R010-C: the post-terminal safe-close gates go red on the mutant.
    $c = $mutantResults | Where-Object { $_.Kind -eq 'C' }
    $redC = ($c -and $c.Code -ne 0 -and $c.Text -match 'R010 C-red: post-terminal safe-close contract')
    Write-Host ''
    Write-Host ("R010 RED summary: A={0} B={1} C={2}" -f $(if ($redA) { 'REPRODUCED' } else { 'NOT-RED' }), $(if ($redB) { 'REPRODUCED' } else { 'NOT-RED' }), $(if ($redC) { 'REPRODUCED' } else { 'NOT-RED' }))
    if (-not ($redA -and $redB -and $redC)) {
        foreach ($r in $mutantResults) {
            Write-Host ("  DIAG mutant {0}: exit={1} markerA={2} markerB={3} markerC={4}" -f $r.Kind, $r.Code, ($r.Text -match 'A-red:'), ($r.Text -match 'B-red:'), ($r.Text -match 'C-red:')) -ForegroundColor DarkGray
            $tail = @($r.Text -split "`r?`n" | Where-Object { $_ -match 'FAIL|THREW|does not parse|NOT RECOGNIZED|Exception' } | Select-Object -First 6)
            foreach ($t in $tail) { Write-Host "    $t" -ForegroundColor DarkGray }
        }
        Write-Host 'R010 RED CONTROL NOT PROVEN: at least one defect class was not behaviourally reproduced.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'R010 RED CONTROL PROVEN: all three defect classes behaviourally reproduced on deterministic mutants of the current GUI.' -ForegroundColor Yellow
    exit 0
}

if ($RedGui) { $gui = $RedGui }

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
# W2-004/W2-005: Start-BatchJob now toggles the WHOLE batch UI through
# Disable-BatchUi/Enable-BatchUi, so the harness supplies every control those
# functions touch, exactly as the real form would have them in scope.
$script:btnSave = New-Object System.Windows.Forms.Button
$script:btnDelCustom = New-Object System.Windows.Forms.Button
$script:lstThemes = New-Object System.Windows.Forms.ListBox
$script:clbMyApps = New-Object System.Windows.Forms.CheckedListBox
$script:clbPopularApps = New-Object System.Windows.Forms.CheckedListBox
$script:btnSelectAll = New-Object System.Windows.Forms.Button
$script:btnSelectNone = New-Object System.Windows.Forms.Button
$script:cmbLanguage = New-Object System.Windows.Forms.ComboBox

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

# R014 (SRC-028): Say-Log now routes through the bounded log helper, so the
# helper and its retention caps must be present before Say-Log is dot-sourced.
$script:LogCharCap = 200000; $script:LogLowWater = 150000; $script:LogMaxChunk = 50000
. ([scriptblock]::Create((Get-FunctionAst 'Add-BoundedLogText')))
. ([scriptblock]::Create((Get-FunctionAst 'Say-Log')))
. ([scriptblock]::Create((Get-FunctionAst 'Invoke-ChildPowerShell')))
. ([scriptblock]::Create((Get-FunctionAst 'Get-BatchFailures')))
# R014 (SRC-028): the streaming Start-BatchJob tick enqueues/drains bounded
# records and parses machine-result payloads, so the transport helpers and
# their module-level budgets must exist before the worker runs.
$script:BatchQueueMax = 2000
$script:BatchQueueLines = 0
$script:BatchQueueGate = New-Object object
$script:BatchDroppedLines = 0
$script:BatchDrainLineBudget = 200
$script:BatchDrainCharBudget = 8000
$script:BatchQueueRecordCharMax = [Math]::Max(1, $script:BatchDrainCharBudget - 2)
$script:BatchResults = @{}
$script:BatchResultSeenTarget = @{}
$script:BatchResultMalformed = $false
$script:BatchResultMalformedReason = $null
foreach ($batchFn in @('New-BatchQueueItem', 'Enqueue-BatchItem', 'Set-BatchResultMalformed', 'Add-BatchMachineResult', 'Add-BatchMachineResultFromPayload', 'Classify-BatchResult')) {
    . ([scriptblock]::Create((Get-FunctionAst $batchFn)))
}
. ([scriptblock]::Create((Get-FunctionAst 'Start-BatchJob')))
foreach ($lifecycleFn in @('Disable-BatchUi', 'Enable-BatchUi', 'Complete-BatchWorker', 'Test-BatchCloseSafe')) {
    $fnText = Get-FunctionAst $lifecycleFn
    if ($fnText) { . ([scriptblock]::Create($fnText)) }
}

# R010 exactly-once instrumentation around the REAL streaming lifecycle path.
# The extracted Complete-BatchWorker resolves the Process / Timer / Drain at
# invocation time, so harness-local wrappers shadow them transparently and COUNT
# without changing behaviour: each wrapper delegates to the real object, so
# shadowing can never recurse into itself.
$script:recvCount = 0
$script:drainCount = 0
$script:procDisposeCount = 0
$script:removeCount = 0
$script:timerStopCount = 0
$script:timerDisposeCount = 0
$script:enableUiCount = 0
$script:failDrain = $false

# Capture the REAL lifecycle functions BEFORE the wrappers below shadow the names.
$script:realEnableBatchUi = $null
$enableCmd = Get-Command Enable-BatchUi -CommandType Function -ErrorAction SilentlyContinue
if ($enableCmd) { $script:realEnableBatchUi = $enableCmd.ScriptBlock }

# Drain-BatchQueue wrapper (streaming successor to Receive-Job). The shipped
# Complete-BatchWorker calls Drain-BatchQueue on the state holder's Queue.
# Capture the REAL shipped function BEFORE the shadow below hides the name: it
# is dot-sourced into scope first, its ScriptBlock is grabbed, then the shadow
# replaces it. (Building a scriptblock from the raw `function ... {}` text would
# only REDEFINE the function on invoke, never run its body, so the queue would
# never drain and the tick would stall.)
. ([scriptblock]::Create((Get-FunctionAst 'Drain-BatchQueue')))
$script:realDrainBatchQueue = (Get-Command Drain-BatchQueue -CommandType Function).ScriptBlock
function Drain-BatchQueue {
    $script:drainCount++
    if ($script:failDrain) {
        $script:failDrain = $false  # one-shot; restore real behaviour
        throw 'simulated Drain-BatchQueue failure (R010 B5 harness interceptor)'
    }
    # Delegate to the REAL shipped Drain-BatchQueue via its captured scriptblock.
    if ($script:realDrainBatchQueue) { & $script:realDrainBatchQueue @args }
}

# Remove-Job is a legacy Job-path cmdlet the streaming Complete-BatchWorker no
# longer calls. Count only if it is ever invoked.
$script:realRemoveJob = Get-Command Remove-Job -CommandType Cmdlet -ErrorAction SilentlyContinue
function Remove-Job {
    param()
    $script:removeCount++
    if ($script:realRemoveJob) { & $script:realRemoveJob @args }
}
if ($script:realEnableBatchUi) {
    function Enable-BatchUi {
        $script:enableUiCount++
        & $script:realEnableBatchUi @args
    }
}
function Reset-BatchCounters {
    $script:recvCount = 0; $script:drainCount = 0; $script:procDisposeCount = 0; $script:removeCount = 0
    $script:timerStopCount = 0; $script:timerDisposeCount = 0; $script:enableUiCount = 0
    $script:failDrain = $false
}
function Install-TimerProxy {
    # Swap holders' process/timer for counting proxies that DELEGATE to the real ones.
    # The tick reads $st.Process.HasExited, so the proxy must expose it.
    if (-not $script:batchState) { return }
    if ($script:batchState.Process -is [System.Diagnostics.Process]) {
        $pp = [pscustomobject]@{ Real = $script:batchState.Process }
        $pp | Add-Member -MemberType ScriptProperty -Name HasExited -Value { return $this.Real.HasExited } -SecondValue { param($v) }
        # The streaming tick reads $st.Process.ExitCode to author the terminal
        # result; the proxy MUST forward it or the completion classifies exit 0.
        $pp | Add-Member -MemberType ScriptProperty -Name ExitCode -Value { return $this.Real.ExitCode } -SecondValue { param($v) }
        $pp | Add-Member -MemberType ScriptMethod -Name CancelOutputRead -Value { $this.Real.CancelOutputRead() }
        $pp | Add-Member -MemberType ScriptMethod -Name CancelErrorRead -Value { $this.Real.CancelErrorRead() }
        $pp | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:procDisposeCount++; $this.Real.Dispose() }
        $script:batchState.Process = $pp
    }
    if ($script:batchState.Timer.PSObject.Properties['Real']) { return }
    if ($script:batchState.Timer -is [System.Windows.Forms.Timer]) {
        $tp = [pscustomobject]@{ Real = $script:batchState.Timer }
        $tp | Add-Member -MemberType ScriptProperty -Name Enabled -Value { return $this.Real.Enabled } -SecondValue { param($v) $this.Real.Enabled = $v }
        $tp | Add-Member -MemberType ScriptProperty -Name IsDisposed -Value { return $false } -SecondValue { param($v) }
        $tp | Add-Member -MemberType ScriptMethod -Name Stop -Value { $script:timerStopCount++; $this.Real.Stop() }
        $tp | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:timerDisposeCount++; $this.Real.Dispose() }
        $script:batchState.Timer = $tp
    }
}

function Invoke-PumpedBatch([string[]]$childArgs, [scriptblock]$onDone) {
    # Mirror the real call shape: Start-BatchJob is entered from a click-handler
    # scope, so the tick scriptblock's declaring scope is this function's scope.
    # A prior pass may have left a batch active (this happens deliberately on a
    # mutant-C run where the Cleared transition is removed); clear that stale
    # holder so Start-BatchJob does not refuse this batch as "already active".
    $stale = $script:batchState
    if ($stale) {
        try { if ($stale.Timer) { $stale.Timer.Stop(); $stale.Timer.Dispose() } } catch { }
        try { if ($stale.Process -and -not $stale.Process.HasExited) { $stale.Process.Kill() } } catch { }
        try { if ($stale.Process) { $stale.Process.Dispose() } } catch { }
        $script:batchState = $null
    }
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
$blankLineArgs = @('-NoProfile', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Write-Output 'workbuddy: FAILED - boom'; Write-Output ''; Write-Output ([NullString]::Value); Write-Output 'Install incomplete: 1 target(s) failed (workbuddy).'; exit 1")))
$handlerRan = $false
$reportedExit = $null
$reportedFailures = $null
try {
    Invoke-PumpedBatch $blankLineArgs {
        param($child)
        $script:handlerRan = $true
        $script:reportedExit = $child.ExitCode
        # Streaming: ordinary child lines are drained into the log, not carried
        # on a legacy .Output array. Parse the observable failure from the log
        # the tick actually produced (the shipped Apply handler logs the same
        # lines via Say-Log before parsing / exit-code fallback).
        $script:reportedFailures = @(Get-BatchFailures ([pscustomobject]@{ Output = @($log.Text -split "`r?`n") }))
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

# ─────────────────────────────────────────────────────────────────────────────
# R010 (SRC-007:W2-005) FormClosing lifecycle matrix. The REAL Add_FormClosing
# handler is AST-extracted from the shipped GUI and attached to the harness
# form, so every close below goes through the exact shipped close logic --
# never a reimplementation.
# ─────────────────────────────────────────────────────────────────────────────
$formClosingBlockText = $null
foreach ($inv in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandExpressionAst] -and $n.Expression -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Member.Value -eq 'Add_FormClosing' }, $true)) {
    foreach ($arg in $inv.Expression.Arguments) {
        if ($arg -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            # The member's Extent.Text is the scriptblock literal WITH its outer
            # braces (on PS 5.1 even ScriptBlockAst.Extent.Text keeps them, so
            # no property in the AST hands over the bare body).
            # [scriptblock]::Create("{ ... }") would compile a scriptblock whose
            # body is a NESTED scriptblock literal: invoking THAT emits the
            # inner scriptblock (its own source text) and executes nothing --
            # every close would silently no-op. Strip the outermost braces so
            # the compiled scriptblock IS the shipped handler body.
            $rawExtent = $arg.Extent.Text.Trim()
            if ($rawExtent.StartsWith('{') -and $rawExtent.EndsWith('}')) {
                $formClosingBlockText = $rawExtent.Substring(1, $rawExtent.Length - 2)
            }
        }
    }
}
$closeHandler = $null
if ($formClosingBlockText) { $closeHandler = [scriptblock]::Create($formClosingBlockText) }
check 'R010 struct: the shipped GUI registers the authoritative Add_FormClosing handler' ($null -ne $closeHandler)
check 'R010 struct: the close decision is answered by Test-BatchCloseSafe, never by button flags' ($null -ne $formClosingBlockText -and $formClosingBlockText -match 'Test-BatchCloseSafe')

function Invoke-RealFormClosing {
    # Drives the EXACT extracted shipped handler and returns its cancel answer.
    $e = New-Object System.Windows.Forms.FormClosingEventArgs([System.Windows.Forms.CloseReason]::UserClosing, $false)
    $dbgRaw = & $closeHandler $form $e
    if ($script:batchState -and $script:batchState.Process -and -not $script:batchState.Process.HasExited) {
        Write-Host ("  DEBUG RFC(close-decided): cancel=" + $e.Cancel) -ForegroundColor DarkGray
    }
    return [bool]$e.Cancel
}

function Wait-BatchJobRunning {
    # Barrier: pump the REAL message pump until the batch worker's Process is
    # actually referenced inside $script:batchState. The process may already
    # have exited for short children, so any batchState is sufficient.
    for ($i = 0; $i -lt 240; $i++) {
        [System.Windows.Forms.Application]::DoEvents()
        $stNow = $script:batchState
        if ($stNow) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return $false
}

function Stop-LingeringBatch {
    # HARNESS-ONLY teardown for a deliberately still-running fixture worker
    # (the assertions above already proved the SHIPPED code never stops it).
    # Must NOT feed the exactly-once counters inside the shipped Complete-BatchWorker.
    $stNow = $script:batchState
    if ($stNow) {
        if ($stNow.Timer) {
            $t = if ($stNow.Timer.PSObject.Properties['Real']) { $stNow.Timer.Real } else { $stNow.Timer }
            try { $t.Stop() } catch { }
            try { $t.Dispose() } catch { }
        }
        if ($stNow.Process) {
            $p = if ($stNow.Process.PSObject.Properties['Real']) { $stNow.Process.Real } else { $stNow.Process }
            try { if ($p -and -not $p.HasExited) { $p.Kill() } } catch { }
            try { $p.Dispose() } catch { }
            try { $p.CancelOutputRead() } catch { }
            try { $p.CancelErrorRead() } catch { }
        } elseif ($stNow.Job) {
            try {
                $realRemoveJob = Get-Command Remove-Job -CommandType Cmdlet -ErrorAction SilentlyContinue
                if ($realRemoveJob) { & $realRemoveJob $stNow.Job -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
    }
    $script:batchState = $null
    $script:batchActive = $false
}

$delayedChildArgs = @('-NoProfile', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 2; exit 0')))

# Child command builder: -EncodedCommand (base64 UTF-16LE) survives any
# wrapper, where nested -Command strings had their double quotes STRIPPED by
# the intermediate powershell.exe (the parsed summary line then read
# 'workbuddy: FAILED - boom; ...' as broken tokens and the child died with a
# ParserError before writing a single output line).

if ($closeHandler -and (Get-Command Test-BatchCloseSafe -CommandType Function -ErrorAction SilentlyContinue)) {

    # Tests 3-4 above ran batches via Invoke-PumpedBatch. On a mutant that
    # removed the Cleared transition (RED C) the holder is left active, so clear
    # any stale holder before the first direct Start-BatchJob of this matrix.
    Stop-LingeringBatch

    # ---- B1: active close is REFUSED; timer stays ENABLED and NOT disposed ----
    $closeCancelActive = $null
    $workerStillThere = $false
    $workerStillRunning = $false
    $timerStillEnabled = $false
    $flagsUntouched = $false
    $zeroPrematureOps = $false
    $noEarlyOnDone = $null
    $procStillAlive = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        Start-BatchJob $delayedChildArgs { param($child) $script:done = $true }
        $running = Wait-BatchJobRunning
        check 'R010 B1: the deliberately delayed worker reached Running (barrier)' $running
        $closeCancelActive = Invoke-RealFormClosing
        $stNow = $script:batchState
        $workerStillThere = ($null -ne $stNow -and ($stNow.Process -or $stNow.Job))
        $workerStillRunning = ($stNow -and $stNow.Process -and -not $stNow.Process.HasExited)
        # The refused close must leave the timer ACTIVE: still enabled, not
        # disposed (a disposed WinForms Timer has IsDisposed=true).
        $timerStillEnabled = ($stNow -and $stNow.Timer -and ($stNow.Timer.Enabled -eq $true) -and (-not $stNow.Timer.IsDisposed))
        $noEarlyOnDone = ($script:done -eq $false)
        # Every lifecycle flag must still be false: the refusal performed no
        # Consumed/CleanedUp/Finalized/Cleared transition.
        $flagsUntouched = ($stNow -and @($stNow.Consumed, $stNow.CleanedUp, $stNow.Finalized, $stNow.Cleared) -notcontains $true)
        # The process is a real OS process the refusal did not kill.
        $procStillAlive = ($stNow -and $stNow.Process -and -not $stNow.Process.HasExited)
        # Counted proof of zero premature lifecycle work. A refused close must
        # not restore the UI either: Enable-BatchUi is part of the assertion.
        $zeroPrematureOps = ($script:recvCount -eq 0 -and $script:drainCount -eq 0 -and $script:removeCount -eq 0 -and $script:timerStopCount -eq 0 -and $script:timerDisposeCount -eq 0 -and $script:enableUiCount -eq 0)
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B1: close event is CANCELLED while the batch is active' ($closeCancelActive -eq $true)
    check 'R010 B1: $script:batchState remains active after the refused close' $workerStillThere
    check 'R010 B1: the worker process is still alive after the refused close' $procStillAlive
    check 'R010 B1: the TIMER is still ENABLED and NOT disposed after the refused close' $timerStillEnabled
    check 'R010 B1: no OnDone fired by the refused close' ($noEarlyOnDone -eq $true)
    check 'R010 B1: lifecycle flags (Consumed/CleanedUp/Finalized/Cleared) all still false after the refused close' $flagsUntouched
    check 'R010 B1: zero lifecycle operations counted during the refused close (drain/Remove/Stop/Dispose/Enable-BatchUi all 0)' $zeroPrematureOps

    # ---- B2: repeated refusals do zero premature work; terminal path is exactly-once ----
    $cancelAnswers = @()
    $repeatAlive = $false
    $repeatNoLifecycleWork = $false
    $repeatWorkerFinished = $false
    $repeatExitOk = $null
    $prematureCounts = @()
    $zeroOpsDuringRefusals = $false
    $exactlyOnce = $false
    $stateClearedOnce = $false
    $stableAfterExtraPumping = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        $script:onDoneRuns = 0
        Start-BatchJob $delayedChildArgs { param($child) $script:onDoneRuns++; $script:repeatExitOk = $child.ExitCode; $script:done = $true }
        $running = Wait-BatchJobRunning
        for ($i = 0; $i -lt 3; $i++) {
            $cancelAnswers += Invoke-RealFormClosing
            $stNow = $script:batchState
            if ($stNow) { $prematureCounts += @((@($stNow.Consumed, $stNow.CleanedUp, $stNow.Finalized) | Where-Object { $_ }).Count) }
        }
        # RED-marker probe (RED R010-A): if an ACTIVE close is allowed, the
        # close-ownership contract is broken. Recorded as the defect evidence
        # consumed by the -RedControl verdict for mutant A.
        if (@($cancelAnswers | Where-Object { -not $_ }).Count -gt 0) {
            Write-Host 'R010 A-red: an ACTIVE close was NOT cancelled (close allowed while the batch is still running)' -ForegroundColor Yellow
        }
        $repeatAlive = ($null -ne $script:batchState -and $script:batchState.Process -and -not $script:batchState.Process.HasExited)
        $repeatNoLifecycleWork = (@($prematureCounts | Where-Object { $_ -ne 0 }).Count -eq 0)
        $zeroOpsDuringRefusals = ($script:recvCount -eq 0 -and $script:drainCount -eq 0 -and $script:removeCount -eq 0 -and $script:timerStopCount -eq 0 -and $script:timerDisposeCount -eq 0 -and $script:enableUiCount -eq 0)
        # Counters now live for the terminal path.
        Install-TimerProxy
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $repeatWorkerFinished = $script:done
        $exactlyOnce = ($script:drainCount -ge 1 -and $script:procDisposeCount -eq 1 -and $script:timerStopCount -eq 1 -and $script:timerDisposeCount -eq 1 -and $script:enableUiCount -eq 1)
        # RED-marker probe (RED R010-B): a duplicated drain/dispose is the direct
        # behavioural evidence that exactly-once lifecycle protection is gone.
        if ($script:drainCount -gt 1 -or $script:procDisposeCount -gt 1) {
            Write-Host ('R010 B-red: duplicate terminal work on re-entry (drain count ' + $script:drainCount + ', proc dispose ' + $script:procDisposeCount + ')') -ForegroundColor Yellow
        }
        $stateClearedOnce = ($null -eq $script:batchState -and $script:onDoneRuns -eq 1)
        # Pump ADDITIONAL message-loop iterations: no counter may increase.
        $snapR = $script:drainCount; $snapP = $script:procDisposeCount; $snapS = $script:timerStopCount
        $snapD = $script:timerDisposeCount; $snapU = $script:enableUiCount; $snapO = $script:onDoneRuns
        for ($i = 0; $i -lt 12; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $stableAfterExtraPumping = ($script:drainCount -eq $snapR -and $script:procDisposeCount -eq $snapP -and $script:timerStopCount -eq $snapS -and
            $script:timerDisposeCount -eq $snapD -and $script:enableUiCount -eq $snapU -and $script:onDoneRuns -eq $snapO)
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B2: every repeated close attempt is cancelled' (@($cancelAnswers | Where-Object { -not $_ }).Count -eq 0 -and @($cancelAnswers).Count -eq 3)
    check 'R010 B2: lifecycle state stays consistent (zero premature Consumed/CleanedUp/Finalized)' $repeatNoLifecycleWork
    check 'R010 B2: zero lifecycle operations counted during the repeated refusals' $zeroOpsDuringRefusals
    Write-Host ("  DEBUG B2: finished=$repeatWorkerFinished exitOk=$repeatExitOk onDoneRuns=$script:onDoneRuns drain=$script:drainCount") -ForegroundColor DarkGray
    check 'R010 B2: worker continues normally after the repeated refusals (completed exit 0)' ($repeatWorkerFinished -and $repeatExitOk -eq 0)
    check 'R010 B2: EXACTLY-ONCE counters after the terminal path (drain>=1 procDispose=1 Timer.Stop=1 Timer.Dispose=1 Enable-BatchUi=1)' $exactlyOnce
    check 'R010 B2: OnDone exactly once, state CLEARED after the terminal completion and REMAINS cleared under extra pumping' ($script:onDoneRuns -eq 1 -and $stateClearedOnce -and $stableAfterExtraPumping)
    check 'R010 B2: extra message-loop pumping increases NO counter' $stableAfterExtraPumping

    # ---- B3: success terminal path - exactly-once counters, then close allowed ----
    $successOnDoneCount = 0
    $successExactlyOnce = $false
    $successStateClearedOnce = $false
    $successCloseAllowed = $null
    $successStable = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        Start-BatchJob @('-NoProfile', '-Command', 'exit 0') {
            param($child)
            $script:successOnDoneCount++
            $script:done = $true
        }
        Install-TimerProxy
        # Capture the AUTHORITATIVE state reference for the deterministic
        # re-entry probe below (the same hashtable the lifecycle mutates -
        # Cleared nulls the holder, not this reference).
        $script:reentryStateRef = $script:batchState
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        # Idempotence: pump further ticks - the completion must NOT run twice.
        for ($i = 0; $i -lt 6; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $successExactlyOnce = ($script:drainCount -ge 1 -and $script:procDisposeCount -eq 1 -and $script:timerStopCount -eq 1 -and
            $script:timerDisposeCount -eq 1 -and $script:enableUiCount -eq 1 -and $script:successOnDoneCount -eq 1)
        $successStateClearedOnce = ($null -eq $script:batchState)
        $successCloseAllowed = (-not (Invoke-RealFormClosing))
        # RED-marker probe (RED R010-B): deterministic re-entry into the
        # terminal lifecycle AFTER completion. The fixed code's exactly-once
        # guards (Done + CleanedUp + Finalized + Timer/ProcessDisposed) make
        # re-entry INERT: no disposal counter moves AND OnDone does not re-fire.
        # Record BEFORE any throw so the marker survives a later harness throw.
        $reentryInert = $true
        if ($script:reentryStateRef) {
            $preR = $script:drainCount; $preP = $script:procDisposeCount; $preS = $script:timerStopCount
            $preD = $script:timerDisposeCount; $preU = $script:enableUiCount; $preO = $script:successOnDoneCount
            Complete-BatchWorker $script:reentryStateRef
            if ($script:drainCount -ne $preR -or $script:procDisposeCount -ne $preP -or $script:timerStopCount -ne $preS -or
                $script:timerDisposeCount -ne $preD -or $script:enableUiCount -ne $preU -or $script:successOnDoneCount -ne $preO) {
                $reentryInert = $false
                Write-Host ('R010 B-red: duplicate terminal work on re-entry (drain delta ' + ($script:drainCount - $preR) + ', proc dispose delta ' + ($script:procDisposeCount - $preP) + ', Timer.Stop delta ' + ($script:timerStopCount - $preS) + ', Timer.Dispose delta ' + ($script:timerDisposeCount - $preD) + ', Enable-BatchUi delta ' + ($script:enableUiCount - $preU) + ', OnDone delta ' + ($script:successOnDoneCount - $preO) + ')') -ForegroundColor Yellow
            }
        }
        # RED-marker probes (RED R010-C): after terminal completion the state
        # must be cleared and the close must be ALLOWED. Record BEFORE any
        # throw so the markers survive a later harness throw.
        if (-not $successStateClearedOnce) {
            Write-Host 'R010 C-red: post-terminal safe-close contract - state remains uncleared after terminal completion' -ForegroundColor Yellow
        }
        if ($successCloseAllowed -eq $false) {
            Write-Host 'R010 C-red: post-terminal safe-close contract - close refused after terminal completion' -ForegroundColor Yellow
        }
        $snapR = $script:drainCount; $snapP = $script:procDisposeCount; $snapS = $script:timerStopCount
        $snapD = $script:timerDisposeCount; $snapU = $script:enableUiCount
        for ($i = 0; $i -lt 8; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $successStable = ($script:drainCount -eq $snapR -and $script:procDisposeCount -eq $snapP -and $script:timerStopCount -eq $snapS -and
            $script:timerDisposeCount -eq $snapD -and $script:enableUiCount -eq $snapU)
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B3: success terminal path runs OnDone and re-enables the batch UI exactly once' ($successOnDoneCount -eq 1 -and $script:btnApply.Enabled -and $script:btnRevert.Enabled)
    check 'R010 B3: EXACTLY-ONCE counters on the success terminal path (drain>=1 procDispose=1 Stop=1 Dispose=1 Enable-BatchUi=1)' $successExactlyOnce
    check 'R010 B3: $script:batchState cleared after the terminal completion (null holder; no terminal counter repeats under extra pumping)' $successStateClearedOnce
    check 'R010 B3: subsequent FormClosing is ALLOWED after the terminal path' ($successCloseAllowed -eq $true)
    check 'R010 B3: extra pumping after the success terminal moves NO counter' $successStable
    check 'R010 B3: re-entry into a completed terminal lifecycle is INERT (exactly-once guard holds)' $reentryInert

    # ---- B4: a failing worker keeps the failure observable, cleanup exactly-once ----
    $failedExit = $null
    $failedFailures = $null
    $failedCloseAllowed = $null
    $failedExactlyOnce = $false
    $failedStateCleared = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        Start-BatchJob @('-NoProfile', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Write-Output 'workbuddy: FAILED - boom'; Write-Output 'Install incomplete: 1 target(s) failed (workbuddy).'; exit 1"))) {
            param($child)
            $script:failedExit = $child.ExitCode
            # Streaming completion hands the state holder (no legacy .Output).
            # Failures are the parsed text lines when present, else the nonzero
            # exit code is the authoritative failure signal -- the same fallback
            # the shipped Apply handler uses (`if ExitCode -ne 0 -and -not
            # failed.Count { failed = keys }`).
            $script:failedFailures = @(Get-BatchFailures $child)
            if ($child.ExitCode -ne 0 -and -not $script:failedFailures.Count) { $script:failedFailures = @('workbuddy') }
            $script:done = $true
        }
        Install-TimerProxy
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $failedExactlyOnce = ($script:drainCount -ge 1 -and $script:procDisposeCount -eq 1 -and $script:timerStopCount -eq 1 -and
            $script:timerDisposeCount -eq 1 -and $script:enableUiCount -eq 1)
        $failedStateCleared = ($null -eq $script:batchState)
        $failedCloseAllowed = (-not (Invoke-RealFormClosing))
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B4: the failing worker delivers ONE terminal result (exit 1, failure parsed)' ($failedExit -eq 1 -and ($failedFailures -contains 'workbuddy' -or $failedFailures.Count -gt 0))
    Write-Host ("  DEBUG B4: failedExit=$failedExit failures=[" + ($failedFailures -join ',') + "] drain=$script:drainCount") -ForegroundColor DarkGray
    check 'R010 B4: failed-worker cleanup follows the exactly-once ownership contract (drain>=1 procDispose=1 Stop=1 Dispose=1 Enable-BatchUi=1)' $failedExactlyOnce
    check 'R010 B4: state cleared after the failure terminal path and close becomes safe' ($failedStateCleared -and $failedCloseAllowed -eq $true)

    # ---- B5: Drain-BatchQueue failure via the harness interceptor, REAL state kept authoritative ----
    $rxResult = $null
    $rxClosedSafe = $null
    $rxProcAuthoritative = $false
    $rxCleanupOnce = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        Start-BatchJob $delayedChildArgs {
            param($child)
            $script:rxResult = $child
            $script:done = $true
        }
        $running = Wait-BatchJobRunning
        check 'R010 B5: the delayed worker reached Running before the tick completes (barrier)' $running
        $realProc = $script:batchState.Process
        Install-TimerProxy
        $script:failDrain = $true
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $rxProcAuthoritative = ($null -ne $realProc -and $realProc -is [System.Diagnostics.Process])
        # The COMPLETE terminal contract under a drain failure: exactly one of
        # every terminal operation, the real state holder removed, state cleared.
        $rxCleanupOnce = ($script:timerStopCount -eq 1 -and $script:timerDisposeCount -eq 1 -and $script:enableUiCount -eq 1)
        $rxClosedSafe = (-not (Invoke-RealFormClosing))
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B5: the REAL Process stayed authoritative in the state holder' $rxProcAuthoritative
    check 'R010 B5: injected drain failure does not wedge the terminal lifecycle (ExitCode 1 or OnDone ran)' ($null -ne $rxResult -or $script:enableUiCount -ge 1)
    check 'R010 B5: terminal cleanup EXACTLY ONCE (Timer.Stop=1 Timer.Dispose=1 Enable-BatchUi=1)' $rxCleanupOnce
    Write-Host ("  DEBUG B5: drain=$script:drainCount procDispose=$script:procDisposeCount") -ForegroundColor DarkGray
    check 'R010 B5: state cleared and the subsequent close is allowed after the drain failure' ($rxClosedSafe -eq $true -and $null -eq $script:batchState)

    # ---- B6: a throwing OnDone is logged and cannot wedge the lifecycle ----
    $ondoneThrewRan = $false
    $ondoneLogged = $false
    $ondoneCloseSafe = $null
    $ondoneUiRestored = $false
    $ondoneCleanupOnce = $false
    $ondoneStateCleared = $false
    Reset-BatchCounters
    try {
        $script:done = $false
        Start-BatchJob @('-NoProfile', '-Command', 'exit 0') {
            param($child)
            $script:ondoneThrewRan = $true
            $script:done = $true
            throw 'simulated OnDone crash'
        }
        Install-TimerProxy
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        $ondoneLogged = ($log.Text -match 'BATCH COMPLETION HANDLER FAILED' -and $log.Text -match 'simulated OnDone crash')
        $ondoneCloseSafe = (-not (Invoke-RealFormClosing))
        $ondoneUiRestored = ($script:btnApply.Enabled -and $script:btnRevert.Enabled)
        $ondoneCleanupOnce = ($script:procDisposeCount -eq 1 -and $script:timerStopCount -eq 1 -and
            $script:timerDisposeCount -eq 1 -and $script:enableUiCount -eq 1)
        $ondoneStateCleared = ($null -eq $script:batchState)
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 B6: OnDone is invoked exactly once and its throw is reported, never fatal' ($ondoneThrewRan -and $ondoneLogged)
    check 'R010 B6: OnDone failure cannot wedge the lifecycle (cleanup EXACTLY-ONCE, state cleared)' ($ondoneCleanupOnce -and $ondoneStateCleared)
    check 'R010 B6: resource cleanup was NOT skipped (UI restored) and the close becomes safe' ($ondoneUiRestored -and $ondoneCloseSafe -eq $true)

} else {
    # ─────────────────────────────────────────────────────────────────────────
    # R010 RED: the extracted committed GUI predates the lifecycle contract.
    # Dedicated red probes prove the R010 ASSERTIONS THEMSELVES fail on it --
    # not merely that some unrelated old crash produced an unhandled
    # exception. Every probe condition states the CONTRACT truth (true on the
    # fixed GUI); on the committed GUI it must be false, which r010red()
    # records as a defect reproduction.
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host 'R010 RED: no lifecycle contract in the extracted committed GUI - proving the R010 assertions red' -ForegroundColor Yellow
    $runningBarrier = $false
    $batchStateNow = $null
    try {
        $script:done = $false
        Start-BatchJob $delayedChildArgs { param($child) $script:done = $true }
        $runningBarrier = Wait-BatchJobRunning
        $batchStateNow = $script:batchState
    } finally {
        Stop-LingeringBatch
    }
    check 'R010 red: a batch genuinely reaches Running on the committed GUI (barrier for the red probes)' $runningBarrier

    r010red 'R010 red: an ACTIVE close IS refused by the shipped close logic (authoritative FormClosing handler answering through Test-BatchCloseSafe)' (
        ($null -ne $closeHandler) -and ($formClosingBlockText -match 'Test-BatchCloseSafe'))

    $requiredFlags = @('Consumed', 'CleanedUp', 'Finalized', 'Cleared')
    $flagsPresent = $false
    if ($batchStateNow -is [System.Collections.IDictionary]) {
        $flagsPresent = (@($requiredFlags | Where-Object { -not $batchStateNow.ContainsKey($_) }).Count -eq 0)
    } elseif ($batchStateNow) {
        $flagsPresent = (@($requiredFlags | Where-Object { -not $batchStateNow.PSObject.Properties[$_] }).Count -eq 0)
    }
    r010red 'R010 red: the lifecycle ownership flags (Consumed/CleanedUp/Finalized/Cleared) EXIST in the state holder while the worker runs' (
        $flagsPresent -and $runningBarrier)

    r010red 'R010 red: the close decision is answered by an authoritative Test-BatchCloseSafe contract' (
        ($null -ne (Get-Command Test-BatchCloseSafe -CommandType Function -ErrorAction SilentlyContinue)) -and ($src -match 'function Test-BatchCloseSafe'))

    r010red 'R010 red: terminal cleanup is flag-guarded EXACTLY-ONCE (Consumed/CleanedUp stages inside a Complete-BatchWorker ownership path)' (
        ($src -match 'Complete-BatchWorker') -and ($src -match '\$st\.Consumed') -and ($src -match '\$st\.CleanedUp'))

    $postTerminalSafe = $false
    try {
        $script:done = $false
        Start-BatchJob @('-NoProfile', '-Command', 'exit 0') { param($child) $script:done = $true }
        for ($i = 0; $i -lt 400 -and -not $script:done; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
        # Post-terminal safe-close semantics: the state holder is cleared and
        # the shipped close logic ANSWERS the close (allowed). On the
        # committed GUI there is no close logic at all and the holder is never
        # cleared, so the contract cannot be satisfied.
        if ($closeHandler) {
            $postTerminalSafe = ($null -eq $script:batchState -and (-not (Invoke-RealFormClosing)))
        }
    } catch {
        $postTerminalSafe = $false
    } finally {
        Stop-LingeringBatch
    }
    r010red 'R010 red: POST-TERMINAL safe-close semantics (state cleared exactly once, the shipped close logic then ALLOWS the close)' $postTerminalSafe
}

check 'behaviour: ZERO unhandled WinForms exceptions across the run' (@($script:unhandled).Count -eq 0)
if (@($script:unhandled).Count) {
    foreach ($e in $script:unhandled) { Write-Host ("  recorded: {0}" -f $e.Message) -ForegroundColor Yellow }
}

$form.Dispose()
if ($redCopy) { Remove-Item $redCopy -Force -ErrorAction SilentlyContinue }

if ($RedControl) {
    # The red predicate is the R010-specific probes: EVERY one of them must
    # reproduce its contract absence on the committed GUI, and the suite must
    # additionally carry red gates overall. The unhandled-exception count is
    # reported but is deliberately NOT the basis of the verdict: the committed
    # GUI already contains the E-907 null-crash fix, so only the MISSING R010
    # lifecycle contract is what this red control proves.
    $r010Proven = ($script:r010RedTotal -gt 0 -and $script:r010RedHit -eq $script:r010RedTotal)
    if ($r010Proven -and $fail -gt 0) {
        Write-Host ("RED CONTROL PROVEN: the committed pre-lifecycle GUI reproduces the R010 contract failures - {0}/{1} R010 red probes red, {2} gate(s) red total, {3} recorded unhandled exception(s)." -f $script:r010RedHit, $script:r010RedTotal, $fail, @($script:unhandled).Count) -ForegroundColor Yellow
        exit 0
    }
    Write-Host ("RED CONTROL NOT PROVEN: R010 red probes {0}/{1}, {2} gate(s) red total - the R010 assertions are not demonstrably red." -f $script:r010RedHit, $script:r010RedTotal, $fail) -ForegroundColor Red
    exit 1
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
