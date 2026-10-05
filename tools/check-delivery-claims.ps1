# Delivery-claim resolver (T-417; improve cycle imp-vacterro-wintage-20261005-4, RUN-1/IMP-004).
#
# Defect class this gate pins down:
# the T-413 delivery report listed "the npm test/test:bd script repair" as part
# of the deliverable, in `package.json`. That file is excluded by .gitignore:60,
# has no git history and is absent from the release archive, so the recipient
# could not open or verify the claim and read it as stale narration from another
# environment -- which is exactly how the operator reported it. The SHIP phase
# writes the delivery text (.saipen/kitchen/digest.md), and until now nothing
# compared what that text CLAIMED against what the artifact CONTAINS.
#
# The contract enforced here: every path-shaped token in the report either
# resolves in the artifact -- present in HEAD, or staged for the commit that is
# being written, since release.ps1 builds the archive from tracked files -- or
# the reporter declares it with -Allow. A token that exists in this working copy but is not tracked (ignored,
# or never added) is a FAIL, named together with the rule that excluded it; so
# is a token that resolves nowhere. "Present on disk" is deliberately NOT the
# test: the working copy is not the deliverable, and an ignored file is the very
# case that fooled the T-413 report.
#
#   tools/check-delivery-claims.ps1                      # the current digest
#   tools/check-delivery-claims.ps1 -Path <report.md>
#   tools/check-delivery-claims.ps1 -Allow 'docs/*'      # declared non-product
#   tools/check-delivery-claims.ps1 -List                # tokens, no verdict
#   tools/check-delivery-claims.ps1 -RedControl          # scratch-repo red/green
#
# Exit 0 = every claim resolves, 1 = a claim does not, 2 = usage error.

[CmdletBinding()]
param(
    [string]$Path,
    [string]$Root,
    [string[]]$Allow = @(),
    [switch]$List,
    [switch]$RedControl
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$script:repoRoot = if ($Root) { $Root } else { Split-Path $here -Parent }

# A path-shaped token: slash-separated segments ending in an alphabetic
# extension, with a sentence-final period allowed but not a further dot-chain
# (so `tests/Run-Tests.ps1.` is a token and `v1.36.1` still is not). The
# numeric-shape guard keeps version strings (1.36.6, v1.36.1)
# and prose out; the drive-letter and scheme guards keep runtime paths and URLs
# out. Over-matching is the safe direction: a false positive is a sentence to
# reword, a false negative is an unverifiable claim that ships.
function Get-ClaimTokens([string]$text) {
    $flat = $text -replace '\\', '/'
    $out = New-Object System.Collections.ArrayList
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($flat, '(?<![\w/.-])(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z][A-Za-z0-9]{0,5}(?![\w/-])(?!\.\w)')) {
        $t = $m.Value
        $start = [Math]::Max(0, $m.Index - 4)
        $ctx = $flat.Substring($start, $m.Index - $start)
        if ($ctx -match '://') { continue }
        if ($t -match '^[A-Za-z]:/') { continue }
        if ($t.StartsWith('/')) { continue }
        $t = $t -replace '^\./', ''
        if ($seen.Add($t)) { [void]$out.Add($t) }
    }
    @($out)
}

# Native stderr is not an error signal here -- `git ls-files --error-unmatch`
# reports a miss through it -- so every git call runs with stderr discarded and
# a preserved ErrorActionPreference, the same shape the suite uses.
function Invoke-GitQuiet([string]$root, [string[]]$a, [switch]$StderrToo) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = if ($StderrToo) { & git -C $root @a 2>&1 } else { & git -C $root @a 2>$null }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Code = $code; Out = @($out) }
}

function Test-Claim([string]$token, [string[]]$allow) {
    foreach ($a in $allow) { if ($token -like $a) { return @{ Tier = 'allowed'; Rule = "declared with -Allow $a" } } }
    $where = $null
    if ((Invoke-GitQuiet $script:repoRoot @('ls-files', '--error-unmatch', '--', $token)).Code -eq 0) { $where = 'the index' }
    elseif ((Invoke-GitQuiet $script:repoRoot @('cat-file', '-e', "HEAD:$token")).Code -eq 0) { $where = 'HEAD' }
    if ($where) { return @{ Tier = 'tracked'; Rule = "tracked in $where, so the archive carries it" } }
    if (Test-Path (Join-Path $script:repoRoot $token)) {
        $why = (Invoke-GitQuiet $script:repoRoot @('check-ignore', '-v', '--', $token, '2>$null')).Out
        $rule = if ($why.Count -and $why[0]) { $why[0] } else { 'untracked' }
        return @{ Tier = 'present'; Rule = "exists in this working copy but not in the artifact ($rule)" }
    }
    return @{ Tier = 'missing'; Rule = 'resolves nowhere in the artifact' }
}

function Invoke-ClaimCheck([string]$path, [string[]]$allow, [switch]$listOnly) {
    $text = [System.IO.File]::ReadAllText($path)
    $tokens = Get-ClaimTokens $text
    if ($listOnly) { foreach ($t in $tokens) { Write-Host $t }; return 0 }
    Write-Host "delivery claims in $(Split-Path $path -Leaf) -- resolved against $(Split-Path $script:repoRoot -Leaf)"
    if ($tokens.Count -eq 0) { Write-Host '  (no path-shaped claim to resolve)'; return 0 }
    $tracked = 0; $allowed = 0; $bad = New-Object System.Collections.ArrayList
    foreach ($t in $tokens) {
        $r = Test-Claim $t $allow
        switch ($r.Tier) {
            'tracked' { $tracked++; Write-Host "  [ok]   $t -- $($r.Rule)" -ForegroundColor DarkGray }
            'allowed' { $allowed++; Write-Host "  [ok]   $t -- $($r.Rule)" -ForegroundColor DarkGray }
            default   { [void]$bad.Add($t); Write-Host "  [FAIL] $t -- $($r.Rule)" -ForegroundColor Red }
        }
    }
    Write-Host "RESULT: $($tokens.Count) claim(s): $tracked resolved in the artifact, $allowed declared, $($bad.Count) unverifiable"
    if ($bad.Count) { Write-Host "  the report names $(if ($bad.Count -eq 1) { 'a path' } else { 'paths' }) the recipient cannot open: $(($bad | Select-Object -First 10) -join ', ')" }
    return $bad.Count
}

# Proven in a scratch repository: this checkout is never mutated.
function Test-ScratchRepo {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-claims-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    $previousRoot = $script:repoRoot
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $script:repoRoot = $tmp
        Invoke-GitQuiet $tmp @('init', '-q', '.') | Out-Null
        Invoke-GitQuiet $tmp @('config', 'user.email', 'probe@localhost') | Out-Null
        Invoke-GitQuiet $tmp @('config', 'user.name', 'probe') | Out-Null
        Set-Content -Path (Join-Path $tmp '.gitignore') -Value 'package.json'
        New-Item -ItemType Directory -Path (Join-Path $tmp 'tools') -Force | Out-Null
        Set-Content -Path (Join-Path $tmp 'tools/foo.js') -Value '// tracked'
        Set-Content -Path (Join-Path $tmp 'package.json') -Value '{}'
        Invoke-GitQuiet $tmp @('add', '-A') | Out-Null
        $commit = Invoke-GitQuiet $tmp @('commit', '-q', '-m', 'scratch')
        check 'scratch setup: the fixture repository committed tools/foo.js' ($commit.Code -eq 0)

        $good = Join-Path $tmp 'good.md'
        Set-Content -Path $good -Value 'T-900 shipped tools/foo.js and .gitignore. Version 1.36.6 was not touched.'
        $okTokens = @(Get-ClaimTokens ([System.IO.File]::ReadAllText($good)))
        $okBad = @($okTokens | Where-Object { (Test-Claim $_ @()).Tier -ne 'tracked' })
        check 'scratch green: a report naming only tracked paths resolves (only tools/foo.js is a token here)' `
            ($okTokens.Count -eq 1 -and $okTokens[0] -eq 'tools/foo.js' -and $okBad.Count -eq 0)
        check 'scratch green control: version strings and dot-prefixed files are not claim tokens' `
            (@(@(Get-ClaimTokens 'v1.36.1 1.36.6, .gitignore') | Where-Object { $_ -match '1\.36|\.gitignore' }).Count -eq 0)

        $bad = Join-Path $tmp 'bad.md'
        Set-Content -Path $bad -Value "Done: the npm test/test:bd script repair in package.json, plus tools/foo.js."
        $badTokens = @(Get-ClaimTokens ([System.IO.File]::ReadAllText($bad)))
        $badVerdicts = @($badTokens | ForEach-Object { @{ t = $_; r = (Test-Claim $_ @()) } } | Where-Object { $_.r.Tier -ne 'tracked' })
        check 'scratch red: an ignored file the report claims is unverifiable and named (package.json)' `
            ($badVerdicts.Count -eq 1 -and $badVerdicts[0].t -eq 'package.json' -and $badVerdicts[0].r.Rule -match 'gitignore')
        check 'scratch red control: the tracked file in the same sentence still resolves (tools/foo.js)' `
            ((Test-Claim 'tools/foo.js' @()).Tier -eq 'tracked')

        check 'scratch red: a claim that resolves nowhere is unverifiable (src/ghost.js)' `
            ((Test-Claim 'src/ghost.js' @()).Tier -eq 'missing')
        check 'scratch green: -Allow declares a non-product path instead of failing on it' `
            ((Test-Claim 'package.json' @('package.json')).Tier -eq 'allowed')
    }
    finally {
        $script:repoRoot = $previousRoot
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

$script:pass = 0; $script:fail = 0
function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($RedControl) {
    Write-Host 'delivery-claim resolver -- -RedControl (scratch repository; this checkout is not mutated)'
    Test-ScratchRepo
    Write-Host "`n$($script:pass) PASS, $($script:fail) FAIL" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
    exit $script:fail
}

$subject = if ($Path) { $Path } else { Join-Path $script:repoRoot '.saipen/kitchen/digest.md' }
if (-not (Test-Path -LiteralPath $subject)) {
    Write-Host "usage: no report to read at $subject" -ForegroundColor Red
    exit 2
}
$bad = Invoke-ClaimCheck $subject $Allow -listOnly:$List
exit $(if ($bad -gt 0) { 1 } else { 0 })
