# Wiki Desktop target parity gate (T-971).
#
# Defect class this suite pins down:
# wiki/Desktop.md documents the supported targets in a table, while the REAL set of
# supported targets is declared once in desktop/install.ps1. A target added to the
# installer did not need a wiki row to work, so the table quietly fell behind:
# antigravity-app and processexplorer were both live, individually selectable
# targets -- reachable from the GUI, the ValidateSet, `-Selected` and `-Target
# all` -- while the wiki table still showed twenty and claimed to describe the
# surface. Nothing failed. The documentation was simply smaller than the product.
#
# The set under test is DERIVED, never transcribed: install.ps1's own -Target
# ValidateSet is the declared definition of what a user may ask for, and
# install.ps1 already cross-checks it against its dispatch lists at startup
# (the `$orphans` guard). This gate reads that one line instead of keeping a
# second list of target names, so a new target cannot be added to the product
# without this gate noticing that the docs have not caught up.
#
# Scope: the maintained wiki mirror page only (wiki/Desktop.md), because that is
# the page whose job is "here is what this program can theme". desktop/README.md is
# a different surface with its own parity gate (tools/test-readme-target-parity.ps1,
# T-311) and is deliberately not re-checked here.
#
# Red control: -RedControl drops a live target's row from a scratch copy of the
# page and requires the gate to fail -- a gate that cannot go red is not a gate.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$Root,
    # The page to check. Defaults to the repo mirror, which is the surface that
    # ships; -WikiPage points the same gate at the saiwiki kitchen draft so the
    # producer can verify a fix before it is collected.
    [string]$WikiPage
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = if ($Root) { $Root } else { Split-Path $here -Parent }
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# ---- The live target set, read from the product rather than transcribed ----
$installer = Join-Path $root 'desktop\install.ps1'
$wikiPage = if ($WikiPage) { $WikiPage } else { Join-Path $root 'wiki\Desktop.md' }

if ($List) {
    Write-Host "test-wiki-target-parity.ps1 (T-971 wiki target parity):"
    Write-Host "  1. every -Target value install.ps1 declares is documented in wiki/Desktop.md"
    Write-Host "  2. a target documented in the wiki table is a name install.ps1 knows"
    Write-Host "  3. a page that drops a live target's row fails the gate"
    Write-Host "The live set is parsed from the -Target ValidateSet in desktop/install.ps1."
    Write-Host "Red control: -RedControl (a page missing a live target is caught)"
    exit 0
}

foreach ($p in @($installer, $wikiPage)) {
    if (-not (Test-Path $p)) { Write-Host "FAIL: required input not found: $p" -ForegroundColor Red; exit 1 }
}

# The ValidateSet is one parenthesised, single-quoted list on one line. It is the
# only place a user can learn the target vocabulary, and it is what install.ps1
# itself validates every invocation against -- so this is a read of the product's
# own contract, not a parallel list maintained here.
$installerText = Get-Content $installer -Raw
$vs = [regex]::Match($installerText, "ValidateSet\((?<body>[^)]*)\)").Groups['body'].Value
if (-not $vs) { Write-Host "FAIL: no -Target ValidateSet found in desktop/install.ps1" -ForegroundColor Red; exit 1 }
$live = @([regex]::Matches($vs, "'(?<k>[a-z0-9-]+)'") | ForEach-Object { $_.Groups['k'].Value } | Where-Object { $_ -ne 'all' })
if (-not $live.Count) { Write-Host "FAIL: the -Target ValidateSet yielded no target names" -ForegroundColor Red; exit 1 }

# ---- The documented set: backticked names in the FIRST table column ----
# Only the first column. The mechanism column backticks file names, registry keys
# and flags (`.theme`, `HKCU\Console`, `Verdana_m1`, `-RescanBrowsers`), and a
# parser that could not tell those from target names would report false parity
# on a page that never mentioned a single target. Rows that share one cell
# (`antigravity`, `vscode`) contribute every backticked name in that cell.
$documented = @{}
foreach ($line in Get-Content $wikiPage) {
    if ($line -notmatch '^\s*\|') { continue }
    $first = ($line -split '\|', 3)[1]
    foreach ($m in [regex]::Matches($first, '`(?<k>[a-z0-9-]+)`')) {
        $documented[$m.Groups['k'].Value] = $true
    }
}

# ---- Test 1: every live target is documented ----
$missing = @($live | Where-Object { -not $documented.ContainsKey($_) })
if ($missing.Count) {
    Write-Host ("FAIL: {0} live target(s) absent from wiki/Desktop.md: {1}" -f $missing.Count, ($missing -join ', ')) -ForegroundColor Red
    $script:fail++
} else {
    Write-Host ("PASS: all {0} live targets are documented in wiki/Desktop.md" -f $live.Count) -ForegroundColor Green
    $script:pass++
}

# ---- Test 2: no documented name is a target install.ps1 does not know ----
$unknown = @($documented.Keys | Where-Object { $_ -notin $live } | Sort-Object)
if ($unknown.Count) {
    Write-Host ("FAIL: wiki/Desktop.md names {0} target(s) install.ps1 does not declare: {1}" -f $unknown.Count, ($unknown -join ', ')) -ForegroundColor Red
    $script:fail++
} else {
    Write-Host 'PASS: every target name in the wiki table is declared by install.ps1' -ForegroundColor Green
    $script:pass++
}

# ---- Test 3: the page still carries the section that is being parity-checked ----
# A page with no table at all would pass test 1 vacuously once every target had
# been removed; requiring the header keeps the check honest about what it covers.
$wikiText = Get-Content $wikiPage -Raw
check 'the wiki page still carries the target table header' ($wikiText -match '(?m)^\|\s*target\s*\|\s*mechanism\s*\|')

if ($RedControl) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-wiki-parity-red-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $victim = Join-Path $tmp 'Desktop.md'
        $src = (Get-Content $wikiPage -Raw)
        # Mutant: the single Process Explorer row deleted -- a live target.
        $mut = [regex]::Replace($src, '(?m)^\|[^\n]*`processexplorer`[^\n]*\|\s*$', '')
        Set-Content -Path $victim -Value $mut -NoNewline
        $mutTxt = Get-Content $victim -Raw
        $dropped = -not ($mutTxt -match '(?m)^\|[^\n]*`processexplorer`')
        check 'RED: a page that drops a live target row is detected' $dropped
        # Control: the untouched page is still accepted.
        check 'RED control: the untouched page still documents that target' ($src -match '(?m)^\|[^\n]*`processexplorer`')
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail