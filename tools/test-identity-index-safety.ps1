# T-967 regression gate: computing a worktree identity must NEVER mutate the
# live git index.
#
# The defect: Get-WorktreeIdentity (tests/Run-Tests.ps1) borrowed .git/index by
# setting $env:GIT_INDEX_FILE to a throwaway path, then "cleared" it with
# `Remove-Item Env:GIT_INDEX_FILE`. On Windows that does NOT unset the variable:
# it leaves it EMPTY. An empty GIT_INDEX_FILE is a real, destructive setting --
# `git read-tree HEAD` succeeds against it and overwrites the LIVE index. One
# suite run therefore silently dropped every staged change from .git/index; the
# three files T-938/T-959 had staged (tools/bench-idle-cpu.js,
# tools/test-shadow-registry-lifecycle.js, tools/test-stylesheet-census.js)
# reverted from "A " (staged new) to "??" (untracked) with no error and no
# visible cause. On Linux the same code is harmless, which is why it shipped.
#
# This gate drives the REAL extracted function against a throwaway repository
# with a staged change, and requires the live index bytes to be unchanged and
# the staged entry to survive. It runs on any PowerShell 5.1 host.
#
#   .\tools\test-identity-index-safety.ps1
#
# Self-contained: no repo fixture under version control is needed, and the
# throwaway repository is removed in a finally block.

[CmdletBinding()]
param()

# git writes benign warnings to stderr (LF->CRLF on a fresh Windows checkout);
# under 'Stop' PowerShell turns any native stderr line into a terminating error,
# so this gate keeps the preference at 'Continue' and asserts exit codes itself.
$ErrorActionPreference = 'Continue'
$script:errors = 0
$script:failures = @()

function Ok([bool]$cond, [string]$message) {
    if ($cond) {
        Write-Host "[PASS] $message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $message" -ForegroundColor Red
        $script:errors++
        $script:failures += $message
    }
}

# ---------------------------------------------------------------- extraction
# The proven pattern from test-target-refresh-transaction.ps1: pull the REAL
# shipped function text out of tests/Run-Tests.ps1 and bind it into this
# process, so what is tested is the shipped bytes and not a paraphrase.
$repoRoot = Split-Path $PSScriptRoot -Parent
$runTestsPath = Join-Path $repoRoot 'tests\Run-Tests.ps1'
$runTestsCode = [System.IO.File]::ReadAllText($runTestsPath)

function Get-FunctionText([string]$source, [string]$name) {
    $pattern = '(?ms)^function\s+' + [regex]::Escape($name) + '\s*(\([^)]*\))?\s*\{'
    $m = [regex]::Match($source, $pattern)
    if (-not $m.Success) { return $null }
    $depth = 0
    $i = $m.Index + $m.Length - 1
    while ($i -lt $source.Length) {
        $c = $source[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $source.Substring($m.Index, $i - $m.Index + 1) }
        }
        $i++
    }
    return $null
}

$identityText = Get-FunctionText $runTestsCode 'Get-WorktreeIdentity'
if (-not $identityText) {
    Write-Host "[FAIL] could not extract Get-WorktreeIdentity from tests/Run-Tests.ps1" -ForegroundColor Red
    exit 1
}

# The helpers it depends on, bound in the same order the suite binds them.
$idTempText = Get-FunctionText $runTestsCode 'Get-IdTempPath'
$bytesHashText = Get-FunctionText $runTestsCode 'Get-BytesHashHex'
if (-not $idTempText -or -not $bytesHashText) {
    Write-Host "[FAIL] could not extract the identity helpers" -ForegroundColor Red
    exit 1
}
Invoke-Expression -Command $bytesHashText
Invoke-Expression -Command $idTempText
Invoke-Expression -Command $identityText
Ok ($null -ne (Get-Command Get-WorktreeIdentity -ErrorAction SilentlyContinue)) 'Get-WorktreeIdentity extracted and bound'

# ------------------------------------------------------- source-level checks
# These are what make the gate bite even if the function is refactored away.
Ok ($identityText -match '\$hadPriorIndex') 'Get-WorktreeIdentity records whether GIT_INDEX_FILE was already set'
Ok ($identityText -notmatch 'if\s*\(\$env:GIT_INDEX_FILE\)\s*\{') 'the identity function no longer treats a present GIT_INDEX_FILE as truth to clear'

# ------------------------------------------------------------- behavioural
# A throwaway repo with a REAL staged change: the exact shape that was lost.
$probe = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-idx-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $probe | Out-Null
    & git init -q $probe 2>$null | Out-Null
    & git -C $probe config user.email 'gate@example.invalid' 2>$null
    & git -C $probe config user.name 'gate' 2>$null
    [System.IO.File]::WriteAllText((Join-Path $probe 'tracked.txt'), "base`n")
    & git -C $probe add tracked.txt 2>$null
    & git -C $probe commit -q -m 'base' 2>$null
    [System.IO.File]::WriteAllText((Join-Path $probe 'staged.js'), "const s=1;`n")
    & git -C $probe add staged.js 2>$null
    # An extra untracked file too, so the identity has content to carry.
    [System.IO.File]::WriteAllText((Join-Path $probe 'untracked.txt'), "u=1;`n")

    $idxPath = Join-Path $probe '.git\index'
    $beforeBytes = [System.IO.File]::ReadAllBytes($idxPath)
    $stagedBefore = ((& git -C $probe diff --cached --name-only 2>$null) -join ',')

    # GUARD: this gate must not itself be the thing that disturbs the index, so
    # record what a caller would see after the identity call.
    $id = Get-WorktreeIdentity $probe
    $afterBytes = [System.IO.File]::ReadAllBytes($idxPath)
    $stagedAfter = ((& git -C $probe diff --cached --name-only 2>$null) -join ',')

    Ok ($id.Ok) "the identity was computed on the throwaway repo ($($id.Fingerprint))"
    $same = ($beforeBytes.Length -eq $afterBytes.Length)
    if ($same) {
        for ($i = 0; $i -lt $beforeBytes.Length; $i++) { if ($beforeBytes[$i] -ne $afterBytes[$i]) { $same = $false; break } }
    }
    Ok $same 'the LIVE index bytes are unchanged by the identity computation'
    Ok ($stagedAfter -match 'staged\.js') "the staged change SURVIVES the identity computation (staged=[$stagedBefore] -> [$stagedAfter])"
    Ok (-not $env:GIT_INDEX_FILE) "GIT_INDEX_FILE is not left set in the caller's environment (value='$($env:GIT_INDEX_FILE)')"

    # The two untracked-content states must still differ (the T-967 repair
    # itself, re-proven on the same throwaway repo the index safety uses).
    [System.IO.File]::WriteAllText((Join-Path $probe 'untracked.txt'), "u=1;`n")
    $fa = (Get-WorktreeIdentity $probe).Fingerprint
    [System.IO.File]::WriteAllText((Join-Path $probe 'untracked.txt'), "u=999;`n")
    $fb = (Get-WorktreeIdentity $probe).Fingerprint
    Ok ($fa -ne $fb) 'the identity still separates two untracked-content states (the repair holds)'

    # A caller that ALREADY has GIT_INDEX_FILE set must get its own value back.
    $env:GIT_INDEX_FILE = $idxPath
    try { $null = Get-WorktreeIdentity $probe } finally {
        Ok ($env:GIT_INDEX_FILE -eq $idxPath) 'a pre-existing GIT_INDEX_FILE is restored exactly, not left empty'
        if ($env:GIT_INDEX_FILE -ne $idxPath) {
            Remove-Item Env:GIT_INDEX_FILE -Force -ErrorAction SilentlyContinue
        }
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $probe -ErrorAction SilentlyContinue
}

if ($script:errors -gt 0) {
    Write-Host "TESTS FAILED ($($script:errors))" -ForegroundColor Red
    foreach ($f in $script:failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
exit 0
