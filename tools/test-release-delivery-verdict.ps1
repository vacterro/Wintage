# T-983: prove the release FAILS when the served artifact is not the published
# build.
#
# The delivery detector (tools/check-deployed-userscript.js) has an offline test
# for its three verdicts (tools/test-release-delivery.js). What that test does
# NOT cover is the release's REACTION to them: the mapping from the detector's
# exit code to the release's decision lives in release.ps1, and release.ps1 can
# only be exercised by really pushing.
#
# So the mapping is a FUNCTION, this gate lifts it out of release.ps1 verbatim
# with the PowerShell AST (the same technique the rollback gate uses for
# Restore-PreReleaseState), and asserts both halves of the promise:
#   - a stale artifact (exit 1) maps to 'stale'
#   - the release THROWS on 'stale' and only WARNS on 'unknown'
#
# A RED control mutates the lifted function so a stale artifact looks current,
# and requires the same assertion to fail -- otherwise this gate would pass
# against a release that no longer fails.
#
# Nothing is built, committed, tagged or pushed.
#
#   .\tools\test-release-delivery-verdict.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here -Parent
$release = Join-Path $repo 'release.ps1'
$script:pass = 0
$script:fail = 0

function Check([string]$label, [bool]$cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Lift a top-level function out of release.ps1 verbatim. The AST is used
# rather than a brace counter because the release file's own braces and quotes
# are not this gate's to reason about.
function Get-FunctionText([string]$file, [string]$name) {
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { throw "release.ps1 does not parse: $($errs[0].Message)" }
    $fn = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true)
    if (-not $fn) { throw "could not locate '$name' in $file" }
    $text = [System.IO.File]::ReadAllText($file)
    return $text.Substring($fn.Extent.StartOffset, $fn.Extent.EndOffset - $fn.Extent.StartOffset)
}

# The mapping under test, isolated: the lifted text is dot-sourced into a
# throwaway scope so the gate cannot be fooled by a same-named local function.
function Invoke-Verdict([string]$fnText, $code) {
    $scope = & {
        param($text)
        . ([scriptblock]::Create($text))
        Get-ReleaseDeliveryVerdict $code
    } $fnText
    return [string]$scope
}

# --- The shipped mapping ---------------------------------------------------

$fnText = Get-FunctionText $release 'Get-ReleaseDeliveryVerdict'
Check 'the shipped Get-ReleaseDeliveryVerdict is located in release.ps1' ($fnText -match 'function\s+Get-ReleaseDeliveryVerdict')

$staleVerdict = Invoke-Verdict $fnText 1
Check 'exit 1 (the served artifact is not this build) is STALE' ($staleVerdict -eq 'stale') "got '$staleVerdict'"
$currentVerdict = Invoke-Verdict $fnText 0
Check 'exit 0 (the served artifact is this build) is CURRENT' ($currentVerdict -eq 'current') "got '$currentVerdict'"
$unknownVerdict = Invoke-Verdict $fnText 2
Check 'exit 2 (the artifact could not be fetched) is UNKNOWN' ($unknownVerdict -eq 'unknown') "got '$unknownVerdict'"
$oddVerdict = Invoke-Verdict $fnText 7
Check 'an exit code nobody defined is STALE (the release fails safe)' ($oddVerdict -eq 'stale') "got '$oddVerdict'"
$noCodeVerdict = Invoke-Verdict $fnText $null
Check 'a MISSING exit code is UNKNOWN, never CURRENT (no evidence is not a pass)' ($noCodeVerdict -eq 'unknown') "got '$noCodeVerdict'"

# --- What the release DOES with the verdict --------------------------------

$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($release, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { throw "release.ps1 does not parse: $($errs[0].Message)" }
$releaseText = [System.IO.File]::ReadAllText($release)

Check 'the release runs the delivery detector' ($releaseText -match 'tools[\\/]check-deployed-userscript\.js')
Check 'the release asks the shipped verdict function' ($releaseText -match 'Get-ReleaseDeliveryVerdict\s+\$LASTEXITCODE')

$ifs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true))
# IfStatementAst exposes the condition and the body through Clauses (the
# Condition/Body shortcuts are empty on Windows PowerShell 5.1), and an if may
# carry more than one clause, so every clause is looked at.
$clauses = @()
foreach ($i in $ifs) {
    foreach ($c in $i.Clauses) {
        $clauses += [pscustomobject]@{ Condition = $c.Item1.Extent.Text; Body = $c.Item2.Extent.Text }
    }
}
$staleIf = $clauses | Where-Object { $_.Condition -match '\$delivery\s+-eq\s+.stale.' } | Select-Object -First 1
$unknownIf = $clauses | Where-Object { $_.Condition -match '\$delivery\s+-eq\s+.unknown.' } | Select-Object -First 1

Check 'the release has a branch for a stale delivery' ($null -ne $staleIf)
Check 'the release has a branch for an unknown delivery' ($null -ne $unknownIf)

if ($staleIf) {
    $staleBody = $staleIf.Body
    Check 'a stale delivery THROWS: the release fails' ($staleBody -match '(?i)\bthrow\b')
    Check 'the stale branch says the artifact is not served yet' ($staleBody -match '(?i)does not serve this build')
}
if ($unknownIf) {
    $unknownBody = $unknownIf.Body
    Check 'an unknown delivery does NOT throw: the release cannot prove the artifact, but the push already happened' ($unknownBody -notmatch '(?i)\bthrow\b')
    Check 'an unknown delivery WARNS instead' ($unknownBody -match '(?i)WARNING')
}

# --- RED control -----------------------------------------------------------
# The mutant makes a stale artifact look current. The same assertion that
# passed above must now fail, or this gate proves nothing.

$mutant = $fnText -replace "return\s+'stale'", "return 'current'"
Check 'the mutant really changed the shipped text' ($mutant -ne $fnText)
$mutantVerdict = Invoke-Verdict $mutant 1
Check 'RED control: with the mutant, exit 1 is no longer STALE' ($mutantVerdict -ne 'stale') "got '$mutantVerdict'"

Write-Host ""
if ($script:fail -gt 0) {
    Write-Host "TESTS FAILED ($script:fail of $($script:pass + $script:fail) checks)" -ForegroundColor Red
    exit 1
}
Write-Host "ALL TESTS PASSED! ($script:pass checks)" -ForegroundColor Green
exit 0
