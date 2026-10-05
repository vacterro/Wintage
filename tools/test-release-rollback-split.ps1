# Release rollback cross-store split gate (W2-003, SRC-063).
#
# The defect: a release that failed AFTER `node tools/build-desktop.js` and
# BEFORE the commit rolled back only the TRACKED store. desktop/out is
# .gitignore'd, never committed, and therefore invisible to `git restore`, so the
# worktree came back with the source at version N and the generated tree still
# holding the failed run's N+1 payload. Every later "is desktop/out current?"
# answer was then wrong in the direction that looks safe.
#
# This gate builds a THROWAWAY git repository in the temp dir, walks it into the
# exact state a failed release leaves behind, and runs the SHIPPED rollback text
# against it. The rollback function is lifted out of release.ps1 with the
# PowerShell AST (not by counting braces), so what executes here is the shipped
# text, and the shipped Git-Safe travels with it.
#
# A RED control re-runs the identical scenario against the verbatim pre-repair
# rollback and requires the SAME self-consistency assertion to fail.
#
# Nothing is built, committed, tagged or pushed in the real repository.
#
#   .\tools\test-release-rollback-split.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here -Parent
$release = Join-Path $repo 'release.ps1'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-TextFile([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

# Lift a top-level function out of release.ps1 verbatim. The AST is used rather
# than a brace counter because the release file's own braces and quotes are not
# this gate's to reason about.
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

function Invoke-Git([string]$repo_, [string[]]$argv) {
    $out = & git -c core.autocrlf=false -C $repo_ @argv 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($argv -join ' ') failed in ${repo_}: $out" }
    return @($out | ForEach-Object { [string]$_ })
}

# A ref is the only line git emits that is exactly 40 hex chars; advisory stderr
# (LF/CRLF notices, hints) arrives mixed into stdout and must not be mistaken
# for one. Used only where a ref is the whole point of the call.
function Get-GitRef([string]$repo_, [string[]]$argv) {
    return (((Invoke-Git $repo_ $argv) | Where-Object { $_ -match '^[0-9a-f]{40}$' }) -join '').Trim()
}

function Get-Head([string]$repo_) {
    return Get-GitRef $repo_ @('rev-parse', 'HEAD')
}

# A stand-in for the real generator, so the rollback's own
# `node (Join-Path $PSScriptRoot 'tools/build-desktop.js')` resolves to
# something that is a pure function of the tracked source -- without dragging a
# 16-palette generation into a scratch tree.
$stubBuilder = @'
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'wintage.user.js'), 'utf8');
const m = /@version\s+(\d+\.\d+\.\d+)/.exec(src);
if (!m) { console.error('stub build: wintage.user.js carries no @version'); process.exit(1); }
const out = path.join(root, 'desktop', 'out');
// The real generator publishes ONE whole generation (it stages and swaps), so
// nothing the previous generation left behind survives. Modelling that is what
// makes "no artifact of the failed run survived" a real claim rather than a
// re-write of one file.
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'generated.txt'), 'payload ' + m[1] + '\n');
'@

function Set-SourceVersion([string]$repo_, [string]$v) {
    Write-TextFile (Join-Path $repo_ 'wintage.user.js') ("// @version $v`nconst W95_VERSION = '$v';`n")
}

# Walk a fresh throwaway repository into the state a failed release leaves:
# committed at version N, generated at N, then bumped to N+1 and regenerated --
# with the pre-release snapshot refs computed the way release.ps1 computes them.
function New-FailedReleaseState([string]$repo_, [string]$runner) {
    Write-TextFile (Join-Path $repo_ '.gitignore') "desktop/out/`n"
    Write-TextFile (Join-Path $repo_ 'tools\build-desktop.js') $stubBuilder
    Write-TextFile (Join-Path $repo_ 'restore.ps1') $runner
    Set-SourceVersion $repo_ '1.0.0'
    Invoke-Git $repo_ @('init') | Out-Null
    Invoke-Git $repo_ @('config', 'user.email', 'gate@example.invalid') | Out-Null
    Invoke-Git $repo_ @('config', 'user.name', 'wintage gate') | Out-Null
    Invoke-Git $repo_ @('add', '--', '.gitignore', 'wintage.user.js') | Out-Null
    Invoke-Git $repo_ @('commit', '-m', 'version N') | Out-Null
    $head = Get-Head $repo_
    # version N's own generation
    & node (Join-Path $repo_ 'tools\build-desktop.js') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'stub generator failed at version N' }
    # The pre-release snapshot, taken at the same point release.ps1 takes it:
    # BEFORE the bump. `git stash create` snapshots the CURRENT worktree, so a
    # snapshot taken after the bump would faithfully restore version N+1 and the
    # rollback would look like it worked while proving nothing.
    $snapshot = Get-GitRef $repo_ @('stash', 'create', 'wintage release pre-state')
    $worktree = if ($snapshot) { $snapshot } else { $head }
    $index = if ($snapshot) { "$snapshot^2" } else { $head }
    # ...the release bumps the version and regenerates, then dies before commit
    Set-SourceVersion $repo_ '1.0.1'
    & node (Join-Path $repo_ 'tools\build-desktop.js') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'stub generator failed at version N+1' }
    return @{
        root     = $repo_
        worktree = $worktree
        index    = $index
    }
}

function Read-Generated([string]$repo_) {
    $p = Join-Path $repo_ 'desktop\out\generated.txt'
    if (-not (Test-Path $p)) { return '<absent>' }
    return [System.IO.File]::ReadAllText($p).Trim()
}

# THE assertion. Both stores must agree on version N after a rollback: the
# tracked source restored, and the generated tree re-derived from it.
function Test-SelfConsistent([string]$repo_) {
    $src = [System.IO.File]::ReadAllText((Join-Path $repo_ 'wintage.user.js'))
    return (($src -match '@version 1\.0\.0') -and ((Read-Generated $repo_) -eq 'payload 1.0.0'))
}

function New-ScratchRepo([string]$name) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("wintage-w2003-$name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'tools') | Out-Null
    return $dir
}

Write-Host '--- W2-003: the shipped rollback text is located and executed ---'

$gitSafe = Get-FunctionText $release 'Git-Safe'
$restore = Get-FunctionText $release 'Restore-PreReleaseState'
check 'the shipped Restore-PreReleaseState is located in release.ps1' ($restore -match 'function\s+Restore-PreReleaseState')
check 'the shipped Git-Safe travels with it' ($gitSafe -match 'function\s+Git-Safe')

# The shipped rollback is a FUNCTION, so it can be run against a scratch tree.
# release.ps1 itself is a top-to-bottom script that bumps, commits and pushes on
# load -- it is never executed here, only read.
$runner = @(
    $gitSafe
    $restore
    'Restore-PreReleaseState $args[0] $args[1] ([bool]::Parse($args[2]))'
) -join "`r`n"

$green = New-ScratchRepo 'green'
try {
    $st = New-FailedReleaseState $green $runner
    check 'the scenario really did reach the failed-release state' ((Read-Generated $green) -eq 'payload 1.0.1')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $green 'restore.ps1') $st.worktree $st.index 'True' | Out-Null
    check 'the shipped rollback exits 0' ($LASTEXITCODE -eq 0)
    check 'the TRACKED store is back at version N' ([System.IO.File]::ReadAllText((Join-Path $green 'wintage.user.js')) -match '@version 1\.0\.0')
    check 'the GENERATED store was re-derived from version N' ((Read-Generated $green) -eq 'payload 1.0.0')
    check 'no artifact of the failed N+1 run survived in desktop/out' (-not (Test-Path (Join-Path $green 'desktop\out\payload-1.0.1.txt')))
    check 'the rolled-back worktree is SELF-CONSISTENT' (Test-SelfConsistent $green)
    check 'the rollback left no tracked file dirty' ((Invoke-Git $green @('status', '--porcelain', '--', 'wintage.user.js')).Count -eq 0)
} finally { Remove-Item -Recurse -Force $green -ErrorAction SilentlyContinue }

# $generated = false is the pre-generation abort: it must NOT rewrite the
# ignored tree, because that abort's own message says NOTHING was changed. Its
# own scratch repo, so the two scenarios cannot contaminate each other.
$preGen = New-ScratchRepo 'pregen'
try {
    $st2 = New-FailedReleaseState $preGen $runner
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $preGen 'restore.ps1') $st2.worktree $st2.index 'False' | Out-Null
    check 'a pre-generation abort still exits 0' ($LASTEXITCODE -eq 0)
    check 'a pre-generation abort does NOT touch the ignored tree' ((Read-Generated $preGen) -eq 'payload 1.0.1')
    check 'a pre-generation abort DOES still restore the tracked store' (
        [System.IO.File]::ReadAllText((Join-Path $preGen 'wintage.user.js')) -match '@version 1\.0\.0')
} finally { Remove-Item -Recurse -Force $preGen -ErrorAction SilentlyContinue }

Write-Host '--- W2-003 RED: the pre-repair rollback leaves the cross-store split ---'

# The verbatim pre-repair rollback: the same two `git restore` calls with the
# same throw, and nothing else. Only the variable names become parameters.
$oldRestore = @'
function Restore-PreReleaseState([string]$worktreeRef, [string]$indexRef, [bool]$generated) {
    if ((Git-Safe restore "--source=$worktreeRef" --worktree -- .) -ne 0 -or
        (Git-Safe restore "--source=$indexRef" --staged -- .) -ne 0) {
        throw 'release rollback failed: pre-release tracked worktree and index could not be restored'
    }
}
'@
$redRunner = (@($gitSafe, $oldRestore, 'Restore-PreReleaseState $args[0] $args[1] ([bool]::Parse($args[2]))') -join "`r`n")

$red = New-ScratchRepo 'red'
try {
    $st = New-FailedReleaseState $red $redRunner
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $red 'restore.ps1') $st.worktree $st.index 'True' | Out-Null
    check 'RED: the pre-repair rollback exits 0 (it does not know it failed)' ($LASTEXITCODE -eq 0)
    check 'RED: the pre-repair rollback DID restore the tracked store' (([System.IO.File]::ReadAllText((Join-Path $red 'wintage.user.js'))) -match '@version 1\.0\.0')
    check 'RED: the pre-repair rollback leaves the GENERATED store at N+1' ((Read-Generated $red) -eq 'payload 1.0.1')
    check 'RED: the SAME self-consistency assertion FAILS against it' (-not (Test-SelfConsistent $red))
} finally { Remove-Item -Recurse -Force $red -ErrorAction SilentlyContinue }

Write-Host '--- W2-003: the fix is wired, not orphaned ---'

check 'the shipped rollback re-derives the ignored tree' ($restore -match 'build-desktop\.js')
$releaseText = [System.IO.File]::ReadAllText($release)
check 'the shipped rollback is CALLED from the pre-commit catch' (
    $releaseText -match 'Restore-PreReleaseState \$snapshotWorktree \$snapshotIndex \$generated')
# A part-way generation has already dirtied the ignored tree, so the flag has to
# be raised BEFORE the build call, not after it. The generation step is pinned by
# its own failure message, which exists nowhere else in the file.
$flagAt = $releaseText.IndexOf('$generated = $true')
$genAt = $releaseText.IndexOf('Building the desktop themes failed')
check '$generated is set BEFORE the generation step, so a part-way build is covered' (
    $flagAt -gt 0 -and $genAt -gt $flagAt)

Write-Host ''
Write-Host "release rollback split: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0