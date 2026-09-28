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
#     needle straddling a chunk boundary, in both the escaped and slash forms,
#     and whose RESIDENT WINDOW stays chunk+overlap as the file grows (a large
#     synthetic 8/64 MiB Preferences file proves total bytes read scales while
#     the working buffer does not);
#   * a profile health answer with an unchanged fingerprint is served without
#     opening the preference file at all, and is invalidated the moment the file
#     changes;
#   * the portable walk keeps no depth bound and keeps product validation;
#   * an explicitly rescanned root discovers a browser added after the cache was
#     established, and a replaced/invalidated cached executable never survives
#     rediscovery;
#   * a REAL WinForms startup (desktop/WintageInstaller.ps1) with a warm cache
#     reaches the Shown event with ZERO recursive portable walker invocations,
#     while the same startup with a cold cache and a deliberately slow walker is
#     visibly delayed (RED C);
#   * warm-cache status parity covers the full profile record (browser, profile,
#     Tampermonkey, ThemeLoaded), not just executable paths.
#
# The enumeration instrument is the `-Enumerator` parameter of the production
# decision function: the fixture supplies a COUNTING walker, so "the walk did not
# happen" is a measured fact rather than an inference, and no test-only branch
# exists in the tool. The live WinForms smoke additionally arms the real walker's
# own count file and deliberate-sleep seam
# (WINTAGE_TEST_WALK_COUNT_FILE / WINTAGE_TEST_WALK_SLOW_MS), so the REAL child
# install.ps1 path proves the cached startup never invokes it.
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
    'large Preferences file: no match with a bounded working buffer',
    'large Preferences file: StageRoot near the end matches',
    'large Preferences file: StageRoot across a chunk boundary matches',
    'unchanged fingerprint serves the answer without opening the file',
    'changed preference file invalidates the cached profile answer',
    'production tool delegates discovery and never walks inline',
    'portable walk keeps product validation and no depth bound',
    'install.ps1 exposes an explicit rescan at both browser call sites',
    'end-to-end: real walker, large tree, walk-once then cache-served',
    'end-to-end: warm cache never invents a browser whose exe vanished',
    'rescan: explicit -Rescan discovers a browser added after caching (real walker)',
    'rescan: explicit -Rescan discovers an added browser (decision-level)',
    'replace: a replaced/invalidated cached executable never survives rediscovery',
    'live WinForms smoke: cached startup reaches Shown with zero walker invocations',
    'RED C: a cold cache with a slow walker is caught delaying the usable form',
    'parity: warm cache preserves browser/profile/Tampermonkey/theme status exactly',
    'RED A: cache-bypassing mutant reproduces the walk-on-every-refresh defect',
    'RED B: fingerprint-bypassing mutant reproduces the re-read defect',
    'INSTRUMENT CONTROL: the bounded-window gate goes red on an unbounded-chunk mutant'
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

function New-PortableBrowserAt([string]$base, [string]$exeSource, [string]$name = 'msedge.exe', [string]$leaf = 'PortableBrowser') {
    $dir = Join-Path $base ('Deeply\Nested\' + $leaf)
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

    # ---- 12b: LARGE Preferences file -- bounded working memory -----------------
    # The audit's missing clause: "Feed a large synthetic Preferences file and
    # assert peak memory remains bounded rather than proportional to file size."
    # The fixture streams the file (never one giant PowerShell string) and the
    # scanner reports its OWN working-buffer cardinality, so the bound is proven
    # against a measured counter rather than process-wide RSS noise.
    function New-LargePreferencesFile {
        param([string]$Path, [long]$SizeBytes, [string]$Needle = '', [long]$NeedleOffset = -1)
        $blockSize = 262144
        $block = New-Object byte[] $blockSize
        for ($i = 0; $i -lt $blockSize; $i++) { $block[$i] = [byte][char]'A' }
        $needleBytes = if ($Needle) { [System.Text.Encoding]::UTF8.GetBytes($Needle) } else { New-Object byte[] 0 }
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            $pos = 0L
            $needleWritten = $false
            while ($pos -lt $SizeBytes) {
                $len = [int][Math]::Min([long]$blockSize, ($SizeBytes - $pos))
                if ($needleBytes.Length -gt 0 -and -not $needleWritten -and $NeedleOffset -ge $pos -and $NeedleOffset -lt ($pos + $len)) {
                    $pre = [int]($NeedleOffset - $pos)
                    if ($pre -gt 0) { $fs.Write($block, 0, $pre) }
                    $fs.Write($needleBytes, 0, $needleBytes.Length)
                    $post = $len - $pre - $needleBytes.Length
                    if ($post -gt 0) { $fs.Write($block, 0, $post) }
                    $needleWritten = $true
                } else {
                    $fs.Write($block, 0, $len)
                }
                $pos += $len
            }
            if ($needleBytes.Length -gt 0 -and -not $needleWritten -and $NeedleOffset -ge 0) {
                $fs.Write($needleBytes, 0, $needleBytes.Length)
            }
        } finally { $fs.Dispose() }
    }
    $escapedLen = [System.Text.Encoding]::UTF8.GetByteCount($escaped)
    $smallMiB = 8
    $bigMiB = if ($env:WINTAGE_TEST_PREFS_MIB) { [int]$env:WINTAGE_TEST_PREFS_MIB } else { 64 }
    $smallPath = Join-Path $needleDir 'large-nomatch-8mib.json'
    $bigPath = Join-Path $needleDir ("large-nomatch-{0}mib.json" -f $bigMiB)
    New-LargePreferencesFile -Path $smallPath -SizeBytes ([long]$smallMiB * 1MB)
    New-LargePreferencesFile -Path $bigPath -SizeBytes ([long]$bigMiB * 1MB)
    $statsSmall = @{}
    $statsBig = @{}
    $smallVerdict = [bool](Test-FileContainsAnyBounded -Path $smallPath -Needles @($escaped, $slashed) -Stats $statsSmall)
    $bigVerdict = [bool](Test-FileContainsAnyBounded -Path $bigPath -Needles @($escaped, $slashed) -Stats $statsBig)
    check ("large no-match: {0} MiB and {1} MiB both report no match" -f $smallMiB, $bigMiB) ((-not $smallVerdict) -and (-not $bigVerdict))
    check ("large no-match: every byte is read but the window stays bounded (totalBytes grows with N: {0} -> {1})" -f $statsSmall.TotalBytesRead, $statsBig.TotalBytesRead) (
        $statsSmall.TotalBytesRead -ge ([long]$smallMiB * 1MB) -and $statsBig.TotalBytesRead -ge ([long]$bigMiB * 1MB) -and
        $statsBig.TotalBytesRead -gt $statsSmall.TotalBytesRead)
    check ("large no-match: the resident window is chunk+overlap and does NOT scale with file size (8MiB window={0} vs {1}MiB window={2})" -f $statsSmall.MaxWindowBytes, $bigMiB, $statsBig.MaxWindowBytes) (
        $statsSmall.MaxWindowBytes -eq $statsBig.MaxWindowBytes -and
        $statsBig.MaxWindowBytes -le ($statsBig.MaxChunkBytes + $statsBig.OverlapBound) -and
        $statsSmall.MaxOverlapBytes -le $statsSmall.OverlapBound -and
        $statsBig.MaxOverlapBytes -le $statsBig.OverlapBound -and
        $statsBig.MaxWindowBytes -lt (1MB))
    # StageRoot NEAR THE END of a large file, and one that STRADDLES a chunk
    # boundary: both must match exactly like a whole-file read.
    $nearEndOffset = ([long]$bigMiB * 1MB) - [long]($escapedLen + 200)
    $nearEndPath = Join-Path $needleDir 'large-nearend.json'
    New-LargePreferencesFile -Path $nearEndPath -SizeBytes ([long]$bigMiB * 1MB) -Needle $escaped -NeedleOffset $nearEndOffset
    $boundaryOffset = 65536L - [long][Math]::Floor($escapedLen / 2)   # split across the first 64 KiB chunk edge
    $boundaryPath = Join-Path $needleDir 'large-boundary.json'
    New-LargePreferencesFile -Path $boundaryPath -SizeBytes ([long]$bigMiB * 1MB) -Needle $escaped -NeedleOffset $boundaryOffset
    $statsNear = @{}
    $statsBound = @{}
    $nearEndFound = [bool](Test-FileContainsAnyBounded -Path $nearEndPath -Needles @($escaped, $slashed) -Stats $statsNear)
    $boundaryFound = [bool](Test-FileContainsAnyBounded -Path $boundaryPath -Needles @($escaped, $slashed) -Stats $statsBound)
    # Whole-file reference (the semantics the bounded search replaces), read once
    # per file rather than once per needle form.
    $nearEndRaw = [System.IO.File]::ReadAllText($nearEndPath)
    $boundaryRaw = [System.IO.File]::ReadAllText($boundaryPath)
    $nearEndRef = $nearEndRaw.Contains($escaped) -or $nearEndRaw.Contains($slashed)
    $boundaryRef = $boundaryRaw.Contains($escaped) -or $boundaryRaw.Contains($slashed)
    check 'large match: a StageRoot near the END of a large file matches (== whole-file reference)' ($nearEndFound -and $nearEndRef)
    check 'large match: a StageRoot crossing a chunk boundary matches (== whole-file reference)' ($boundaryFound -and $boundaryRef)
    check 'large match: the boundary match keeps the bounded window contract' (
        $statsBound.MaxWindowBytes -le ($statsBound.MaxChunkBytes + $statsBound.OverlapBound) -and
        $statsBound.MaxWindowBytes -lt (1MB) -and $statsBound.TotalBytesRead -le ([long]$bigMiB * 1MB + $escapedLen))
    check ("large match: the boundary match is found within the first two chunks (chunks={0})" -f $statsBound.Chunks) ($statsBound.Chunks -le 2)

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

    # ---- 18b: explicit rescan discovers a NEW browser (real walker) ----------
    # SRC-007:R015 guardrail: "explicit Rescan must discover browsers added
    # beneath an unchanged PortableRoot". Warm cache answers A only; after B is
    # created under the SAME root an ordinary refresh still answers A (cache),
    # and only -Rescan re-walks and returns A+B.
    if ($realExe) {
        $addRoot = Join-Path $fixture 'add-portable'
        $addA = New-PortableBrowserAt $addRoot $realExe 'chrome.exe' 'PortableBrowserA'
        $addCache = Join-Path $fixture 'add-appdata'
        $addCold = Get-PortableCandidates -PortableRoot $addRoot -CacheRoot $addCache
        $addWarm = Get-PortableCandidates -PortableRoot $addRoot -CacheRoot $addCache
        check 'rescan: cold discovery returns browser A only' ($addCold.Mode -eq 'walked' -and @($addCold.Candidates).Count -eq 1)
        check 'rescan: warm refresh is cache-served with A only, zero walk' ($addWarm.Mode -eq 'cache' -and @($addWarm.Candidates).Count -eq 1)
        $addB = New-PortableBrowserAt $addRoot $realExe 'msedge.exe' 'PortableBrowserB'
        $stillWarm = Get-PortableCandidates -PortableRoot $addRoot -CacheRoot $addCache
        check 'rescan: an ordinary refresh still returns the cached A only (may not see B yet)' ($stillWarm.Mode -eq 'cache' -and @($stillWarm.Candidates).Count -eq 1)
        $rescannedAdd = Get-PortableCandidates -PortableRoot $addRoot -CacheRoot $addCache -Rescan
        check 'rescan: explicit -Rescan walks and returns A + B' ($rescannedAdd.Mode -eq 'walked' -and @($rescannedAdd.Candidates).Count -eq 2)
        $addPersisted = Read-BrowserDiscoveryFile $addCache
        $addKey = Get-PortableRootKey $addRoot
        check 'rescan: the updated cache holds A + B' (@($addPersisted.portable.$addKey.candidates).Count -eq 2)
        $addNext = Get-PortableCandidates -PortableRoot $addRoot -CacheRoot $addCache
        check 'rescan: the next ordinary refresh is cache-served with A + B, zero walk' ($addNext.Mode -eq 'cache' -and @($addNext.Candidates).Count -eq 2)
    } else {
        skip 'rescan: no Chromium binary for the add-after-cache real-walker fixture'
    }

    # ---- 18c: explicit rescan discovers a NEW browser (injectable decision) ---
    # The decision-level proof, independent of executable ProductName: A is
    # cached; B appears under the same root; only -Rescan surfaces B.
    $decideRoot = Join-Path $fixture 'decide-portable'
    New-Item -ItemType Directory -Force -Path $decideRoot | Out-Null
    $decideCache = Join-Path $fixture 'decide-appdata'
    $script:decideSet = @($candidateA)
    $decideWalker = { param([string]$r) $WalkState.Calls = $WalkState.Calls + 1; return $script:decideSet }
    Reset-WalkCount
    $null = Get-PortableCandidates -PortableRoot $decideRoot -CacheRoot $decideCache -Enumerator $decideWalker
    $candidateB = [pscustomobject]@{ Name = 'Fixture Chromium B'; Exe = (Join-Path $cacheRoot 'fixture-user-data\b.exe'); UserData = (Join-Path $cacheRoot 'fixture-user-data') }
    [System.IO.File]::WriteAllBytes($candidateB.Exe, [byte[]]@())
    $script:decideSet = @($candidateA, $candidateB)
    Reset-WalkCount
    $decideWarm = Get-PortableCandidates -PortableRoot $decideRoot -CacheRoot $decideCache -Enumerator $decideWalker
    check 'rescan(decision): warm refresh is cache-served with the ORIGINAL set and zero walks' ($decideWarm.Mode -eq 'cache' -and $script:WalkState.Calls -eq 0 -and @($decideWarm.Candidates).Count -eq 1)
    Reset-WalkCount
    $decideRescan = Get-PortableCandidates -PortableRoot $decideRoot -CacheRoot $decideCache -Rescan -Enumerator $decideWalker
    check 'rescan(decision): explicit -Rescan discovers the added browser (A + B)' ($decideRescan.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1 -and @($decideRescan.Candidates).Count -eq 2)
    $decidePersisted = Read-BrowserDiscoveryFile $decideCache
    $decideKey = Get-PortableRootKey $decideRoot
    check 'rescan(decision): the updated cache holds A + B' (@($decidePersisted.portable.$decideKey.candidates).Count -eq 2)
    Reset-WalkCount
    $decideAfter = Get-PortableCandidates -PortableRoot $decideRoot -CacheRoot $decideCache -Enumerator $decideWalker
    check 'rescan(decision): the next ordinary refresh is cache-served with A + B, zero walks' ($decideAfter.Mode -eq 'cache' -and $script:WalkState.Calls -eq 0 -and @($decideAfter.Candidates).Count -eq 2)

    # ---- 18d: REPLACE / INVALIDATE a cached executable -----------------------
    # SRC-007:R015 VERIFY: deterministic add/remove/replace. Remove is covered
    # above; here a cached candidate's executable is REPLACED (same path, new
    # bytes) and the cache must not invent stale metadata -- the invalidation
    # forces rediscovery and the cache is rewritten to the replacement.
    $repRoot = Join-Path $fixture 'replace-portable'
    New-Item -ItemType Directory -Force -Path $repRoot | Out-Null
    $repCache = Join-Path $fixture 'replace-appdata'
    $repX = [pscustomobject]@{ Name = 'Fixture Chromium'; Exe = (Join-Path $cacheRoot 'fixture-user-data\rep-x.exe'); UserData = (Join-Path $cacheRoot 'fixture-user-data') }
    [System.IO.File]::WriteAllBytes($repX.Exe, [byte[]]@(1, 2, 3, 4))
    $script:repSet = @($repX)
    $repWalker = { param([string]$r) $WalkState.Calls = $WalkState.Calls + 1; return $script:repSet }
    $null = Get-PortableCandidates -PortableRoot $repRoot -CacheRoot $repCache -Enumerator $repWalker
    $repY = [pscustomobject]@{ Name = 'Fixture Chromium Replaced'; Exe = (Join-Path $cacheRoot 'fixture-user-data\rep-y.exe'); UserData = (Join-Path $cacheRoot 'fixture-user-data') }
    [System.IO.File]::WriteAllBytes($repY.Exe, [byte[]]@(9, 9))
    # Invalidate X (vanished) and expose the replacement Y; rediscovery must
    # return Y, never the stale X.
    Remove-Item -LiteralPath $repX.Exe -Force
    $script:repSet = @($repY)
    Reset-WalkCount
    $repReplaced = Get-PortableCandidates -PortableRoot $repRoot -CacheRoot $repCache -Enumerator $repWalker
    check 'replace: a vanished cached candidate forces rediscovery' ($repReplaced.Mode -eq 'walked' -and $script:WalkState.Calls -eq 1)
    check 'replace: rediscovery returns the replacement, never the stale candidate' (@($repReplaced.Candidates).Count -eq 1 -and $repReplaced.Candidates[0].Exe -ieq $repY.Exe -and @($repReplaced.Candidates | Where-Object { $_.Exe -ieq $repX.Exe }).Count -eq 0)
    $repPersisted = Read-BrowserDiscoveryFile $repCache
    $repKey = Get-PortableRootKey $repRoot
    $repStored = @($repPersisted.portable.$repKey.candidates)
    check 'replace: the cache is rewritten to the replacement (stale metadata does not survive)' ($repStored.Count -eq 1 -and $repStored[0].Exe -ieq $repY.Exe)
    Reset-WalkCount
    $repAfter = Get-PortableCandidates -PortableRoot $repRoot -CacheRoot $repCache -Enumerator $repWalker
    check 'replace: the next refresh is cache-served with the replacement, zero walks' ($repAfter.Mode -eq 'cache' -and $script:WalkState.Calls -eq 0 -and @($repAfter.Candidates).Count -eq 1 -and $repAfter.Candidates[0].Exe -ieq $repY.Exe)

    # ---- 19b: LIVE WinForms pre-ShowDialog smoke (real startup path) ---------
    # SRC-007:R015: "Live WinForms smoke: with a deliberately slow portable
    # discovery source, the form must become usable without waiting for the
    # full recursive scan."
    #
    # This launches the REAL desktop/WintageInstaller.ps1 in a child process
    # against an isolated WINTAGE_APPDATA with a warmed cache and a slow walker
    # armed. The GUI's own PATH-shimmed install.ps1 listing drives the real
    # browser-discovery path, which writes its walker-invocation count to a file
    # the smoke reads the moment the form's Shown event stamps. Requirement:
    # walkerInvocations == 0 before ShowDialog returns.
    $gui = Join-Path $root 'desktop\WintageInstaller.ps1'
    $smokeShim = Join-Path $fixture 'shim'
    New-Item -ItemType Directory -Force -Path $smokeShim | Out-Null
    Write-Text (Join-Path $smokeShim 'powershell.cmd') ("@echo off`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" %*`r`n")
    $smokeRoot = Join-Path $fixture 'smoke-appdata'
    $smokePortable = Join-Path $fixture 'smoke-portable'
    $smokeDeep = Join-Path $smokePortable 'unrelated\deep'
    New-Item -ItemType Directory -Force -Path $smokeDeep | Out-Null
    foreach ($n in 1..80) { Write-Text (Join-Path $smokeDeep ("f$n.bin")) 'noise' }
    Write-Text (Join-Path $smokeRoot 'paths.json') ('{"portable":"' + $smokePortable.Replace('\', '\\') + '"}')
    # Warm the cache directly (the cold path is the RED C control, below).
    $null = Get-PortableCandidates -PortableRoot $smokePortable -CacheRoot $smokeRoot
    $smokeMarker = Join-Path $fixture 'smoke-shown.stamp'
    $smokeWalkFile = Join-Path $fixture 'smoke-walkcount.txt'

    function Invoke-GuiStartupSmoke([int]$WalkSlowMs, [int]$AutoCloseMs) {
        # Runs the real GUI with the given slow-walk setting and returns the
        # measured startup facts. The PATH shim is harmless here (it only
        # forwards), and it makes the child-invocation surface observable.
        $prevPath = $env:PATH; $prevAppData = $env:WINTAGE_APPDATA; $prevSlow = $env:WINTAGE_TEST_WALK_SLOW_MS
        $prevCountFile = $env:WINTAGE_TEST_WALK_COUNT_FILE; $prevAutoclose = $env:WINTAGE_TEST_AUTOCLOSE_MS
        $prevShown = $env:WINTAGE_TEST_FORM_SHOWN_FILE
        if (Test-Path $smokeMarker) { Remove-Item -LiteralPath $smokeMarker -Force }
        if (Test-Path $smokeWalkFile) { Remove-Item -LiteralPath $smokeWalkFile -Force }
        $env:PATH = $smokeShim + ';' + $prevPath
        $env:WINTAGE_APPDATA = $smokeRoot
        $env:WINTAGE_TEST_WALK_COUNT_FILE = $smokeWalkFile
        $env:WINTAGE_TEST_FORM_SHOWN_FILE = $smokeMarker
        $env:WINTAGE_TEST_AUTOCLOSE_MS = "$AutoCloseMs"
        $env:WINTAGE_TEST_WALK_SLOW_MS = "$WalkSlowMs"
        $t0 = [datetime]::UtcNow
        $proc = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gui) -PassThru -WindowStyle Hidden
        $shownAt = $null
        for ($i = 0; $i -lt 1200; $i++) {
            if (Test-Path $smokeMarker) { $shownAt = [datetime]::UtcNow; break }
            if ($proc.HasExited) { break }
            Start-Sleep -Milliseconds 50
        }
        $walks = if (Test-Path $smokeWalkFile) { [int]((Get-Content -LiteralPath $smokeWalkFile -Raw).Trim()) } else { 0 }
        $proc.WaitForExit(180000) | Out-Null
        $env:PATH = $prevPath; $env:WINTAGE_APPDATA = $prevAppData; $env:WINTAGE_TEST_WALK_SLOW_MS = $prevSlow
        $env:WINTAGE_TEST_WALK_COUNT_FILE = $prevCountFile; $env:WINTAGE_TEST_AUTOCLOSE_MS = $prevAutoclose
        $env:WINTAGE_TEST_FORM_SHOWN_FILE = $prevShown
        return [pscustomobject]@{ ShownMs = if ($shownAt) { [int]($shownAt - $t0).TotalMilliseconds } else { -1 }; Walks = $walks; Exited = $proc.HasExited }
    }

    $prevWinEnv = $env:WINTAGE_APPDATA
    $smokeWarm = Invoke-GuiStartupSmoke -WalkSlowMs 6000 -AutoCloseMs 1200
    check 'live smoke: the form reached Shown with the cache warm' ($smokeWarm.ShownMs -ge 0)
    check 'live smoke: walkerInvocations == 0 before the form became usable' ($smokeWarm.Walks -eq 0)
    check 'live smoke: the deliberately slow walker never delayed startup (6s slow walker, but Shown stayed fast)' (($smokeWarm.ShownMs -ge 0) -and ($smokeWarm.ShownMs -lt 10000))

    # RED C: the SAME smoke with a COLD cache. The deliberately slow walker now
    # runs on the startup path and visibly delays the usable window -- proving
    # the smoke fixture can catch the original defect rather than passing blind.
    $coldCacheFile = Get-BrowserCachePath $smokeRoot
    if (Test-Path $coldCacheFile) { Remove-Item -LiteralPath $coldCacheFile -Force }
    $smokeCold = Invoke-GuiStartupSmoke -WalkSlowMs 6000 -AutoCloseMs 1200
    check 'live smoke: the slow walker IS invoked and observed on a cold cache (RED C barrier)' ($smokeCold.Walks -ge 1)
    check 'RED C: the original defect is caught -- the slow walker delays the usable form (>6s slow walker)' ($smokeCold.ShownMs -ge 8000)
    check 'RED C: contrast proven -- the slow walker added a clear delay vs the warm cache' (($smokeCold.ShownMs - $smokeWarm.ShownMs) -ge 3000)
    $env:WINTAGE_APPDATA = $prevWinEnv
    # Re-warm the smoke cache so later references are unaffected.
    $null = Get-PortableCandidates -PortableRoot $smokePortable -CacheRoot $smokeRoot

    # ---- 19c: CACHE / PROFILE RESULT PARITY (browser, profile, TM, theme) ----
    # SRC-007:R015: the warm-cache result must preserve the browser set, the
    # profile set, the Tampermonkey count/state and the ThemeLoaded state -- not
    # merely executable paths. Driven through the REAL install-browsers.ps1
    # listing with a real Chromium binary so every status field is exercised.
    if ($realExe) {
        $parityRoot = Join-Path $fixture 'parity-portable'
        $parityBrowser = New-PortableBrowserAt $parityRoot $realExe 'chrome.exe' 'ParityBrowser'
        $parityProfile = Join-Path $parityBrowser.UserData 'Default'
        # A real profile: Tampermonkey extension present + the staged theme path
        # recorded in Preferences (escaped form, as Chromium writes it).
        New-Item -ItemType Directory -Force -Path (Join-Path $parityProfile 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo') | Out-Null
        $parityStage = Join-Path $fixture 'parity-stage'
        New-Item -ItemType Directory -Force -Path $parityStage | Out-Null
        Write-Text (Join-Path $parityProfile 'Preferences') ('{"theme":"' + $parityStage.Replace('\', '\\') + '"}')
        $parityCache = Join-Path $fixture 'parity-appdata'
        function Get-BrowserListing([string]$cacheRoot) {
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ListJson -StageRoot $parityStage -PortableRoot $parityRoot -CacheRoot $cacheRoot 2>&1 | Out-String).Trim()
            return ($out | ConvertFrom-Json)
        }
        # Use WINTAGE_APPDATA so the tool's cache root is the fixture's.
        $prevParityAppData = $env:WINTAGE_APPDATA
        $env:WINTAGE_APPDATA = $parityCache
        $pRun1 = Get-BrowserListing $parityCache
        $pRun2 = Get-BrowserListing $parityCache
        $env:WINTAGE_APPDATA = $prevParityAppData
        check 'parity: run1 performed the portable walk, run2 served the same result from cache' ($pRun1.PortableDiscovery -eq 'walked' -and $pRun2.PortableDiscovery -eq 'cache')
        check 'parity: browser/profile/Tampermonkey/ThemeLoaded counts are identical across the cache boundary' (
            $pRun1.BrowserCount -eq $pRun2.BrowserCount -and
            $pRun1.ProfileCount -eq $pRun2.ProfileCount -and
            $pRun1.TampermonkeyCount -eq $pRun2.TampermonkeyCount -and
            $pRun1.ThemeLoadedCount -eq $pRun2.ThemeLoadedCount)
        $parityProfiles1 = @($pRun1.Profiles | Sort-Object ProfilePath | ForEach-Object { "{0}|{1}|{2}|{3}" -f $_.Exe, $_.UserData, $_.Profile, ([bool]$_.Tampermonkey) + '/' + ([bool]$_.ThemeLoaded) })
        $parityProfiles2 = @($pRun2.Profiles | Sort-Object ProfilePath | ForEach-Object { "{0}|{1}|{2}|{3}" -f $_.Exe, $_.UserData, $_.Profile, ([bool]$_.Tampermonkey) + '/' + ([bool]$_.ThemeLoaded) })
        check 'parity: the FULL profile records (exe, UserData, profile, TM, theme) are identical, not just paths' (
            $parityProfiles1.Count -eq $parityProfiles2.Count -and (@(Compare-Object $parityProfiles1 $parityProfiles2).Count -eq 0) -and $parityProfiles1.Count -ge 1)
        check 'parity: the staged theme is actually detected as loaded (ThemeLoadedCount >= 1) and Tampermonkey seen' ($pRun2.ThemeLoadedCount -ge 1 -and $pRun2.TampermonkeyCount -ge 1)
    } else {
        skip 'parity: no Chromium binary for the cache/profile result-parity fixture'
    }

    # ---- 20..21: red controls (temporary source mutants only) ----------------
    $mutantRoot = Join-Path $fixture 'mutants'
    New-Item -ItemType Directory -Force -Path $mutantRoot | Out-Null

    # INSTRUMENT CONTROL for the bounded-window gate: a mutant scanner that
    # reads the WHOLE file as one "chunk" (the pre-fix ReadAllText shape). The
    # same -Stats evidence the large-file checks rely on must go RED -- the
    # resident window becomes the file size. Without this, "window stayed
    # bounded" could be a check that cannot fail.
    $mutantChunk = Join-Path $mutantRoot 'chunk-unbounded.ps1'
    $chunkAnchor = 'if ($ChunkBytes -le 0) { $ChunkBytes = $script:BROWSER_PREF_CHUNK }'
    $mutantChunkSrc = $helperSrc.Replace($chunkAnchor, 'if ($ChunkBytes -le 0) { $ChunkBytes = [int][System.IO.FileInfo]::new($Path).Length }')
    $mutantChunkChanged = ($mutantChunkSrc -ne $helperSrc)
    Write-Text $mutantChunk $mutantChunkSrc
    $chunkRed = & powershell -NoProfile -ExecutionPolicy Bypass -Command @"
. '$mutantChunk'
`$stats = @{}
`$null = Test-FileContainsAnyBounded -Path '$bigPath' -Needles @('$escaped') -Stats `$stats
Write-Host ('window=' + `$stats.MaxWindowBytes + ' chunks=' + `$stats.Chunks)
"@
    $chunkRedWindow = 0
    if ($chunkRed -match 'window=(\d+)') { $chunkRedWindow = [long]$Matches[1] }
    check 'INSTRUMENT CONTROL: the unbounded-chunk mutant actually applied' $mutantChunkChanged
    check ("INSTRUMENT CONTROL: the bounded-window gate goes RED on the whole-file mutant (window {0} == file size, >= 1 MiB)" -f $chunkRedWindow) ($chunkRedWindow -ge ([long]$bigMiB * 1MB))
    check 'INSTRUMENT CONTROL: the shipped scanner stays bounded on the same file (contrast)' ($statsBig.MaxWindowBytes -lt 1MB -and $statsBig.MaxWindowBytes -lt $chunkRedWindow)

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
