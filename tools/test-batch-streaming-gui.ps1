# Process-level Windows acceptance gate for SRC-028:R014 PERF-004.
# Runs the shipped batch implementation against delayed child PowerShell
# processes on a real WinForms message pump. Missing WinForms is a hard failure.
[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$SubjectGui,
    [string]$Probe
)

$ErrorActionPreference = 'Stop'
$global:passCount = 0
$global:failCount = 0
$global:startedAt = [System.Diagnostics.Stopwatch]::StartNew()
$rootH = Split-Path $PSScriptRoot -Parent
$guiH = Join-Path $rootH 'desktop\WintageInstaller.ps1'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $SubjectGui) { $SubjectGui = $guiH }

function check([string]$label, $condition) {
    if ($condition) { Write-Host "PASS: $label" -ForegroundColor Green; $global:passCount++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $global:failCount++ }
}

if ($List) {
    Write-Host 'test-batch-streaming-gui.ps1: real 100k child stream, WinForms heartbeat, bounded queue/logs, EOF, close, result classification, and executed RED mutants.'
    exit 0
}

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host 'UNSUPPORTED: this acceptance gate requires Windows PowerShell 5.1.' -ForegroundColor Red
    exit 2
}
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $probeBox = New-Object System.Windows.Forms.TextBox
    $probeBox.Dispose()
} catch {
    Write-Host ("UNSUPPORTED: real WinForms controls could not be created: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 2
}

$baselineSource = [System.IO.File]::ReadAllText($guiH)
$baselineHash = (Get-FileHash -LiteralPath $guiH -Algorithm SHA256).Hash
function Replace-Once([string]$text, [string]$old, [string]$new) {
    $at = $text.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($at -lt 0 -or $text.IndexOf($old, $at + $old.Length, [System.StringComparison]::Ordinal) -ge 0) {
        throw "mutation anchor must occur exactly once: $old"
    }
    return $text.Substring(0, $at) + $new + $text.Substring($at + $old.Length)
}
function Replace-Function([string]$text, [string]$name, [string]$replacement) {
    $tokens = $null; $errors = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "mutant source parse failed before replacing $name" }
    $node = $tree.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "function anchor missing: $name" }
    $start = $node.Extent.StartOffset
    $length = $node.Extent.EndOffset - $start
    return $text.Substring(0, $start) + $replacement + $text.Substring($start + $length)
}
function Get-FunctionText([string]$text, [string]$name) {
    $tokens = $null; $errors = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "source parse failed while locating $name" }
    $node = $tree.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "function anchor missing: $name" }
    return $node.Extent.Text
}

if ($RedControl) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-r014-red-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $whole = $baselineSource
        $whole = Replace-Once $whole '$script:BatchQueueMax = 2000' '$script:BatchQueueMax = 200000 # R014-RED:whole-run queue capture'
        $whole = Replace-Once $whole '$script:BatchDrainLineBudget = 200' '$script:BatchDrainLineBudget = 100000 # R014-RED:whole-run replay'
        $whole = Replace-Once $whole '$script:BatchDrainCharBudget = 8000' '$script:BatchDrainCharBudget = 100000000 # R014-RED:whole-run replay'
        $whole = Replace-Once $whole '        $drained = Drain-BatchQueue $st.Queue' "        if (`$st.Process -and -not `$st.Process.HasExited) { `$drained = '' } else { `$drained = Drain-BatchQueue `$st.Queue } # R014-RED:whole-run delayed replay"

        $oldEnqueue = @'
function Enqueue-BatchItem($item) {
    $q = $global:BatchOutputQueue
    if ($null -eq $q) { $q = New-Object System.Collections.Concurrent.ConcurrentQueue[object]; $global:BatchOutputQueue = $q }
    if ($item -and $item.Kind -ne 'result') {
        if ($global:BatchQueueLines -ge $global:BatchQueueMax) {
            $dropped = 0
            while ($global:BatchQueueLines -ge $global:BatchQueueMax) {
                $disc = $null
                if ($q.TryDequeue([ref]$disc)) {
                    $global:BatchQueueLines--
                    if ($disc -and $disc.Kind -ne 'result') { $dropped++ }
                } else { break }
            }
            if ($dropped -gt 0) {
                $n = New-BatchQueueItem 'out' "[older batch output truncated: $dropped lines]"
                $null = $q.Enqueue($n)
                $global:BatchQueueLines++
            }
        }
    }
    $null = $q.Enqueue($item)
    if ($item -and $item.Kind -ne 'result') { $global:BatchQueueLines++ }
} # R014-RED:result head eviction
'@
        $resultHead = Replace-Function $baselineSource 'Enqueue-BatchItem' $oldEnqueue

        $counter = $baselineSource
        $drainText = Get-FunctionText $counter 'Drain-BatchQueue'
        $drainText = Replace-Once $drainText '            $script:BatchQueueLines--' '            # R014-RED:stale queue occupancy'
        $counter = Replace-Function $counter 'Drain-BatchQueue' $drainText

        $eof = $baselineSource
        $eof = Replace-Once $eof '        if (-not $st.StdoutEof -or -not $st.StderrEof -or -not $st.ResultChannelSettled) { return }' '        # R014-RED:EOF delivery barrier removed'
        $eof = Replace-Once $eof '        if (-not $processExited -or -not $st.StdoutEof -or -not $st.StderrEof -or -not $st.ResultChannelSettled -or $st.CallbacksInFlight -ne 0) { return }' '        if (-not $processExited) { return } # R014-RED:completion EOF barrier removed'
        $eof = Replace-Once $eof '        if ($st.OutputBridge -and ($st.OutputBridge.OutputQueueCount -ne 0 -or $st.OutputBridge.PendingResultCount -ne 0)) { return }' '        # R014-RED:pending channel barrier removed'
        $eof = Replace-Once $eof '        if ($st.CallbacksInFlight -ne 0 -or $bridge.OutputQueueCount -ne 0 -or $bridge.PendingResultCount -ne 0) { return }' '        # R014-RED:pending callbacks barrier removed'
        $eof = Replace-Once $eof '            string line = data;' ('            string line = data;' + "`r`n" + '            if (!isError && line == "FINAL-BEFORE-EXIT") Thread.Sleep(800); // R014-RED:delay final callback')

        $handlers = $baselineSource
        $handlers = Replace-Once $handlers '    $bridge.Attach($proc)' '    # R014-RED:managed handlers attached late'
        $handlers = Replace-Once $handlers '        $proc.BeginErrorReadLine()' ("        `$proc.BeginErrorReadLine()`r`n        Start-Sleep -Milliseconds 2000`r`n        `$bridge.Attach(`$proc) # R014-RED:handlers attached after async reads")

        $mutants = @(
            @{ Name = 'whole-run'; Source = $whole; Probe = 'whole-run'; Markers = @('FAIL: early marker is visible before the child exits', 'FAIL: live transport stays beneath shipped line cap') },
            @{ Name = 'result-head'; Source = $resultHead; Probe = 'result-head'; Markers = @('FAIL: result record survives head overflow') },
            @{ Name = 'stale-counter'; Source = $counter; Probe = 'counter'; Markers = @('FAIL: queue occupancy returns to zero after drain') },
            @{ Name = 'missing-eof'; Source = $eof; Probe = 'eof'; Markers = @('FAIL: final output and machine result survive EOF delivery') },
            @{ Name = 'late-handlers'; Source = $handlers; Probe = 'handlers'; Markers = @('FAIL: early marker arrives through pre-attached async handlers') }
        )
        $allProven = $true
        foreach ($mutant in $mutants) {
            $path = Join-Path $tempRoot ($mutant.Name + '.ps1')
            [System.IO.File]::WriteAllText($path, [string]$mutant.Source, (New-Object System.Text.UTF8Encoding($false)))
            $written = [System.IO.File]::ReadAllText($path)
            $markerPresent = $written.Contains('R014-RED:' + $mutant.Name) -or ($mutant.Name -eq 'result-head' -and $written.Contains('R014-RED:result head eviction')) -or ($mutant.Name -eq 'stale-counter' -and $written.Contains('R014-RED:stale queue occupancy')) -or ($mutant.Name -eq 'missing-eof' -and $written.Contains('R014-RED:EOF delivery barrier removed')) -or ($mutant.Name -eq 'late-handlers' -and $written.Contains('R014-RED:handlers attached after async reads'))
            $childOutput = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -SubjectGui $path -Probe $mutant.Probe 2>&1)
            $childExit = $LASTEXITCODE
            $joined = ($childOutput | ForEach-Object { [string]$_ }) -join "`n"
            $expectedFailures = $true
            foreach ($marker in $mutant.Markers) { if (-not $joined.Contains($marker)) { $expectedFailures = $false } }
            $proven = $markerPresent -and $childExit -ne 0 -and $expectedFailures
            check ("RED mutant {0} was applied and its behavioral oracle exited red" -f $mutant.Name) $proven
            if (-not $proven) {
                $allProven = $false
                Write-Host ("mutant={0} applied={1} childExit={2}; output: {3}" -f $mutant.Name, $markerPresent, $childExit, ($joined.Substring(0, [Math]::Min(1200, $joined.Length)))) -ForegroundColor DarkYellow
            }
        }
        check 'shipped WintageInstaller.ps1 remained byte-identical through RED controls' ((Get-FileHash -LiteralPath $guiH -Algorithm SHA256).Hash -eq $baselineHash)
        Write-Host "`n$($global:passCount) PASS, $($global:failCount) FAIL; elapsed $([Math]::Round($global:startedAt.Elapsed.TotalSeconds, 1))s"
        if ($allProven -and $global:failCount -eq 0) { Write-Host 'R014 RED CONTROL PROVEN: all five executed mutants failed their behavioral gates.' -ForegroundColor Yellow; exit 0 }
        Write-Host 'R014 RED CONTROL NOT PROVEN.' -ForegroundColor Red
        exit 1
    } finally {
        $fullTemp = [System.IO.Path]::GetFullPath($tempRoot)
        $fullBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($fullTemp.StartsWith($fullBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $fullTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$subjectSource = [System.IO.File]::ReadAllText($SubjectGui)
$tokens = $null; $parseErrors = $null
$global:subjectAst = [System.Management.Automation.Language.Parser]::ParseFile($SubjectGui, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    $parseErrors | ForEach-Object { Write-Host ("PARSE FAIL: {0}" -f $_.Message) -ForegroundColor Red }
    exit 1
}

function Get-SubjectFunctionText([string]$name) {
    $node = $global:subjectAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "function not found in tested GUI: $name" }
    return $node.Extent.Text
}
function Get-Setting([string]$text, [string]$name) {
    $pattern = '(?m)^\s*\$script:' + [regex]::Escape($name) + '\s*=\s*(\d+)'
    $m = [regex]::Match($text, $pattern)
    if (-not $m.Success) { throw "numeric setting not found: $name" }
    return [int]$m.Groups[1].Value
}
function Initialize-BatchGlobals {
    $global:BatchQueueMax = Get-Setting $subjectSource 'BatchQueueMax'
    $global:BatchQueueLines = 0
    $global:BatchQueueGate = New-Object object
    $global:BatchQueueRecordCharMax = [Math]::Max(1, (Get-Setting $subjectSource 'BatchDrainCharBudget') - 2)
    $global:BatchDrainLineBudget = Get-Setting $subjectSource 'BatchDrainLineBudget'
    $global:BatchDrainCharBudget = Get-Setting $subjectSource 'BatchDrainCharBudget'
    $global:BatchDroppedLines = 0
    $global:BatchOutputQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    $global:BatchResults = @{}
    $global:BatchResultSeenTarget = @{}
    $global:BatchResultMalformed = $false
    $global:BatchResultMalformedReason = $null
    $global:batchState = $null
    $global:TfSelectedTargets = @()
    $global:LogCharCap = Get-Setting $subjectSource 'LogCharCap'
    $global:LogLowWater = Get-Setting $subjectSource 'LogLowWater'
    $global:LogMaxChunk = Get-Setting $subjectSource 'LogMaxChunk'
    $global:metricGate = New-Object object
    $global:ordinaryReceived = 0
    $global:maxQueueObserved = 0
    $global:maxRecordObserved = 0
    $global:queueMismatchObserved = $false
    $global:maxDrainChars = 0
    $global:maxDrainLines = 0
    $global:drainViolation = $false
    $global:mainAppendCalls = 0
    $global:completeCalls = 0
}

foreach ($name in @('New-BatchQueueItem', 'Set-BatchResultMalformed', 'Add-BatchMachineResult', 'Add-BatchMachineResultFromPayload', 'Enqueue-BatchItem', 'Drain-BatchQueue', 'Add-BoundedLogText', 'Say-Log', 'Say-TfLog', 'Start-BatchJob', 'Complete-BatchWorker', 'Classify-BatchResult', 'Test-BatchCloseSafe')) {
    $functionText = (Get-SubjectFunctionText $name).Replace('$script:', '$global:')
    if ($name -eq 'Say-Log') { $functionText = [regex]::Replace($functionText, '(?<![\w:])\$log\b', '$global:log') }
    if ($name -eq 'Say-TfLog') { $functionText = [regex]::Replace($functionText, '(?<![\w:])\$txtTfLog\b', '$global:txtTfLog') }
    if ($name -eq 'Add-BoundedLogText') {
        foreach ($variable in @('LogCharCap', 'LogLowWater', 'LogMaxChunk')) {
            $functionText = [regex]::Replace($functionText, '(?<![\w:])\$' + $variable + '\b', '$global:' + $variable)
        }
    }
    . ([scriptblock]::Create($functionText))
}

$closeBlockAst = $global:subjectAst.Find({
    param($n)
    if ($n -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
    return ($n.Extent.Text -match 'Test-BatchCloseSafe' -and $n.Extent.Text -match '\$e\.Cancel')
}, $true)
if (-not $closeBlockAst) { throw 'the shipped FormClosing handler was not found in the GUI AST' }
$closeHandlerText = $closeBlockAst.Extent.Text.Replace('Test-BatchCloseSafe', '($null -eq $global:batchState -or $global:batchState.Cleared)')
$global:shippedCloseHandler = [scriptblock]::Create($closeHandlerText)

$global:realEnqueue = (Get-Command Enqueue-BatchItem -CommandType Function).ScriptBlock
function Enqueue-BatchItem($item) {
    if ($item -and $item.Kind -ne 'result') {
        [System.Threading.Monitor]::Enter($global:metricGate)
        try { $global:ordinaryReceived++ } finally { [System.Threading.Monitor]::Exit($global:metricGate) }
    }
    & $global:realEnqueue $item
    if ($item -and $item.Kind -ne 'result') {
        [System.Threading.Monitor]::Enter($global:BatchQueueGate)
        try {
            if ($global:BatchQueueLines -gt $global:maxQueueObserved) { $global:maxQueueObserved = $global:BatchQueueLines }
            if ($item.Text -and $item.Text.Length -gt $global:maxRecordObserved) { $global:maxRecordObserved = $item.Text.Length }
        } finally { [System.Threading.Monitor]::Exit($global:BatchQueueGate) }
    }
}
$global:realDrain = (Get-Command Drain-BatchQueue -CommandType Function).ScriptBlock
function Drain-BatchQueue([System.Collections.Concurrent.ConcurrentQueue[object]]$q) {
    $chunk = [string](& $global:realDrain $q)
    if ($chunk) {
        $lines = @($chunk -split "`r?`n" | Where-Object { $_.Length -gt 0 }).Count
        if ($chunk.Length -gt $global:maxDrainChars) { $global:maxDrainChars = $chunk.Length }
        if ($lines -gt $global:maxDrainLines) { $global:maxDrainLines = $lines }
        if ($chunk.Length -gt $global:BatchDrainCharBudget -or $lines -gt $global:BatchDrainLineBudget) { $global:drainViolation = $true }
    }
    $gate = $global:BatchQueueGate
    [System.Threading.Monitor]::Enter($gate)
    try { if ($null -ne $q -and $global:BatchQueueLines -ne $q.Count) { $global:queueMismatchObserved = $true } }
    finally { [System.Threading.Monitor]::Exit($gate) }
    return $chunk
}
$global:realBounded = (Get-Command Add-BoundedLogText -CommandType Function).ScriptBlock
function Add-BoundedLogText([System.Windows.Forms.TextBox]$box, [string]$text) {
    if ($global:log -and [object]::ReferenceEquals($box, $global:log)) { $global:mainAppendCalls++ }
    & $global:realBounded $box $text
}
$global:realComplete = (Get-Command Complete-BatchWorker -CommandType Function).ScriptBlock
function Complete-BatchWorker($st) {
    $global:completeCalls++
    $global:completeHadOnDone = [bool]$st.OnDone
    $global:completeOnDoneText = if ($st.OnDone) { $st.OnDone.ToString() } else { '<null>' }
    $global:completeStateBefore = "done=$($st.Done) consumed=$($st.Consumed) clean=$($st.CleanedUp) finalized=$($st.Finalized) exited=$($st.HasExited) eof=$($st.StdoutEof)/$($st.StderrEof) settled=$($st.ResultChannelSettled) callbacks=$($st.CallbacksInFlight)"
    if ($st.OnDone) {
        $global:originalCompletionHandler = $st.OnDone
        $global:completeOnDoneCalled = $false
        $st.OnDone = { param($doneState) $global:completeOnDoneCalled = $true; & $global:originalCompletionHandler $doneState }
    }
    & $global:realComplete $st
}
function Disable-BatchUi { }
function Enable-BatchUi { }
function Get-CurrentBatchState { return $global:batchState }
function Get-QueueSnapshot {
    $gate = $global:BatchQueueGate
    [System.Threading.Monitor]::Enter($gate)
    try {
        return [pscustomobject]@{ Lines = $global:BatchQueueLines; Count = $global:BatchOutputQueue.Count; Dropped = $global:BatchDroppedLines }
    } finally { [System.Threading.Monitor]::Exit($gate) }
}
function Set-TestQueueCounter([int]$value) {
    [System.Threading.Monitor]::Enter($global:BatchQueueGate)
    try { $global:BatchQueueLines = $value } finally { [System.Threading.Monitor]::Exit($global:BatchQueueGate) }
}

function Run-QueueProbes {
    Initialize-BatchGlobals
    $global:BatchQueueMax = 3
    $global:BatchDrainLineBudget = 10
    $global:BatchDrainCharBudget = 200
    $global:BatchQueueRecordCharMax = 198
    $global:TfSelectedTargets = @('fixture-alpha')
    $global:BatchResults = @{}
    $global:BatchResultSeenTarget = @{}
    $global:batchState = @{ ExpectedTargets = @('fixture-alpha'); ResultsByTarget = $global:BatchResults; ResultMalformed = $false; ResultMalformedReason = $null }
    $q = $global:BatchOutputQueue
    $result = New-BatchQueueItem 'result' 'wintage-result fixture-alpha'
    $result | Add-Member -NotePropertyName Payload -NotePropertyValue ([pscustomobject]@{ target = 'fixture-alpha'; status = 'SUCCESS'; code = 0 })
    $null = $q.Enqueue($result)
    foreach ($i in 1..3) { $null = $q.Enqueue((New-BatchQueueItem 'out' ("ordinary-$i"))) }
    $global:BatchQueueLines = 3
    Enqueue-BatchItem (New-BatchQueueItem 'out' 'newest-output')
    $snap = Get-QueueSnapshot
    check 'result record survives head overflow' ($global:BatchResults.ContainsKey('fixture-alpha') -and $global:BatchResultSeenTarget.ContainsKey('fixture-alpha'))
    check 'ordinary occupancy equals queue count after result-head pressure' ($snap.Lines -eq $snap.Count -and $snap.Count -le $global:BatchQueueMax)
    $chunk = Drain-BatchQueue $q
    check 'overflow is reported with one coarse truncation notice' ($chunk -match 'older batch output truncated')
    check 'queue occupancy returns to zero after drain' ($global:BatchQueueLines -eq 0 -and $q.Count -eq 0)
    Add-BatchMachineResult 'fixture-alpha' 'FAILED' 9 $global:batchState
    Add-BatchMachineResult 'fixture-alpha' 'SUCCESS' 0 $global:batchState
    check 'duplicate target record keeps the latest machine result' ($global:BatchResults['fixture-alpha'].status -eq 'SUCCESS' -and $global:BatchResults.Count -eq 1)
    $global:batchState.ExitCode = 0
    check 'latest duplicate classifies from the authoritative result channel' ((Classify-BatchResult $global:batchState).Kind -eq 'SUCCESS')
}

function New-FixtureScript([string]$path) {
    $fixture = @'
param([string]$Scenario)
if ($PSVersionTable.PSVersion.Major -ne 5) { [Console]::Error.WriteLine('fixture requires Windows PowerShell 5.1'); exit 91 }
switch ($Scenario) {
    'success' {
        [Console]::Out.WriteLine('EARLY-MARKER')
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        Start-Sleep -Milliseconds 900
        for ($batch = 0; $batch -lt 5; $batch++) {
            for ($i = 0; $i -lt 20000; $i++) { [Console]::Out.WriteLine(('ordinary-{0}-{1}' -f $batch, $i)) }
            if ($batch -eq 2) { [Console]::Out.WriteLine('MIDDLE-MARKER'); Start-Sleep -Milliseconds 1500 }
            else { Start-Sleep -Milliseconds 90 }
        }
        [Console]::Out.WriteLine(('LONG-ORDINARY:' + ('x' * 20000) + ':LONG-END-MARKER'))
        [Console]::Out.WriteLine('FINAL-OUTPUT-MARKER')
        [Console]::Error.WriteLine('FINAL-ERROR-MARKER')
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-beta","status":"SUCCESS","code":0}')
        exit 0
    }
    'second' {
        Start-Sleep -Milliseconds 700
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-second","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('SECOND-BATCH-MARKER')
        exit 0
    }
    'failure' {
        [Console]::Out.WriteLine('EARLY-FAILURE-MARKER')
        [Console]::Error.WriteLine('TERMINAL-ERROR-MARKER')
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-fail","status":"FAILED","code":7}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 7
    }
    'nonzero-success' {
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 7
    }
    'partial' {
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-beta","status":"FAILED","code":1}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 1
    }
    'duplicate' {
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"FAILED","code":9}')
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 0
    }
    'malformed' {
        [Console]::Out.WriteLine('wintage-result: {bad-json')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 0
    }
    'missing' {
        [Console]::Out.WriteLine('ordinary output without a result record')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 0
    }
    'eof' {
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 0
    }
    'handlers' {
        [Console]::Out.WriteLine('EARLY-MARKER')
        Start-Sleep -Milliseconds 4500
        [Console]::Out.WriteLine('wintage-result: {"target":"fixture-alpha","status":"SUCCESS","code":0}')
        [Console]::Out.WriteLine('FINAL-BEFORE-EXIT')
        exit 0
    }
}
exit 92
'@
    [System.IO.File]::WriteAllText($path, $fixture, (New-Object System.Text.UTF8Encoding($false)))
}

function Run-ProcessScenario([string]$scenario, [string[]]$targets, [int]$expectedExit, [string]$expectedKind, [bool]$heavy = $false, [bool]$resetSentinel = $false, [bool]$throwOnDone = $false) {
    Initialize-BatchGlobals
    $global:throwOnDone = $throwOnDone
    $global:TfSelectedTargets = @($targets)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'R014 process acceptance'
    $form.Width = 640; $form.Height = 320; $form.ShowInTaskbar = $false
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
    $log.MaxLength = [Int32]::MaxValue; $log.Dock = 'Fill'
    $form.Controls.Add($log)
    $global:log = $log
    $ctx = [pscustomobject]@{
        Form = $form; Log = $log; Scenario = $scenario; Started = $null; Completed = $false
        Classification = $null; CompletionState = $null; CompletionError = $null; StateWasCleared = $false
        StateAtDone = $null; Heartbeat = 0; ActiveHeartbeat = 0; TransportHighWaterObserved = 0; ProgressiveBeforeExit = $false
        MiddleVisible = $false; CloseAttempted = $false; CloseRefused = $false; CloseProcessAlive = $false
        TerminalCloseAllowed = $false; ShippedCancelledAtAttempt = $false; CloseSafeAtAttempt = $null; ClearedAtAttempt = $null; QueueAtStartReturn = -1; ExpectedTargets = @($targets)
        LogText = ''; TimedOut = $false; Watchdog = ''; ProcessId = 0; Elapsed = 0; Copyable = $false
        TerminalCloseAttempted = $false
    }
    $runCtx = $ctx
    $global:runCtx = $ctx
    $closeDelegate = [System.Windows.Forms.FormClosingEventHandler]$global:shippedCloseHandler
    $form.add_FormClosing($closeDelegate)
    $form.Add_FormClosing(({
        param($sender, $eventArgs)
        if ($runCtx.Completed) { $runCtx.TerminalCloseAllowed = -not $eventArgs.Cancel }
    }.GetNewClosure()))
    # The AST-extracted handler above is also invoked directly at the close
    # probe below; this delegate bridges the same lifecycle guard into this
    # isolated test Form's private PowerShell scope.
    $form.Add_FormClosing(({
        param($sender, $eventArgs)
        if ($global:batchState -and -not $global:batchState.Cleared) { $eventArgs.Cancel = $true }
    }.GetNewClosure()))

    $heartbeat = New-Object System.Windows.Forms.Timer
    $heartbeat.Interval = 20
    $heartbeat.Add_Tick(({
        $runCtx.Heartbeat++
        $state = Get-CurrentBatchState
        $alive = $false
        if ($state -and $state.Process) {
            if ($state.OutputBridge -and $state.OutputBridge.MaxOutputQueueObserved -gt $runCtx.TransportHighWaterObserved) {
                $runCtx.TransportHighWaterObserved = [int]$state.OutputBridge.MaxOutputQueueObserved
            }
            try { $alive = -not [bool]$state.Process.HasExited } catch { }
            if ($alive) { $runCtx.ActiveHeartbeat++ }
            if ($runCtx.Log.Text.Contains('EARLY-MARKER') -and $alive) { $runCtx.ProgressiveBeforeExit = $true }
            if ($runCtx.Log.Text.Contains('MIDDLE-MARKER')) { $runCtx.MiddleVisible = $true }
            if ($runCtx.Scenario -eq 'success' -and -not $runCtx.CloseAttempted -and $runCtx.Started.ElapsedMilliseconds -gt 300) {
                $runCtx.CloseAttempted = $true
                $runCtx.CloseProcessAlive = $alive
                $runCtx.CloseSafeAtAttempt = Test-BatchCloseSafe
                $runCtx.ClearedAtAttempt = if ($state) { [bool]$state.Cleared } else { $null }
                $runCtx.ShippedCancelledAtAttempt = -not $runCtx.CloseSafeAtAttempt
                $runCtx.Form.Close()
                $runCtx.CloseRefused = -not $runCtx.Form.IsDisposed
            }
        }
        if ($runCtx.Completed -and -not $runCtx.TerminalCloseAttempted) {
            $runCtx.TerminalCloseAttempted = $true
            $runCtx.LogText = $runCtx.Log.Text
            if ($runCtx.StateAtDone -and $runCtx.CompletionState) { $runCtx.StateAtDone.Cleared = [bool]$runCtx.CompletionState.Cleared }
            $runCtx.Log.SelectionStart = 0
            $runCtx.Log.SelectionLength = [Math]::Min(12, $runCtx.Log.TextLength)
            $runCtx.Copyable = ($runCtx.Log.SelectedText.Length -gt 0)
            $runCtx.Form.Close()
        }
        if ($runCtx.Started -and $runCtx.Started.Elapsed.TotalSeconds -gt 10 -and -not $runCtx.Completed -and -not $runCtx.TimedOut) {
            $runCtx.TimedOut = $true
            $state = Get-CurrentBatchState
            $runCtx.Watchdog = "batchStateNull=$($null -eq $state) completeCalls=$global:completeCalls onDone=$global:completeHadOnDone invoked=$global:completeOnDoneCalled completed=$($runCtx.Completed) processId=$($runCtx.ProcessId) before=[$global:completeStateBefore] onDoneBody=$($global:completeOnDoneText)"
            if ($state) {
                $exited = $false
                try { $exited = [bool]$state.Process.HasExited } catch { }
                $snapshot = Get-QueueSnapshot
                $runCtx.Watchdog += " exit=$exited stdoutEOF=$($state.StdoutEof) stderrEOF=$($state.StderrEof) resultSettled=$($state.ResultChannelSettled) callbacks=$($state.CallbacksInFlight) transport=$($state.OutputBridge.OutputQueueCount)/$($state.OutputBridge.MaxOutputQueueObserved) queue=$($snapshot.Lines)/$($snapshot.Count)"
                try { $state.Timer.Stop(); $state.Timer.Dispose(); $state.TimerDisposed = $true } catch { }
                if (-not $exited) {
                    try { $state.Process.Kill(); $null = $state.Process.WaitForExit(3000) } catch { }
                }
                try { $state.Process.remove_OutputDataReceived($state.OutputHandler) } catch { }
                try { $state.Process.remove_ErrorDataReceived($state.ErrorHandler) } catch { }
                try { $state.Process.Dispose(); $state.ProcessDisposed = $true } catch { }
                $state.Cleared = $true
                $global:batchState = $null
            }
            try { $runCtx.Form.Remove_FormClosing($global:shippedCloseHandler) } catch { }
            try { $runCtx.Form.Close() } catch { }
        }
    }.GetNewClosure()))
    $heartbeat.Start()

    $fixturePath = Join-Path $global:fixtureRoot 'fixture-child.ps1'
    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $fixturePath, '-Scenario', $scenario)
    $form.Add_Shown(({
        $runCtx.Started = [System.Diagnostics.Stopwatch]::StartNew()
        if ($resetSentinel) { Set-TestQueueCounter 777 }
        $onDone = {
            param($st)
            $global:runCtx.Completed = $true
            $global:runCtx.CompletionState = $st
            $global:runCtx.ProcessId = [int]$st.ProcessId
            if ($global:throwOnDone) { throw 'R014 intentional OnDone exception' }
            try {
                $global:runCtx.Classification = Classify-BatchResult $st
                Say-Log ("TERMINAL: " + $global:runCtx.Classification.Message)
                Say-TfLog ("TERMINAL: " + $global:runCtx.Classification.Message)
            } catch {
                $global:runCtx.CompletionError = $_.Exception.Message
                Say-Log ("TERMINAL CALLBACK ERROR: " + $_.Exception.Message)
            }
            $global:runCtx.StateAtDone = [pscustomobject]@{
                ExitCode = $st.ExitCode; HasExited = $st.HasExited; StdoutEof = $st.StdoutEof
                StderrEof = $st.StderrEof; ResultChannelSettled = $st.ResultChannelSettled
                CallbacksInFlight = $st.CallbacksInFlight; Consumed = $st.Consumed
                CleanedUp = $st.CleanedUp; Finalized = $st.Finalized; Cleared = $st.Cleared
                ProcessDisposed = $st.ProcessDisposed; TimerDisposed = $st.TimerDisposed
                ResultCount = $st.ResultsByTarget.Count
                TransportReceived = $st.OutputBridge.ReceivedOrdinaryLines
                TransportMaxQueue = $st.OutputBridge.MaxOutputQueueObserved
                TransportMaxRecord = $st.OutputBridge.MaxRecordObserved
                TransportQueueCount = $st.OutputBridge.OutputQueueCount
            }
        }.GetNewClosure()
        try {
            Start-BatchJob $childArgs $onDone
        } catch {
            $runCtx.CompletionError = $_.Exception.ToString()
            $runCtx.Form.Close()
            return
        }
        $runCtx.QueueAtStartReturn = (Get-QueueSnapshot).Lines
    }.GetNewClosure()))

    try {
        [System.Windows.Forms.Application]::Run($form)
    } finally {
        $heartbeat.Stop(); $heartbeat.Dispose()
        $ctx.Elapsed = if ($ctx.Started) { $ctx.Started.Elapsed.TotalSeconds } else { 0 }
        if (-not $log.IsDisposed) {
            $ctx.LogText = $log.Text
            $log.SelectionStart = 0
            $log.SelectionLength = [Math]::Min(12, $log.TextLength)
            $ctx.Copyable = ($log.SelectedText.Length -gt 0)
        }
        $ctx.StateWasCleared = ($null -eq $global:batchState)
        try { $form.Dispose() } catch { }
    }
    check ("$scenario process scenario completed before the 10s watchdog") (-not $ctx.TimedOut -and $ctx.Completed)
    if ($ctx.TimedOut) { Write-Host ("WATCHDOG: {0}; completionError={1}; log={2}" -f $ctx.Watchdog, $ctx.CompletionError, $ctx.LogText) -ForegroundColor DarkYellow }
    if (-not $ctx.Completed) { Write-Host ("SCENARIO DIAGNOSTIC: {0}; error={1}; closeAttempted={2}; closeSafe={3}; stateCleared={4}; guardCancel={5}; closeRefused={6}; childAliveAtClose={7}; heartbeat={8}; elapsed={9}s; log={10}" -f $scenario, $ctx.CompletionError, $ctx.CloseAttempted, $ctx.CloseSafeAtAttempt, $ctx.ClearedAtAttempt, $ctx.ShippedCancelledAtAttempt, $ctx.CloseRefused, $ctx.CloseProcessAlive, $ctx.Heartbeat, [Math]::Round($ctx.Elapsed, 2), $ctx.LogText) -ForegroundColor DarkYellow }
    return $ctx
}

function Run-LogSurfaceProbe {
    $oldCaps = @($global:LogCharCap, $global:LogLowWater, $global:LogMaxChunk)
    # The behavior is the shipped helper; scale its test window to force the
    # same trim path with small, quick WinForms appends.
    $global:LogCharCap = 40000; $global:LogLowWater = 30000; $global:LogMaxChunk = 10000
    $bd = New-Object System.Windows.Forms.TextBox
    $tf = New-Object System.Windows.Forms.TextBox
    foreach ($box in @($bd, $tf)) { $box.Multiline = $true; $box.MaxLength = [Int32]::MaxValue }
    $oldLogForProbe = $global:log; $global:log = $bd; $global:txtTfLog = $tf
    try {
        for ($i = 0; $i -lt 5; $i++) {
            Say-Log ('bd-' + ('b' * 10000))
            Say-TfLog ('tf-' + ('t' * 10000))
        }
        Say-Log 'MAIN-LATEST-ERROR'
        Say-TfLog 'TF-LATEST-ERROR'
        check 'MAIN log retention remains within its cap and keeps newest error' ($bd.TextLength -le $global:LogCharCap -and $bd.Text.Contains('MAIN-LATEST-ERROR'))
        check 'TF log retention remains within its cap and keeps newest error' ($tf.TextLength -le $global:LogCharCap -and $tf.Text.Contains('TF-LATEST-ERROR'))
        foreach ($box in @($bd, $tf)) {
            $box.SelectionStart = 0
            $box.SelectionLength = [Math]::Min(12, $box.TextLength)
            if ([object]::ReferenceEquals($box, $bd)) { check 'MAIN retained text remains selectable/copyable' ($box.SelectedText.Length -gt 0) }
            else { check 'TF retained text remains selectable/copyable' ($box.SelectedText.Length -gt 0) }
        }
    } finally {
        $global:LogCharCap = $oldCaps[0]; $global:LogLowWater = $oldCaps[1]; $global:LogMaxChunk = $oldCaps[2]
        $global:log = $oldLogForProbe
        $bd.Dispose(); $tf.Dispose()
    }
}

if ($Probe) {
    $global:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-r014-fixture-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $global:fixtureRoot -Force | Out-Null
    try {
        New-FixtureScript (Join-Path $global:fixtureRoot 'fixture-child.ps1')
        Initialize-BatchGlobals
        if ($Probe -eq 'result-head') {
            Run-QueueProbes
        } elseif ($Probe -eq 'counter') {
            $global:BatchQueueMax = 10; $global:BatchDrainLineBudget = 10; $global:BatchDrainCharBudget = 200; $global:BatchQueueRecordCharMax = 198
            foreach ($i in 1..3) { Enqueue-BatchItem (New-BatchQueueItem 'out' ("counter-$i")) }
            $null = Drain-BatchQueue $global:BatchOutputQueue
            check 'queue occupancy returns to zero after drain' ($global:BatchQueueLines -eq 0 -and $global:BatchOutputQueue.Count -eq 0)
        } elseif ($Probe -eq 'whole-run') {
            $ctx = Run-ProcessScenario 'success' @('fixture-alpha','fixture-beta') 0 'SUCCESS' $true $false
            check 'early marker is visible before the child exits' $ctx.ProgressiveBeforeExit
            check 'live transport stays beneath shipped line cap' ($ctx.TransportHighWaterObserved -le (Get-Setting $baselineSource 'BatchQueueMax'))
            check 'active close guard canceled close and preserved the running child' ($ctx.CloseAttempted -and -not $ctx.CloseSafeAtAttempt -and $ctx.ShippedCancelledAtAttempt -and $ctx.CloseRefused -and $ctx.CloseProcessAlive)
        } elseif ($Probe -eq 'eof') {
            $ctx = Run-ProcessScenario 'eof' @('fixture-alpha') 0 'SUCCESS' $false $false
            $finalPresent = $ctx.LogText.Contains('FINAL-BEFORE-EXIT') -and $ctx.StateAtDone -and $ctx.StateAtDone.StdoutEof -and $ctx.StateAtDone.StderrEof -and $ctx.StateAtDone.ResultChannelSettled
            check 'final output and machine result survive EOF delivery' $finalPresent
            if (-not $finalPresent) { Write-Host ("EOF DIAGNOSTIC: log={0}; appends={1}; queued={2}; state={3}" -f $ctx.LogText, $global:mainAppendCalls, $global:ordinaryReceived, ($ctx.StateAtDone | Format-List * | Out-String)) -ForegroundColor DarkYellow }
        } elseif ($Probe -eq 'handlers') {
            $ctx = Run-ProcessScenario 'handlers' @('fixture-alpha') 0 'SUCCESS' $false $false
            check 'early marker arrives through pre-attached async handlers' ($ctx.LogText.Contains('EARLY-MARKER') -and $ctx.ProgressiveBeforeExit)
        } else {
            # The dispatch used to end here without a branch, so a typo'd -Probe name
            # ran none of the five probes, printed no assertion and still exited 0:
            # a probe gate that cannot fail on a value it does not recognise is the
            # T-377 tautology in a switch costume. This is the guard the dead switch
            # dispatcher used to provide, now on the code that actually runs.
            throw "unknown RED probe: $Probe"
        }
    } finally {
        $fullTemp = [System.IO.Path]::GetFullPath($global:fixtureRoot)
        $fullBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($fullTemp.StartsWith($fullBase, [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fullTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "`n$($global:passCount) PASS, $($global:failCount) FAIL; elapsed $([Math]::Round($global:startedAt.Elapsed.TotalSeconds, 1))s"
    if ((Get-FileHash -LiteralPath $guiH -Algorithm SHA256).Hash -ne $baselineHash) { Write-Host 'FAIL: shipped source changed during behavioral probe'; exit 1 }
    if ($global:failCount -gt 0) { exit 1 }
    exit 0
}

$global:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-r014-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $global:fixtureRoot -Force | Out-Null
try {
    New-FixtureScript (Join-Path $global:fixtureRoot 'fixture-child.ps1')
    Initialize-BatchGlobals
    $startText = Get-SubjectFunctionText 'Start-BatchJob'
    $enqueueText = Get-SubjectFunctionText 'Enqueue-BatchItem'
    $drainText = Get-SubjectFunctionText 'Drain-BatchQueue'
    $boundedText = Get-SubjectFunctionText 'Add-BoundedLogText'
    $attachAt = $startText.IndexOf('$bridge.Attach($proc)')
    $processStartAt = $startText.IndexOf('$proc.Start()')
    check 'struct: managed stdout/stderr handlers attach before Process.Start and Begin*ReadLine' ($attachAt -ge 0 -and $attachAt -lt $processStartAt -and $attachAt -lt $startText.IndexOf('$proc.BeginOutputReadLine()'))
    check 'struct: completion requires both stream EOFs, result settlement, idle callbacks and drained channels' ($startText -match 'StdoutEof' -and $startText -match 'StderrEof' -and $startText -match 'ResultChannelSettled' -and $startText -match 'CallbacksInFlight' -and $startText -match 'OutputQueueCount')
    check 'struct: machine results bypass ordinary queue and malformed records fail closed' ($startText -match 'Add-BatchMachineResultFromPayload' -and $startText -notmatch "Enqueue-BatchItem\s*\(New-BatchQueueItem 'result'")
    check 'struct: transport caps records and per-tick characters; ordinary occupancy decrements on drain' ($startText -match 'recordMax' -and $startText -match 'charBudget' -and $enqueueText -match 'BatchQueueRecordCharMax' -and $drainText -match 'charBudget' -and $drainText -match 'BatchQueueLines--')
    check 'struct: all three log surfaces use one bounded helper and one scroll per chunk' ($subjectSource -match 'function Say-Log[\s\S]{0,320}Add-BoundedLogText' -and $subjectSource -match 'function Say-TfLog[\s\S]{0,320}Add-BoundedLogText' -and ([regex]::Matches($boundedText, '\.ScrollToCaret\s*\(').Count -eq 1))
    check 'struct: shipped FormClosing event uses the batch lifecycle guard and cancels active close' ($subjectSource -match '\$form\.Add_FormClosing\(\{[\s\S]{0,400}Test-BatchCloseSafe[\s\S]{0,160}\$e\.Cancel\s*=\s*\$true')

    Run-QueueProbes
    $success = Run-ProcessScenario 'success' @('fixture-alpha','fixture-beta') 0 'SUCCESS' $true $false
    check 'delayed real child delivered at least 100,000 ordinary lines in five intervals' ($success.StateAtDone.TransportReceived -ge 100000)
    check 'early output became visible before process exit' $success.ProgressiveBeforeExit
    check 'middle marker became visible during the child run' $success.MiddleVisible
    check 'independent WinForms heartbeat advanced while child was active' ($success.ActiveHeartbeat -ge 10)
    check 'active close guard refused close and left child alive' ($success.CloseAttempted -and -not $success.CloseSafeAtAttempt -and $success.ShippedCancelledAtAttempt -and $success.CloseRefused -and $success.CloseProcessAlive)
    check 'machine results before and after output pressure both survived' ($success.Classification.Kind -eq 'SUCCESS' -and $success.StateAtDone.ResultCount -eq 2)
    check 'final stdout/error lines and pre-exit machine record survived' ($success.LogText.Contains('FINAL-OUTPUT-MARKER') -and $success.LogText.Contains('FINAL-ERROR-MARKER') -and $success.StateAtDone.StdoutEof -and $success.StateAtDone.StderrEof -and $success.StateAtDone.ResultChannelSettled)
    check 'long ordinary line is capped and its newest suffix stays visible' ($success.LogText.Contains('LONG-END-MARKER') -and $success.StateAtDone.TransportMaxRecord -le $global:BatchQueueRecordCharMax)
    check 'queue and per-tick line/character budgets stayed bounded' ($success.TransportHighWaterObserved -le $global:BatchQueueMax -and $global:maxQueueObserved -le $global:BatchQueueMax -and -not $global:queueMismatchObserved -and -not $global:drainViolation)
    check 'queue occupancy returned to zero after full drain' ((Get-QueueSnapshot).Lines -eq 0 -and (Get-QueueSnapshot).Count -eq 0)
    check 'main log retention cap and newest terminal status survived 100k lines' ($success.LogText.Length -le $global:LogCharCap -and $success.LogText.Contains('TERMINAL: apply done. (SUCCESS)'))
    check 'recent main log text remains selectable/copyable' $success.Copyable
    check 'UI appended drained chunks, not one append per source line' ($global:mainAppendCalls -lt ($global:ordinaryReceived / 10))
    check 'terminal cleanup and callbacks were exactly once; terminal close was safe' ($success.StateAtDone.Consumed -and $success.StateAtDone.CleanedUp -and $success.StateAtDone.Finalized -and $success.StateAtDone.ProcessDisposed -and $success.StateAtDone.TimerDisposed -and $success.StateWasCleared -and $success.TerminalCloseAllowed -and $global:completeCalls -eq 1)
    $processAlive = $false
    if ($success.ProcessId -gt 0) { $processAlive = (@(Get-Process -Id $success.ProcessId -ErrorAction SilentlyContinue).Count -gt 0) }
    check 'completed child process left no orphan process' (-not $processAlive)
    Write-Host ("R014 stream metrics: received={0}; transportHighWater={1}/{2}; ordinaryRetainedHighWater={3}; recordHighWater={4}/{5}; maxDrain={6}/{7} chars, {8}/{9} lines; appends={10}; elapsed={11}s" -f $success.StateAtDone.TransportReceived, $success.StateAtDone.TransportMaxQueue, $global:BatchQueueMax, $global:maxQueueObserved, $success.StateAtDone.TransportMaxRecord, $global:BatchQueueRecordCharMax, $global:maxDrainChars, $global:BatchDrainCharBudget, $global:maxDrainLines, $global:BatchDrainLineBudget, $global:mainAppendCalls, [Math]::Round($success.Elapsed, 1))

    $second = Run-ProcessScenario 'second' @('fixture-second') 0 'SUCCESS' $false $true
    check 'second batch resets stale queue pressure at start' ($second.QueueAtStartReturn -eq 0 -and $second.Classification.Kind -eq 'SUCCESS' -and $second.StateWasCleared)

    $failure = Run-ProcessScenario 'failure' @('fixture-fail') 7 'FAILED' $false $false
    check 'nonzero target exit remains FAILED and newest error/status stays visible' ($failure.Classification.Kind -eq 'FAILED' -and $failure.Classification.Message -notmatch 'SUCCESS' -and $failure.LogText.Contains('TERMINAL-ERROR-MARKER') -and $failure.LogText.Contains('TERMINAL: apply FAILED'))
    $nonzeroSuccess = Run-ProcessScenario 'nonzero-success' @('fixture-alpha') 7 'FAILED' $false $false
    check 'nonzero child exit cannot become SUCCESS when target record says success' ($nonzeroSuccess.Classification.Kind -eq 'FAILED')
    $partial = Run-ProcessScenario 'partial' @('fixture-alpha','fixture-beta') 1 'PARTIAL' $false $false
    check 'mixed target outcomes remain PARTIAL on nonzero process exit' ($partial.Classification.Kind -eq 'PARTIAL')
    $duplicate = Run-ProcessScenario 'duplicate' @('fixture-alpha') 0 'SUCCESS' $false $false
    check 'process duplicate target records keep the latest record only' ($duplicate.Classification.Kind -eq 'SUCCESS' -and $duplicate.StateAtDone.ResultCount -eq 1)
    $missing = Run-ProcessScenario 'missing' @('fixture-alpha') 0 'FAILED' $false $false
    check 'missing machine result fails closed' ($missing.Classification.Kind -eq 'FAILED' -and $missing.Classification.Message -match 'missing result record')
    $malformed = Run-ProcessScenario 'malformed' @('fixture-alpha') 0 'FAILED' $false $false
    check 'malformed machine result fails closed' ($malformed.Classification.Kind -eq 'FAILED' -and $malformed.Classification.Message -match 'malformed machine result')
    $callbackError = Run-ProcessScenario 'eof' @('fixture-alpha') 0 'SUCCESS' $false $false $true
    check 'OnDone exception is reported without wedging exactly-once cleanup' ($callbackError.Completed -and $callbackError.StateWasCleared -and $callbackError.CompletionState.CleanedUp -and $callbackError.CompletionState.Finalized -and $callbackError.CompletionState.Cleared -and $callbackError.CompletionState.ProcessDisposed -and $callbackError.CompletionState.TimerDisposed -and $callbackError.TerminalCloseAllowed -and $global:completeCalls -eq 1 -and $callbackError.LogText.Contains('BATCH COMPLETION HANDLER FAILED'))
    $eof = Run-ProcessScenario 'eof' @('fixture-alpha') 0 'SUCCESS' $false $false
    check 'final line emitted immediately before exit is delivered before finalization' ($eof.LogText.Contains('FINAL-BEFORE-EXIT') -and $eof.StateAtDone.StdoutEof -and $eof.StateAtDone.StderrEof -and $eof.StateAtDone.CallbacksInFlight -eq 0)
    $handlers = Run-ProcessScenario 'handlers' @('fixture-alpha') 0 'SUCCESS' $false $false
    check 'fast initial output is captured by handlers attached before async reads' ($handlers.LogText.Contains('EARLY-MARKER') -and $handlers.ProgressiveBeforeExit)
    Run-LogSurfaceProbe
    check 'the behavioral suite ran on Windows PowerShell 5.1 with WinForms' ($PSVersionTable.PSVersion.Major -eq 5 -and $null -ne $probeBox)
    check 'tests left shipped production source byte-identical' ((Get-FileHash -LiteralPath $guiH -Algorithm SHA256).Hash -eq $baselineHash)
} finally {
    $fullTemp = [System.IO.Path]::GetFullPath($global:fixtureRoot)
    $fullBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($fullTemp.StartsWith($fullBase, [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fullTemp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$($global:passCount) PASS, $($global:failCount) FAIL; elapsed $([Math]::Round($global:startedAt.Elapsed.TotalSeconds, 1))s"
if ($global:failCount -gt 0) { exit 1 }
exit 0
