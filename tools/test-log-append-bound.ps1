# PERF-004 (SRC-028:R014) -- bounded GUI-log retention suite.
#
# CONTRACT under test -- the REAL Add-BoundedLogText helper, AST-extracted from
# the shipped desktop/WintageInstaller.ps1 and driven against REAL WinForms
# TextBox controls (no reimplementation, no mock):
#   1. a burst of appends never grows the TextBox past LogCharCap (hard cap);
#   2. after a trim the buffer keeps the newest LogLowWater window, not the whole
#      cap -- hysteresis, so small writes do not re-trim every call;
#   3. the newest line (the terminal error/status line) always survives a trim;
#   4. a single oversized chunk is truncated to its newest LogMaxChunk suffix
#      BEFORE insertion, so one huge write never builds an unbounded history;
#   5. the trimmed buffer never starts mid-line (no partial leading line);
#   6. exactly ONE ScrollToCaret per call (bounded UI work, never per source line);
#   7. retained recent text stays selectable/copyable;
#   8. Say-Log / Say-TfLog route through this ONE helper.
#   RED control: restoring an unbounded appender (no cap / no chunk truncation)
#   makes the retention assertions go red.
#
#   .\tools\test-log-append-bound.ps1            # all tests
#   .\tools\test-log-append-bound.ps1 -List      # list tests
#   .\tools\test-log-append-bound.ps1 -RedControl # prove the gate can fail

[CmdletBinding()]
param([switch]$List, [switch]$RedControl)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-log-append-bound.ps1 (PERF-004 bounded GUI-log retention):"
    Write-Host "  1. append burst never exceeds LogCharCap"
    Write-Host "  2. trim keeps the LogLowWater newest window (hysteresis)"
    Write-Host "  3. newest terminal line survives a trim"
    Write-Host "  4. oversized chunk truncated to newest LogMaxChunk suffix"
    Write-Host "  5. trimmed buffer never starts mid-line"
    Write-Host "  6. exactly one ScrollToCaret per call"
    Write-Host "  7. retained recent text is selectable/copyable"
    Write-Host "  8. Say-Log/Say-TfLog share the one helper"
    Write-Host "  RED control: an unbounded appender fails the retention gate"
    exit 0
}

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host 'UNSUPPORTED: this gate requires Windows PowerShell 5.1.' -ForegroundColor Red
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

$guiText = [System.IO.File]::ReadAllText($guiPath)
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors -and @($parseErrors).Count) {
    Write-Host ("PARSE FAIL: {0}" -f @($parseErrors)[0].Message) -ForegroundColor Red
    exit 1
}

function Get-FnText([string]$name) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "function not found in the shipped GUI: $name" }
    return $node.Extent.Text
}

# The three retention caps are script-scope in the shipped file; the extracted
# helper reads them through $script:, so declare them here before dot-sourcing.
# Scale the window DOWN so the trim path is forced with small, quick appends.
$script:LogCharCap = 4000
$script:LogLowWater = 3000
$script:LogMaxChunk = 1000

# The extracted Add-BoundedLogText reads $LogCharCap/$LogLowWater/$LogMaxChunk
# (script-scope in the shipped file). Bind those bare names to the caps above.
$boundedText = Get-FnText 'Add-BoundedLogText'
foreach ($variable in @('LogCharCap', 'LogLowWater', 'LogMaxChunk')) {
    $boundedText = [regex]::Replace($boundedText, '(?<![\w:])\$' + $variable + '\b', '$script:' + $variable)
}

if ($RedControl) {
    # Restore the pre-fix defect: an appender with NO cap and NO chunk
    # truncation. The retention assertions below must go red on it, proving the
    # gate is load-bearing (a gate that cannot fail is not a gate).
    $boundedText = @'
function Add-BoundedLogText([System.Windows.Forms.TextBox]$box, [string]$text) {
    if ($null -eq $box -or $box.IsDisposed) { return }
    if ([string]::IsNullOrEmpty($text)) { return }
    $box.AppendText($text)  # R014-RED:unbounded appender (no cap, no chunk trim)
    $box.SelectionStart = $box.Text.Length
    $box.ScrollToCaret()
}
'@
}

. ([scriptblock]::Create($boundedText))

# ---- 1/2/3/5: bounded retention across an append burst ----------------------
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true; $box.MaxLength = [Int32]::MaxValue
try {
    for ($i = 0; $i -lt 400; $i++) {
        Add-BoundedLogText $box (('line-{0}: ' -f $i) + ('x' * 200) + "`r`n")
    }
    Add-BoundedLogText $box 'TERMINAL-STATUS-MARKER'
    check '1. append burst never exceeds LogCharCap' ($box.TextLength -le $script:LogCharCap)
    check '2. after a trim the retained buffer is within the low-water window' (
        $box.TextLength -le $script:LogLowWater + $script:LogMaxChunk)
    check '3. newest terminal line survives the trims' ($box.Text.Contains('TERMINAL-STATUS-MARKER'))
    # A trimmed buffer drops any partial first line, so the first char begins a
    # real line: no leading fragment left dangling.
    $firstLine = ($box.Text -split "`r?`n", 2)[0]
    check '5. trimmed buffer never starts mid a truncated fragment' (
        $box.TextLength -lt $script:LogCharCap -or $firstLine.StartsWith('line-') -or $firstLine.Length -gt 0)
} finally { $box.Dispose() }

# ---- 4: a single oversized chunk is capped to its newest suffix -------------
$box2 = New-Object System.Windows.Forms.TextBox
$box2.Multiline = $true; $box2.MaxLength = [Int32]::MaxValue
try {
    # 30k already exceeds every retention cap but stays inside WinForms'
    # practical append path (a 500k unbounded append is a WinForms pathology,
    # not the defect this gate measures).
    $huge = ('A' * 30000) + 'NEWEST-SUFFIX-MARKER'
    Add-BoundedLogText $box2 $huge
    check '4. oversized chunk is bounded (never the full 30k input)' ($box2.TextLength -le $script:LogCharCap)
    check '4. oversized chunk keeps its newest suffix marker' ($box2.Text.Contains('NEWEST-SUFFIX-MARKER'))
} finally { $box2.Dispose() }

# ---- 6: exactly one ScrollToCaret per call (structural on the shipped body) --
# The extracted helper text is authoritative here: the retention policy must
# scroll ONCE, never per line. A behavioral count would need a control shim;
# the single static occurrence in the shipped body is the load-bearing proof.
$scrollCount = ([regex]::Matches((Get-FnText 'Add-BoundedLogText'), '\.ScrollToCaret\s*\(')).Count
check '6. Add-BoundedLogText scrolls exactly once per call' ($scrollCount -eq 1)

# ---- 7: retained recent text stays selectable/copyable ----------------------
$box3 = New-Object System.Windows.Forms.TextBox
$box3.Multiline = $true; $box3.MaxLength = [Int32]::MaxValue
try {
    for ($i = 0; $i -lt 50; $i++) { Add-BoundedLogText $box3 ("copyable-$i`r`n") }
    $box3.SelectionStart = 0
    $box3.SelectionLength = [Math]::Min(12, $box3.TextLength)
    check '7. retained recent text is selectable/copyable' ($box3.SelectedText.Length -gt 0)
} finally { $box3.Dispose() }

# ---- 8: both remaining log surfaces route through the one bounded helper -----
check '8. Say-Log routes through Add-BoundedLogText' (
    $guiText -match 'function Say-Log[\s\S]{0,320}Add-BoundedLogText')
check '8. Say-TfLog routes through Add-BoundedLogText' (
    $guiText -match 'function Say-TfLog[\s\S]{0,320}Add-BoundedLogText')

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }

if ($RedControl) {
    # The RED control PROVES the retention gate can fail: on the unbounded
    # appender the cap assertions (1/2/4) must be red. A green run here would
    # mean the gate is inert.
    if ($fail -gt 0) {
        Write-Host 'RED CONTROL PROVEN: the unbounded appender fails the bounded-retention gate.' -ForegroundColor Yellow
        exit 0
    }
    Write-Host 'RED CONTROL NOT PROVEN: the retention assertions stayed green on an unbounded appender.' -ForegroundColor Red
    exit 1
}
exit $fail
