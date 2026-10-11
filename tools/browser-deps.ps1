# Structural delivery gate for the browser-test dependency contract.
#
# tools/test-chatgpt-assistant-content.js, test-chatgpt-viewport-coverage.js,
# test-provider-image-preservation.js and test-x-interaction-safety.js call
# require('playwright'). Nothing installs it for a fresh checkout unless the
# manifests are COMMITTED, so this gate validates the delivered dependency
# contract instead of trusting a local node_modules:
#
#   * package.json / package-lock.json exist, are tracked by git and are not
#     excluded by .gitignore (repo mode only);
#   * package.json declares the Playwright devDependency and the lockfile pins a
#     matching resolved entry (byte-level parse, not a grep);
#   * `npm ci` against the COMMITTED bytes succeeds in a throwaway directory --
#     the project's own node_modules is never trusted or touched;
#   * require('playwright') resolves from that scratch install;
#   * the Chromium browser binary actually launches (skipped with
#     -SkipBrowserDownload for provisioned CI), and a missing runtime is an
#     explicit FAIL, never a silent pass.
#
# -RetainScratch keeps the scratch npm ci tree and prints its path so downstream
# tests can set NODE_PATH to resolve require('playwright') from the committed bytes.
#
# -RedControl builds a scratch copy of the manifests with the Playwright
# declaration REMOVED and requires this same dependency-contract check to fail
# there, so a green run depends on the committed declaration rather than on any
# local install. The tampered tree is a non-git scratch dir, so only the
# dependency-contract half runs against it.
param(
    [switch]$RedControl,
    [switch]$SkipBrowserDownload,
    [string]$ProjectRoot = '',
    [switch]$DependencyContractOnly,
    [switch]$RetainScratch
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = if ($ProjectRoot) { $ProjectRoot } else { Split-Path $here -Parent }
$pass = 0; $fail = 0
function check($label, $cond, $detail) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else {
        if ($detail) { Write-Host "FAIL: $label -- $detail" -ForegroundColor Red }
        else { Write-Host "FAIL: $label" -ForegroundColor Red }
        $script:fail++
    }
}

$pkgJson = Join-Path $root 'package.json'
$pkgLock = Join-Path $root 'package-lock.json'

# ── Repo delivery: the manifests ride the archive ───────────────────────────
if (-not $DependencyContractOnly) {
    check 'delivered: package.json exists' (Test-Path $pkgJson) ''
    check 'delivered: package-lock.json exists' (Test-Path $pkgLock) ''
    $t = & git -C $root ls-files --error-unmatch package.json 2>&1; $null
    check 'delivered: package.json is tracked by git' ($LASTEXITCODE -eq 0) ($t | Select-Object -First 1)
    $t = & git -C $root ls-files --error-unmatch package-lock.json 2>&1; $null
    check 'delivered: package-lock.json is tracked by git' ($LASTEXITCODE -eq 0) ($t | Select-Object -First 1)
    $t = & git -C $root check-ignore package.json 2>&1; $null
    check 'delivered: package.json is not gitignored' ($LASTEXITCODE -ne 0) ($t | Select-Object -First 1)
    $t = & git -C $root check-ignore package-lock.json 2>&1; $null
    check 'delivered: package-lock.json is not gitignored' ($LASTEXITCODE -ne 0) ($t | Select-Object -First 1)
}

# ── HEAD-byte verification: working tree must match committed bytes ───────────
# T-916: this check used to be skipped under -RedControl, and the full suite
# invokes the gate WITH -RedControl, so the delivery the operator actually ships
# was never HEAD-byte checked. The mode a caller picks must not be able to
# switch off the bytes the gate exists to prove, so it now runs in every mode
# except the contract-only mode that deliberately judges a non-git scratch tree.
if (-not $DependencyContractOnly) {
    # git's own comparison decides "differs from HEAD": the filters (eol=lf via
    # .gitattributes) are applied the same way a fresh checkout would see them,
    # so a candidate whose worktree bytes differ from the committed blob is not
    # proof that the committed delivery can npm ci.
    & git -C $root diff --quiet HEAD -- package.json package-lock.json 2>&1; $null
    check 'delivered: working tree matches HEAD bytes for both manifests' `
        ($LASTEXITCODE -eq 0) `
        ('git diff HEAD -- package.json package-lock.json reports uncommitted changes -- commit or stash before testing')
}

# ── The declaration, read from the bytes (never from a local install) ───────
if (-not (Test-Path $pkgJson)) { Write-Host "`nbrowser-deps: FAILED (no package.json at $root)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $pkgLock)) { Write-Host "`nbrowser-deps: FAILED (no package-lock.json at $root)" -ForegroundColor Red; exit 1 }

$pkg = Get-Content $pkgJson -Raw | ConvertFrom-Json
# node, not ConvertFrom-Json, reads the lockfile: Windows PowerShell 5.1 cannot
# deserialize an npm lock (its `packages[""]` root entry has an empty property
# name, which PSObject rejects), and that refusal would read as a gate failure.
$lockInfo = (& node -e "const l=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const r=l.packages&&l.packages['']||{};const e=l.packages&&l.packages['node_modules/playwright'];console.log(JSON.stringify({ver:l.lockfileVersion,root:(r.devDependencies||{}).playwright||'',entry:e?e.version:'',rootEngines:(r.engines||{}).node||'',pwEngines:(e&&e.engines)?e.engines.node:''}))" $pkgLock 2>&1) -join ''
$lock = $null
try { $lock = $lockInfo | ConvertFrom-Json } catch { }
$declared = $pkg.devDependencies.playwright
check 'deps: package.json declares devDependencies.playwright' ([bool]$declared) 'no "playwright" key under devDependencies'

check 'deps: package-lock pins node_modules/playwright' ($lock -and [bool]$lock.entry) 'lockfile has no resolved playwright entry'
check 'deps: the lockfile root records the same declaration' `
    ($lock -and ($lock.root -eq $declared)) `
    ('package.json=' + $declared + ' lock=' + $(if ($lock) { $lock.root } else { '(unreadable)' }))

# ── Engine floor: the root contract must not sit below Playwright's own floor ─
# A lockfile whose root declares node>=18 while playwright@1.62.1 requires >=20
# npm-installs cleanly today and warns on the operator's older node tomorrow.
# The floor is part of the delivered contract, so it is checked here, from the
# same bytes the fresh checkout would run.
$floorOk = $false
$floorDetail = ''
if ($pkg.engines -and $pkg.engines.node) {
    $rootFloor = [int](([regex]::Match($pkg.engines.node, '\d+')).Value)
    $pwFloor = [int](([regex]::Match($lock.pwEngines, '\d+')).Value)
    $floorOk = $rootFloor -ge $pwFloor
    $floorDetail = ('package.json engines.node=' + $pkg.engines.node + ' playwright requires >=' + $pwFloor)
} else {
    $floorDetail = 'package.json declares no engines.node'
}
check 'deps: root node floor satisfies the pinned playwright floor' $floorOk $floorDetail
# And the lockfile root must mirror it -- a hand-edited package.json that is not
# reflected in the committed lock is a delivery defect, not a detail.
$lockFloorOk = $false
$lockFloorDetail = ''
if ($lock -and $lock.rootEngines) {
    $lockFloorOk = $lock.rootEngines -eq $pkg.engines.node
    $lockFloorDetail = ('lockfile root engines.node=' + $lock.rootEngines + ' package.json=' + $pkg.engines.node)
} else {
    $lockFloorDetail = 'lockfile root declares no engines.node'
}
check 'deps: lockfile root engines mirror package.json' $lockFloorOk $lockFloorDetail

# ── npm ci from the committed bytes, in a throwaway tree ────────────────────
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-deps-' + [System.Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Copy-Item $pkgJson (Join-Path $scratch 'package.json')
    Copy-Item $pkgLock (Join-Path $scratch 'package-lock.json')

    Push-Location $scratch
    try {
        $ciOut = & npm ci --no-audit --no-fund 2>&1
        $ciExit = $LASTEXITCODE
        check 'deps: npm ci succeeds against the committed manifests' ($ciExit -eq 0) ("exit=" + $ciExit + " " + ($ciOut | Select-Object -Last 3 | Out-String).Trim())

        $probeOut = & node -e "try { require('playwright'); console.log('OK') } catch (e) { console.log('NO ' + (e.code || e.message)) }" 2>&1
        check 'deps: require("playwright") resolves from the scratch install' ($probeOut -eq 'OK') ("got: " + $probeOut)

        if (-not $SkipBrowserDownload -and $probeOut -eq 'OK') {
            $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $scratch 'pw-browsers'
            $dlOut = & npx playwright install chromium 2>&1
            $dlExit = $LASTEXITCODE
            check 'deps: npx playwright install chromium succeeds' ($dlExit -eq 0) ("exit=" + $dlExit + " " + ($dlOut | Select-Object -Last 3 | Out-String).Trim())
            $launchOut = & node -e "const {chromium}=require('playwright');chromium.launch({headless:true}).then(async b=>{const p=await b.newPage();await p.setContent('<b>x</b>');await b.close();console.log('LAUNCHED')}).catch(e=>console.log('NO ' + e.message.split('\n')[0]))" 2>&1
            check 'deps: a Chromium instance actually launches' ($launchOut -eq 'LAUNCHED') ("got: " + $launchOut)
            Remove-Item Env:\PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
        } elseif ($SkipBrowserDownload) {
            Write-Host 'SKIP: Chromium download/launch (provisioned CI)' -ForegroundColor DarkGray
        }
    } finally {
        Pop-Location
    }

    if ($RetainScratch) {
        # Output the scratch path so callers can set NODE_PATH
        Write-Host "SCRATCH_PATH:$scratch"
    }
} finally {
    if (-not $RetainScratch -and (Test-Path $scratch)) { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
}

# ── RED CONTROL: remove the declaration, the same check must fail ───────────
if ($RedControl) {
    $red = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-deps-red-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $red -Force | Out-Null
        # A package.json with the Playwright declaration deleted, and no lockfile
        # to install from: exactly the shipped-defect shape this gate exists for.
        $tampered = (Get-Content $pkgJson -Raw) -replace '"playwright"\s*:\s*"[^"]*"\s*,?', ''
        Set-Content -Path (Join-Path $red 'package.json') -Value $tampered -NoNewline
        Set-Content -Path (Join-Path $red 'package-lock.json') -Value (Get-Content $pkgLock -Raw) -NoNewline

        $redOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'browser-deps.ps1') -ProjectRoot $red -DependencyContractOnly -SkipBrowserDownload 2>&1
        $redExit = $LASTEXITCODE
        $namesIt = ($redOut -join "`n") -match 'playwright'
        check 'RED: removing the Playwright declaration makes this gate fail' ($redExit -ne 0) ("the tampered tree was still green: " + ($redOut | Select-Object -Last 3 | Out-String).Trim())
        check 'RED: and the failure names the missing Playwright dependency' $namesIt 'the gate failed for some other reason'
    } finally {
        if (Test-Path $red) { Remove-Item -Recurse -Force $red -ErrorAction SilentlyContinue }
    }
}

# ── RED CONTROL: dirty working bytes with tracked manifests must fail ────────
# Depth guard: the -RedControl child below must judge the SAME tampered tree
# without re-spawning its own dirty control, which would recurse forever.
if ($RedControl -and -not $DependencyContractOnly -and $env:WINTAGE_RED_DIRTY_DEPTH -ne '1') {
    $dirty = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-deps-dirty-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $dirty -Force | Out-Null
        # Build a real scratch git repo: manifests COMMITTED at HEAD, then the
        # working tree is modified. Full mode (not DependencyContractOnly) so the
        # HEAD-byte verification runs and must catch the dirty bytes.
        Push-Location $dirty
        try {
            & git init -q $dirty 2>&1 | Out-Null
            & git config user.email red@control 2>&1 | Out-Null
            & git config user.name 'RED control' 2>&1 | Out-Null
            # No eol churn in the scratch repo: core.autocrlf off and CRLF
            # warnings silenced, so the DIRTY control tests the gate rather than
            # the host's default line-ending policy.
            & git config core.autocrlf false 2>&1 | Out-Null
            & git config core.safecrlf false 2>&1 | Out-Null
            Copy-Item $pkgJson (Join-Path $dirty 'package.json')
            Copy-Item $pkgLock (Join-Path $dirty 'package-lock.json')
            # Native stderr (CRLF warning) would terminate under
            # $ErrorActionPreference='Stop' in PS 5.1; silence it for this block.
            $oldEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & git add package.json package-lock.json 2>$null | Out-Null
            & git commit -q -m 'manifests' 2>$null | Out-Null
            $ErrorActionPreference = $oldEap
            # Dirty the working tree: append one byte to package.json. That keeps
            # the JSON parseable (the gate must fail on the HEAD-byte check
            # itself, not on a broken manifest) while definitely differing.
            $dirtyFile = Join-Path $dirty 'package.json'
            [System.IO.File]::AppendAllText($dirtyFile, "`n")
        } finally { Pop-Location }

        $dirtyOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'browser-deps.ps1') -ProjectRoot $dirty -SkipBrowserDownload 2>&1
        $dirtyExit = $LASTEXITCODE
        $namesIt = ($dirtyOut -join "`n") -match 'reports uncommitted changes'
        check 'RED: tracked manifests with dirty working bytes fails HEAD-byte check' ($dirtyExit -ne 0) ("dirty tree was still green: " + ($dirtyOut | Select-Object -Last 3 | Out-String).Trim())
        check 'RED: and the failure names the HEAD-byte mismatch' $namesIt 'the gate failed for some other reason'
        # T-916: the same tampered tree under -RedControl. The full suite invokes
        # this gate WITH -RedControl, so the mode itself must not be able to hide
        # the mismatch -- previously the -RedControl branch skipped HEAD-byte
        # verification entirely and a dirty real tree shipped green.
        $env:WINTAGE_RED_DIRTY_DEPTH = '1'
        try {
            $dirtyRcOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'browser-deps.ps1') -ProjectRoot $dirty -SkipBrowserDownload -RedControl 2>&1
            $dirtyRcExit = $LASTEXITCODE
        } finally {
            Remove-Item Env:WINTAGE_RED_DIRTY_DEPTH -ErrorAction SilentlyContinue
        }
        $namesRc = ($dirtyRcOut -join "`n") -match 'reports uncommitted changes'
        check 'RED: tracked manifests with dirty working bytes fails HEAD-byte check under -RedControl' ($dirtyRcExit -ne 0) ("dirty tree was still green under -RedControl: " + ($dirtyRcOut | Select-Object -Last 3 | Out-String).Trim())
        check 'RED: and the -RedControl failure names the HEAD-byte mismatch' $namesRc 'the gate failed for some other reason'
    } finally {
        if (Test-Path $dirty) { Remove-Item -Recurse -Force $dirty -ErrorAction SilentlyContinue }
    }
}

if ($fail) {
    Write-Host "`nbrowser-deps: $fail gate(s) FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "`nbrowser-deps: PASS ($pass checks)" -ForegroundColor Green
exit 0