# SRC-006:R006 -- logon-task checkbox: startup must not mutate the task, and a
# failed task command must never dispatch the inverse command.
#
# DEFECT (pre-fix): the CheckedChanged handler was attached at construction but
# the startup state assignment (`$chkLogonTask.Checked = $true` when the task
# exists) happened hundreds of lines later -- the ASSIGNMENT fired the handler,
# so merely opening the GUI re-Registered the task. The error path flipped
# Checked bare, which re-entered the handler: a failed Register dispatched a
# real Unregister that could delete a pre-existing task.
#
# CONTRACT under test:
#  - the checkbox is initialized from the real task state BEFORE the handler is
#    attached, under an explicit suppression guard;
#  - the handler is a no-op while the suppression guard is set;
#  - a failed Register/Unregister rolls the checkbox back VISUALLY under
#    suppression and issues exactly ONE child command total (never the inverse);
#  - the toggle logic is a named function so this suite can drive it without a
#    WinForms message pump.
#
# Method: the suite parses desktop/WintageInstaller.ps1 with the PowerShell AST,
# extracts Invoke-LogonTaskToggle and the Add_CheckedChanged scriptblock, and
# drives them in this script's scope against a stubbed Invoke-ChildPowerShell
# that records every dispatched command. No desktop automation, no real
# ScheduledTasks mutation.

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\WintageInstaller.ps1'
Add-Type -AssemblyName System.Windows.Forms
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-logon-task-gui.ps1 (3 fixtures, 13 checks):"
    Write-Host "  1. toggle function: register/unregister success and failure (never the inverse command)"
    Write-Host "  2. handler: suppression guard no-op + exactly-one-command on failure (recursion proof)"
    Write-Host "  3. structural: state init BEFORE handler attach, guard present in function and handler"
    exit 0
}

$text = [System.IO.File]::ReadAllText($installer)

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "WintageInstaller.ps1 has parse errors: $($errors[0].Message)" }

$fnAst = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Invoke-LogonTaskToggle' }, $true)
if (-not $fnAst.Count) { throw 'Invoke-LogonTaskToggle not found in WintageInstaller.ps1' }
$fnText = $fnAst[0].Extent.Text

$invokes = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $a.Member.Extent.Text -eq 'Add_CheckedChanged' }, $true)
if (-not $invokes.Count) { throw 'Add_CheckedChanged handler not found in WintageInstaller.ps1' }
$handlerText = $invokes[0].Arguments[0].Extent.Text
if (-not $handlerText -or -not $handlerText.Trim().StartsWith('{')) { throw 'Add_CheckedChanged scriptblock extraction failed' }
# The extent INCLUDES the outer braces. [scriptblock]::Create('{ body }')
# builds a script whose only statement is a scriptblock LITERAL -- invoking it
# emits the source text instead of running the body -- so the braces must go.
$handlerBody = $handlerText.Trim().Trim('{}')
$handler = [scriptblock]::Create($handlerBody)

# ---- stubbed environment, all in THIS script scope ----
# The extracted pieces are dot-sourced / invoked here, so their free variables
# ($chkLogonTask, $here, Invoke-ChildPowerShell, Say-Log) resolve dynamically
# against these stubs.
$script:stubExit = 0
$script:invocations = @()
$script:sayLog = @()
$script:suppressLogonTaskEvent = $false
$here = Join-Path $root 'desktop'

function script:Invoke-ChildPowerShell([string[]]$TaskArgs) {
    $script:invocations += ,@($TaskArgs)
    [pscustomobject]@{ Output = @('stub child output'); ExitCode = $script:stubExit }
}
function script:Say-Log { param($m) $script:sayLog += $m }

. ([scriptblock]::Create($fnText))       # defines Invoke-LogonTaskToggle here

# A REAL WinForms.CheckBox (no dialog needed) provides authentic event wiring:
# the extracted handler is attached exactly as the GUI attaches it, so a
# rollback that re-enters the handler is observable, not simulated.
$chkLogonTask = New-Object Windows.Forms.CheckBox

# ---- 1. toggle function: the four command outcomes ----
$script:stubExit = 0
$chkLogonTask.Checked = $true
$null = Invoke-LogonTaskToggle -Wanted:$true
check 'toggle: register success dispatches exactly one command' ($script:invocations.Count -eq 1)
check 'toggle: register success issues -RegisterLogonTask' ($script:invocations[0] -contains '-RegisterLogonTask')
check 'toggle: register success keeps the checkbox checked' ($chkLogonTask.Checked -eq $true)

$script:invocations = @()
$script:stubExit = 1
$chkLogonTask.Checked = $true
$null = Invoke-LogonTaskToggle -Wanted:$true
check 'toggle: register failure issues exactly ONE command total' ($script:invocations.Count -eq 1)
check 'toggle: register failure never issues -UnregisterLogonTask' ($script:invocations[0] -notcontains '-UnregisterLogonTask')
check 'toggle: register failure rolls the checkbox back visually' ($chkLogonTask.Checked -eq $false)
check 'toggle: register failure clears the suppression guard afterwards' ($script:suppressLogonTaskEvent -eq $false)

$script:invocations = @()
$script:stubExit = 0
$chkLogonTask.Checked = $false
$null = Invoke-LogonTaskToggle -Wanted:$false
check 'toggle: unregister issues -UnregisterLogonTask' ($script:invocations[0] -contains '-UnregisterLogonTask')

$script:invocations = @()
$script:stubExit = 1
$chkLogonTask.Checked = $false
$null = Invoke-LogonTaskToggle -Wanted:$false
check 'toggle: unregister failure never issues -RegisterLogonTask' (($script:invocations.Count -eq 1) -and ($script:invocations[0] -notcontains '-RegisterLogonTask'))
check 'toggle: unregister failure rolls the checkbox back visually' ($chkLogonTask.Checked -eq $true)

# ---- 2. handler: suppression guard + recursion proof ----
# Attach the handler only now: section 1 drives the toggle function directly,
# and its Checked setup assignments must not dispatch anything.
$chkLogonTask.add_CheckedChanged($handler)
# Reset to unchecked UNDER suppression (mimics the startup init path itself),
# so the click below actually fires the event.
$script:suppressLogonTaskEvent = $true
$chkLogonTask.Checked = $false
$script:suppressLogonTaskEvent = $false
# Simulate the USER checking the box: the handler must dispatch Register once.
$script:invocations = @()
$script:stubExit = 0
$chkLogonTask.Checked = $true   # a real user click fires CheckedChanged
check 'handler: user check dispatches exactly one -RegisterLogonTask' (($script:invocations.Count -eq 1) -and ($script:invocations[0] -contains '-RegisterLogonTask'))

# Simulate a PROGRAMMATIC assignment (the startup init / any rollback): the
# handler must be a complete no-op.
$script:invocations = @()
$script:suppressLogonTaskEvent = $true
$chkLogonTask.Checked = -not $chkLogonTask.Checked
$script:suppressLogonTaskEvent = $false
check 'handler: suppressed assignment dispatches NOTHING' ($script:invocations.Count -eq 0)

# Recursion proof: a FAILED user toggle must issue exactly ONE command. The
# pre-fix handler flipped Checked bare inside the failure branch, so the flip
# re-entered the handler and dispatched the inverse command -- against the
# pre-fix file this scenario recurses until the stack dies (verified: red
# control against git HEAD hit StackOverflowException).
$script:invocations = @()
$script:stubExit = 1
$chkLogonTask.Checked = $true
check 'handler: failed register issues exactly ONE command total (no recursive dispatch)' ($script:invocations.Count -eq 1)
check 'handler: failed register never issues -UnregisterLogonTask' ($script:invocations[0] -notcontains '-UnregisterLogonTask')
check 'handler: failed register leaves the checkbox unchecked (visual rollback)' ($chkLogonTask.Checked -eq $false)
check 'handler: suppression guard is cleared after the rollback' ($script:suppressLogonTaskEvent -eq $false)

# ---- 3. structural: init ordering + guard presence ----
$initIdx = $text.IndexOf("Get-ScheduledTask -TaskName 'Wintage Reapply at Logon'")
$attachIdx = $text.IndexOf('$chkLogonTask.Add_CheckedChanged(')
check 'structural: task-state query happens BEFORE the handler is attached' (($initIdx -ge 0) -and ($attachIdx -ge 0) -and ($initIdx -lt $attachIdx))
check 'structural: the old bare startup assignment is gone' ($text -notmatch [regex]::Escape('if ($existing) { $chkLogonTask.Checked = $true }'))
check 'structural: suppression guard present in handler and toggle function' (($handlerText -match 'suppressLogonTaskEvent') -and ($fnText -match 'suppressLogonTaskEvent'))

