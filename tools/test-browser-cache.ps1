# Portable browser discovery cache + bounded preference scan regression suite
# (SRC-007:R015 / PERF-004, T-246).
#
# The audit measured that a remembered `-PortableRoot` made EVERY status refresh
# (`Get-ChildItem -Recurse -File` over an arbitrary user-selected subtree) part
# of the GUI's startup critical path and of every Apply/Revert refresh, and that
# each discovered profile had its complete `Preferences` file read into memory
# only to run two `.Contains` checks. This suite pins the repair:
#
#   * a warm cache answers a status refresh with ZERO recursive enumeration and
#     the identical candidate set;
#   * a walk happens only on a cold/corrupt cache, a changed root, an
#     invalidated cached candidate, or an explicit rescan;
#   * cached candidates are re-validated cheaply and a vanished browser is
#     dropped, never invented;
#   * preference matching is a bounded chunked byte search that still finds a
#     needle straddling a chunk boundary, in both the escaped and slash forms;
#   * a profile health answer with an unchanged fingerprint is served without
#     opening the preference file at all, and is invalidated the moment the file
#     changes;
#   * the portable walk keeps no depth bound and keeps product validation.
#
# The enumeration instrument is the `-Enumerator` parameter of the production
# decision function: the fixture supplies a COUNTING walker, so "the walk did not
# happen" is a measured fact rather than an inference, and no test-only branch
# exists in the tool.
#
#   .\tools\test-browser-cache.ps1          # all tests
#   .\tools\test-browser-cache.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$helper = Join-Path $here 'browser-discovery.ps1'
$tool = Join-Path $here 'install-browsers.ps1'
$installer = Join-Path $root 'desktop\install.ps1'
$pass = 0
$fail = 0
$skip = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function skip($label) {
    Write-Host "SKIP: $label" -ForegroundColor DarkYellow
    $script:skip++
}

function Write-Text([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

$tests = @(
    'cold cache walks once and persists the discovered candidates',
    'warm cache serves the same candidate set with ZERO enumeration',
    'explicit -Rescan re-walks an unchanged root',
    'deleted cache walks again',
    'changed root re-walks and keeps one bounded portable entry',
    'invalidated cached candidate is dropped AND triggers rediscovery',
    'corrupt cache is treated as absent, without a crash',
    'no root / missing root never walks',
    'catalog mode stays authoritative and never walks',
    'bounded search matches escaped and slash forms',
    'bounded search finds a needle straddling a chunk boundary',
    'bounded search agrees with the whole-file reference on every shape',
    'unchanged fingerprint serves the answer without opening the file',
    'changed preference file invalidates the cached profile answer',
    'production tool delegates discovery and never walks inline',
    'portable walk keeps product validation and no depth bound',
    'install.ps1 exposes an explicit rescan at both browser call sites',
    'end-to-end: real walker, large tree, walk-once then cache-served',
    'end-to-end: warm cache never invents a browser whose exe vanished',
    'RED A: cache-bypassing mutant reproduces the walk-on-every-refresh defect',
    'RED B: fingerprint-bypassing mutant reproduces the re-read defect'
)
if ($List) {
    Write-Host "test-browser-cache.ps1 ($($tests.Count) tests):"
    $i = 1
    foreach ($t in $tests) { Write-Host "  $i. $t"; $i++ }
    exit 0
}

. $helper

# ---- fixture -----------------------------------------------------------------
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-r015-' + [guid]::NewGuid().ToString('N'))
$cacheRoot = Join-Path $fixture 'appdata'
$portable = Join-Path $fixture 'portable'
New-Item -ItemType Directory -Force -Path $cacheRoot, $portable | Out-Null

# A broad, deep tree of UNRELATED files: the exact shape that made the audit's
# PortableRoot expensive. Nothing here is a browser candidate.
foreach ($depth in 1..6) {
    $dir = Join-Path $portable ('unrelated\level{0}\nested' -f $depth)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($n in 1..40) { Write-Text (Join-Path $dir ("asset$n.txt")) ("payload $n") }
}

function New-PortableBrowserAt([string]$base, [string]$exeSource, [string]$name = 'msedge.exe') {
    $dir = Join-Path $base 'Deeply\Nested\PortableBrowser'
    $data = Join-Path $dir 'User Data'
    New-Item -ItemType Directory -Force -Path (Join-Path $data 'Default') | Out-Null
    Write-Text (Join-Path $data 'Local State') '{}'
    $exe = Join-Path $dir $name
    if ($exeSource) { Copy-Item -LiteralPath $exeSource -Destination $exe -Force } else { [System.IO.File]::WriteAllBytes($exe, [byte[]]@()) }
    return [pscustomobject]@{ Exe = $exe; UserData = $data; Dir = $dir }
}

# The synthetic enumerator: counts walks and returns whatever the fixture says
# exists, so the cache decision is observable without a real browser binary.
# The counter lives in a hashtable because a closure captures the REFERENCE, so
# the count survives the walk being invoked from inside the production function.
$script:WalkState = @{ Calls = 0 }
function New-CountingEnumerator([object[]]$scripted) {
    return { param([string]$PortableRoot) $WalkState.Calls = $WalkState.Calls + 1; return @($scripted) }.GetNewClosure()
}
function Reset-WalkCount { $script:WalkState.Calls = 0 }

$candidateA = [pscustomobject]@{ Name = 'Fixture Chromium'; Exe = $null; UserData = $null }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $cacheRoot 'fixture-user-data') | Out-Null
$candidateA.Exe = Join-Path $cacheRoot 'fixture-user-data\chrome.exe'
$candidateA.UserData = Join-Path $cacheRoot 'fixture-user-data'
[System.IO.File]::WriteAllBytes($candidateA.Exe, [byte[]]@())

try {
    # ---- 1..8: the discovery decision ---------------------------------------
    Reset-WalkCount
    $cold = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    check 'cold cache: mode is walked and the walker ran exactly once' ($cold.Mode -eq 'walked' -and $cold.Walks -eq 1 -and $script:WalkState.Calls -eq 1)
    $cacheFile = Get-BrowserCachePath $cacheRoot
    check 'cold cache: the discovery is persisted to the cache file' (Test-Path -LiteralPath $cacheFile)
    $persisted = Read-BrowserDiscoveryFile $cacheRoot
    $key = Get-PortableRootKey $portable
    check 'cold cache: the persisted key is the case-insensitive absolute root' ($persisted.portable.PSObject.Properties.Name -contains $key)
    check 'cold cache: the discovered candidate round-trips' (@($persisted.portable.$key.candidates).Count -eq 1 -and $persisted.portable.$key.candidates[0].Exe -eq $candidateA.Exe)

    Reset-WalkCount
    $warm = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    check 'warm cache: served from cache with ZERO enumerator calls' ($warm.Mode -eq 'cache' -and $warm.Walks -eq 0 -and $script:WalkState.Calls -eq 0)
    check 'warm cache: identical candidate set as the walk' (@($warm.Candidates).Count -eq @($cold.Candidates).Count -and $warm.Candidates[0].Exe -eq $cold.Candidates[0].Exe -and $warm.Candidates[0].UserData -eq $cold.Candidates[0].UserData)

    Reset-WalkCount
    $rescanned = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Rescan -Enumerator (New-CountingEnumerator @($candidateA))
    check 'explicit -Rescan re-walks the unchanged root' ($rescanned.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1)

    Remove-Item -LiteralPath $cacheFile -Force
    Reset-WalkCount
    $recold = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    check 'deleted cache: the next refresh walks again' ($recold.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1)

    $otherRoot = Join-Path $fixture 'portable-2'
    New-Item -ItemType Directory -Force -Path $otherRoot | Out-Null
    Reset-WalkCount
    $moved = Get-PortableCandidates -PortableRoot $otherRoot -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    $afterMove = Read-BrowserDiscoveryFile $cacheRoot
    check 'changed root: re-walks on the key mismatch' ($moved.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1)
    check 'changed root: the portable section stays bounded to ONE root' (@($afterMove.portable.PSObject.Properties).Count -eq 1 -and @($afterMove.portable.PSObject.Properties.Name)[0] -eq (Get-PortableRootKey $otherRoot))

    $vanishing = [pscustomobject]@{ Name = 'Vanishing'; Exe = (Join-Path $cacheRoot 'fixture-user-data\gone.exe'); UserData = (Join-Path $cacheRoot 'fixture-user-data') }
    [System.IO.File]::WriteAllBytes($vanishing.Exe, [byte[]]@())
    Reset-WalkCount
    $null = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($vanishing))
    Remove-Item -LiteralPath $vanishing.Exe -Force
    Reset-WalkCount
    $invalidated = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @())
    check 'invalidated cached candidate: dropped AND a walk is forced' ($invalidated.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1 -and @($invalidated.Candidates).Count -eq 0)

    Write-Text $cacheFile '{"schema":1,"portable":{'
    Reset-WalkCount
    $corrupt = Get-PortableCandidates -PortableRoot $portable -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    check 'corrupt cache: treated as absent, no crash, rediscovered' ($corrupt.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1 -and (Test-Path -LiteralPath $cacheFile))
    check 'corrupt cache: the file is rewritten in a readable shape' ($null -ne (Read-BrowserDiscoveryFile $cacheRoot))

    Reset-WalkCount
    $noRoot = Get-PortableCandidates -PortableRoot '' -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    $missingRoot = Get-PortableCandidates -PortableRoot (Join-Path $fixture 'does-not-exist') -CacheRoot $cacheRoot -Enumerator (New-CountingEnumerator @($candidateA))
    check 'no root / missing root: mode none and the walker never runs' ($noRoot.Mode -eq 'none' -and $missingRoot.Mode -eq 'none' -and $script:WalkState.Calls -eq 0)

    # ---- 9: catalog mode stays authoritative ---------------------------------
    $catalogRoot = Join-Path $fixture 'catalog-appdata'
    New-Item -ItemType Directory -Force -Path $catalogRoot | Out-Null
    $catalogBrowser = New-PortableBrowserAt $fixture $null
    $catalogFile = Join-Path $fixture 'catalog.json'
    $catalogJson = @(@{ Name = 'Fixture Chromium'; Exe = $catalogBrowser.Exe; UserData = $catalogBrowser.UserData }) | ConvertTo-Json
    Write-Text $catalogFile $catalogJson
    $prevAppData = $env:WINTAGE_APPDATA
    $env:WINTAGE_APPDATA = $catalogRoot
    $catalogOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ListJson -Catalog $catalogFile -PortableRoot $portable -StageRoot (Join-Path $fixture 'stage') 2>&1 | Out-String).Trim()
    $env:WINTAGE_APPDATA = $prevAppData
    $catalogSummary = $null
    try { $catalogSummary = $catalogOut | ConvertFrom-Json } catch { $catalogSummary = $null }
    check 'catalog mode: listing succeeds and reports NO portable walk' ($null -ne $catalogSummary -and $catalogSummary.PortableDiscovery -eq 'none')
    $catalogCache = Read-BrowserDiscoveryFile $catalogRoot
    check 'catalog mode: no portable candidate is cached' (-not $catalogCache -or -not $catalogCache.portable -or -not @($catalogCache.portable.PSObject.Properties).Count)

    # ---- 10..12: bounded preference scanning ---------------------------------
    $needleDir = Join-Path $fixture 'needle'
    New-Item -ItemType Directory -Force -Path $needleDir | Out-Null
    $stage = Join-Path $fixture 'stage-root'
    $escaped = $stage.Replace('\', '\\')
    $slashed = $stage.Replace('\', '/')
    $escapedFile = Join-Path $needleDir 'escaped.json'
    Write-Text $escapedFile ('{"p":"' + $escaped + '"}')
    $slashedFile = Join-Path $needleDir 'slashed.json'
    Write-Text $slashedFile ('{"p":"' + $slashed + '"}')
    $absentFile = Join-Path $needleDir 'absent.json'
    Write-Text $absentFile '{"p":"C:/somewhere/else"}'
    check 'bounded search: escaped-backslash form matches' (Test-FileContainsAnyBounded -Path $escapedFile -Needles @($escaped, $slashed))
    check 'bounded search: slash form matches' (Test-FileContainsAnyBounded -Path $slashedFile -Needles @($escaped, $slashed))
    check 'bounded search: an unrelated file does not match' (-not (Test-FileContainsAnyBounded -Path $absentFile -Needles @($escaped, $slashed)))

    $straddle = Join-Path $needleDir 'straddle.json'
    $pad = 'A' * 4096
    $writer = [System.IO.StreamWriter]::new($straddle, $false, $utf8NoBom)
    try {
        for ($i = 0; $i -lt 16; $i++) { $writer.Write($pad) }   # 64 KiB of padding
        $writer.Write($escaped)
        $writer.Write($pad)
    } finally { $writer.Dispose() }
    $straddling = $false
    foreach ($chunk in 8, 64, 4096, 65536) {
        if (-not (Test-FileContainsAnyBounded -Path $straddle -Needles @($escaped, $slashed) -ChunkBytes $chunk)) { $straddling = $true }
    }
    check 'bounded search: finds a needle at a 64 KiB boundary for every chunk size' (-not $straddling)

    $shapes = @()
    $shapes += [pscustomobject]@{ Name = 'at start'; Text = $escaped + $pad }
    $shapes += [pscustomobject]@{ Name = 'at end'; Text = $pad + $slashed }
    $shapes += [pscustomobject]@{ Name = 'middle'; Text = $pad + $escaped + $pad }
    $shapes += [pscustomobject]@{ Name = 'empty file'; Text = '' }
    $shapes += [pscustomobject]@{ Name = 'no match'; Text = $pad }
    $shapes += [pscustomobject]@{ Name = 'partial prefix only'; Text = $escaped.Substring(0, [Math]::Max(1, $escaped.Length - 1)) }
    $parity = $true
    foreach ($shape in $shapes) {
        $path = Join-Path $needleDir ('shape-' + ($shape.Name -replace ' ', '_') + '.json')
        Write-Text $path $shape.Text
        # Test-only reference: the whole-file semantics the bounded search replaces.
        $raw = [System.IO.File]::ReadAllText($path)
        $reference = $raw.Contains($escaped) -or $raw.Contains($slashed)
        $actual = [bool](Test-FileContainsAnyBounded -Path $path -Needles @($escaped, $slashed))
        if ($actual -ne $reference) { $parity = $false; Write-Host "  parity break on '$($shape.Name)': reference=$reference actual=$actual" -ForegroundColor DarkYellow }
    }
    check 'bounded search: identical verdict to the whole-file reference on 6 shapes' $parity

    # ---- 13..14: profile fingerprint cache -----------------------------------
    $profileRoot = Join-Path $fixture 'profile'
    New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
    $prefs = Join-Path $profileRoot 'Preferences'
    Write-Text $prefs ('{"theme":"' + $escaped + '"}')

    $stableCache = @{}
    check 'profile answer: first read detects the staged theme' ([bool](Get-ProfileThemeLoaded -ProfilePath $profileRoot -StageRoot $stage -Cache $stableCache))
    $locked = $false
    $handle = $null
    try {
        $handle = [System.IO.File]::Open($prefs, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $locked = $true
    } catch { $locked = $false }
    if ($locked) {
        $cachedAnswer = [bool](Get-ProfileThemeLoaded -ProfilePath $profileRoot -StageRoot $stage -Cache $stableCache)
        $coldAnswer = [bool](Get-ProfileThemeLoaded -ProfilePath $profileRoot -StageRoot $stage -Cache @{})
        check 'profile answer: unchanged fingerprint is served WITHOUT opening the file' ($cachedAnswer)
        check 'profile answer: a fresh cache really does open the file (lock is observable)' (-not $coldAnswer)
        $handle.Dispose()
    } else {
        skip 'profile answer: exclusive-lock probe unavailable on this filesystem'
    }

    Write-Text $prefs '{"theme":"plain"}'
    [System.IO.File]::SetLastWriteTimeUtc($prefs, [datetime]::UtcNow.AddSeconds(5))
    check 'profile answer: a changed preference file invalidates the cached answer' (-not [bool](Get-ProfileThemeLoaded -ProfilePath $profileRoot -StageRoot $stage -Cache $stableCache))

    # ---- 15..17: production wiring ------------------------------------------
    $toolSrc = Get-Content $tool -Raw
    $helperSrc = Get-Content $helper -Raw
    $installerSrc = Get-Content $installer -Raw
    check 'tool: portable discovery is delegated to the cache decision' ($toolSrc -match 'Get-PortableCandidates' -and $toolSrc -match 'Get-ProfileThemeLoaded')
    $profilesStart = $toolSrc.IndexOf('function Get-BrowserProfiles')
    $profilesEnd = $toolSrc.IndexOf('function Get-Summary')
    $profilesBlock = $toolSrc.Substring($profilesStart, $profilesEnd - $profilesStart)
    # Comments legitimately name the call this guard forbids, so the scan runs
    # on code only.
    $profilesCode = (($profilesBlock -split "`n") | Where-Object { $_.Trim() -notmatch '^#' }) -join "`n"
    check 'tool: the profile scan performs no whole-file read' ($profilesCode -notmatch 'ReadAllText')
    check 'tool: no recursive enumeration remains anywhere in the tool' ($toolSrc -notmatch 'Get-ChildItem[^\r\n]*-Recurse')
    check 'tool: the bounded search replaced the whole-file Contains checks' ($toolSrc -notmatch '(?m)\.Contains\(\$escapedStage\)')
    check 'walk: no depth bound is imposed on the supported layout' ($helperSrc -notmatch 'Get-ChildItem[^\r\n]*-Depth')
    check 'walk: product validation and candidate resolution survive' ($helperSrc -match 'VersionInfo\.ProductName' -and $helperSrc -match "BROWSER_PRODUCT_RE" -and $helperSrc -match "'Local State'")
    check 'install.ps1: -RescanBrowsers is forwarded at the listing site' ([regex]::Matches($installerSrc, "(?m)^\s*if \(\`$RescanBrowsers\) \{ \`$browserArgs \+= '-Rescan' \}").Count -ge 2)
    check 'install.ps1: -RescanBrowsers is passed to re-apply children' ($installerSrc -match "\`$passArgs\['-RescanBrowsers'\]")

    # ---- 18..19: end-to-end with the real walker -----------------------------
    $realExe = $null
    foreach ($probe in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'),
            'C:\Program Files\Google\Chrome\Application\chrome.exe',
            'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')) {
        if (Test-Path -LiteralPath $probe) { $realExe = $probe; break }
    }
    if (-not $realExe) {
        skip 'end-to-end: no Chromium binary on this machine for a real-walker fixture'
        skip 'end-to-end: warm-cache stale-candidate guard'
    } else {
        $liveRoot = Join-Path $fixture 'live-portable'
        $live = New-PortableBrowserAt $liveRoot $realExe
        foreach ($depth in 1..4) {
            $dir = Join-Path $liveRoot ('filler\a{0}\b' -f $depth)
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            foreach ($n in 1..25) { Write-Text (Join-Path $dir ("x$n.bin")) 'noise' }
        }
        $liveCache = Join-Path $fixture 'live-appdata'
        Reset-WalkCount
        $realCold = Get-PortableCandidates -PortableRoot $liveRoot -CacheRoot $liveCache
        $realWarm = Get-PortableCandidates -PortableRoot $liveRoot -CacheRoot $liveCache
        check 'end-to-end: a deep large tree yields the real candidate on the first walk' ($realCold.Mode -eq 'walked' -and @($realCold.Candidates).Count -eq 1 -and $realCold.Candidates[0].Exe -ieq $live.Exe)
        check 'end-to-end: the second refresh is cache-served with the same candidate' ($realWarm.Mode -eq 'cache' -and @($realWarm.Candidates).Count -eq 1 -and $realWarm.Candidates[0].UserData -ieq $realCold.Candidates[0].UserData)
        check 'end-to-end: the served candidate is the deepest-first resolved UserData' ($realWarm.Candidates[0].UserData -ieq (Get-Item -LiteralPath $live.UserData).FullName.TrimEnd('\'))
        Remove-Item -LiteralPath $live.Exe -Force
        $afterRemoval = Get-PortableCandidates -PortableRoot $liveRoot -CacheRoot $liveCache -Enumerator { param([string]$r) @() }
        check 'end-to-end: a vanished executable is never served from cache' (@($afterRemoval.Candidates | Where-Object { $_.Exe -ieq $live.Exe }).Count -eq 0)
    }

    # ---- 20..21: red controls (temporary source mutants only) ----------------
    $mutantRoot = Join-Path $fixture 'mutants'
    New-Item -ItemType Directory -Force -Path $mutantRoot | Out-Null

    $mutantA = Join-Path $mutantRoot 'cache-bypassed.ps1'
    $mutantSrcA = $helperSrc.Replace('if (-not $Rescan -and $Data) {', 'if ($false) {')
    $mutantChanged = ($mutantSrcA -ne $helperSrc)
    Write-Text $mutantA $mutantSrcA
    $redA = & powershell -NoProfile -ExecutionPolicy Bypass -Command @"
. '$mutantA'
`$calls = 0
`$walker = { param([string]`$r) `$script:calls = `$script:calls + 1; @() }
`$one = Get-PortableCandidates -PortableRoot '$portable' -CacheRoot '$cacheRoot' -Enumerator `$walker
`$two = Get-PortableCandidates -PortableRoot '$portable' -CacheRoot '$cacheRoot' -Enumerator `$walker
Write-Host ('mode=' + `$two.Mode + ' walks=' + `$script:calls)
"@
    check 'RED A: the mutation actually applied to the copied source' $mutantChanged
    check 'RED A: without the cache branch every refresh walks (old defect reproduced)' ($redA -match 'walks=2')

    $mutantB = Join-Path $mutantRoot 'fingerprint-bypassed.ps1'
    $mutantSrcB = $helperSrc.Replace("        if (`$entry -and `$entry.fp -eq `$fingerprint) { return [bool]`$entry.themeLoaded }", '        if ($false) { return [bool]$entry.themeLoaded }')
    $mutantChangedB = ($mutantSrcB -ne $helperSrc)
    Write-Text $mutantB $mutantSrcB
    $probeDir = Join-Path $fixture 'mutant-profile'
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    $probePrefs = Join-Path $probeDir 'Preferences'
    Write-Text $probePrefs ('{"theme":"' + $escaped + '"}')
    $redB = & powershell -NoProfile -ExecutionPolicy Bypass -Command @"
. '$mutantB'
`$cache = @{}
`$null = Get-ProfileThemeLoaded -ProfilePath '$probeDir' -StageRoot '$stage' -Cache `$cache
`$h = [System.IO.File]::Open('$probePrefs', [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
`$cached = Get-ProfileThemeLoaded -ProfilePath '$probeDir' -StageRoot '$stage' -Cache `$cache
`$h.Dispose()
Write-Host ('cachedWhileLocked=' + `$cached)
"@
    check 'RED B: the mutation actually applied to the copied source' $mutantChangedB
    check 'RED B: without the fingerprint shortcut the file is re-read while locked (old defect reproduced)' ($redB -match 'cachedWhileLocked=False')
} finally {
    if ($handle) { try { $handle.Dispose() } catch { } }
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("test-browser-cache.ps1: $pass PASS / $fail FAIL / $skip SKIP") -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
