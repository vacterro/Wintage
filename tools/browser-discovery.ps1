# Portable browser discovery cache + bounded preference scanning (R015 / PERF-004).
#
# The audit measured that a remembered `-PortableRoot` turned every status
# refresh into `Get-ChildItem -Recurse -File` over an arbitrary user-selected
# subtree, and that every discovered profile had its complete `Preferences`
# file read into memory only to run two `.Contains` checks. Both costs were
# paid again on each Load-Targets (startup, after Apply, after Revert).
#
# This module is dot-sourced by tools/install-browsers.ps1 and by the R015
# fixture, so the DISCOVERY DECISION (walk / serve from cache / rescan) is
# separable from the tool's command flow and observable by a test.
#
# Invariants this file owns:
#   * a recursive walk happens only when the cache cannot answer
#     (cold cache, corrupt cache, changed root, invalidated candidate,
#     explicit -Rescan); it is never on the ordinary path;
#   * cached candidates are re-validated cheaply (path existence) before use
#     and a vanished browser is dropped, never invented;
#   * enumeration is streamed (name filter during the walk) with no depth
#     bound, so deep portable layouts stay discoverable;
#   * preference matching is a bounded chunked byte search with overlap, not
#     `ReadAllText`, and keeps the escaped-backslash and slash forms exact;
#   * the cache file is bounded (one portable root, capped profile map) and is
#     written atomically, and a cache read error is never fatal.

$script:BROWSER_DISCOVERY_SCHEMA = 1
$script:BROWSER_EXE_NAMES = @('chrome.exe', 'brave.exe', 'msedge.exe', 'vivaldi.exe', 'opera.exe')
$script:BROWSER_PRODUCT_RE = '(?i)(Chrome|Chromium|Brave|Cent Browser|Vivaldi|Opera|Microsoft Edge)'
$script:BROWSER_CACHE_FILE = 'browser-discovery.json'
$script:BROWSER_PROFILE_CACHE_CAP = 256
$script:BROWSER_PREF_CHUNK = 65536

function Get-BrowserCacheRoot([string]$Explicit) {
    # WINTAGE_APPDATA is the repository's existing isolation switch (install.ps1
    # and the GUI both honour it), so a fixture can own its cache without a
    # production-only test hook.
    if ($Explicit) { return [System.IO.Path]::GetFullPath($Explicit).TrimEnd('\') }
    if ($env:WINTAGE_APPDATA) { return [System.IO.Path]::GetFullPath($env:WINTAGE_APPDATA).TrimEnd('\') }
    return [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Wintage')).TrimEnd('\')
}

function Get-BrowserCachePath([string]$CacheRoot) {
    Join-Path (Get-BrowserCacheRoot $CacheRoot) $script:BROWSER_CACHE_FILE
}

function Get-PortableRootKey([string]$PortableRoot) {
    # NTFS paths are case-insensitive; the key follows the filesystem, not the
    # string the caller happened to type.
    [System.IO.Path]::GetFullPath($PortableRoot).TrimEnd('\').ToLowerInvariant()
}

function Read-BrowserDiscoveryFile([string]$CacheRoot) {
    $path = Get-BrowserCachePath $CacheRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not $raw.Trim()) { return $null }
        $obj = $raw | ConvertFrom-Json
        if ($obj.schema -ne $script:BROWSER_DISCOVERY_SCHEMA) { return $null }
        return $obj
    } catch {
        # A corrupt cache is an absent cache: fail into a walk, never into an
        # error the installer has to explain.
        return $null
    }
}

function Write-BrowserDiscoveryFile([string]$CacheRoot, $Data) {
    $path = Get-BrowserCachePath $CacheRoot
    $dir = Split-Path -Parent $path
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $tmp = "$path.tmp-$([guid]::NewGuid().ToString('N'))"
        [System.IO.File]::WriteAllText($tmp, ($Data | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {
        Write-Warning "browser discovery cache could not be written ($($_.Exception.Message)); the next run will rediscover."
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Test-FileContainsAnyBounded {
    <#
      Bounded-memory equivalent of `[System.IO.File]::ReadAllText($p).Contains($needle)`.

      Reads the file in fixed chunks and searches each window, carrying
      (longest needle - 1) bytes across the boundary so a match that straddles
      a chunk is still found. Returns $true on the first hit; never holds more
      than one chunk plus the overlap in memory.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Needles,
        [int]$ChunkBytes = 0
    )
    $wanted = @()
    $maxLen = 0
    foreach ($needle in @($Needles)) {
        if (-not $needle) { continue }
        $wanted += $needle
        $n = [System.Text.Encoding]::UTF8.GetByteCount($needle)
        if ($n -gt $maxLen) { $maxLen = $n }
    }
    if (-not $wanted.Count) { return $false }
    if ($ChunkBytes -le 0) { $ChunkBytes = $script:BROWSER_PREF_CHUNK }
    if ($ChunkBytes -lt $maxLen) { $ChunkBytes = $maxLen }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $buffer = New-Object byte[] $ChunkBytes
        $tail = New-Object byte[] 0
        while ($true) {
            $read = $stream.Read($buffer, 0, $ChunkBytes)
            if ($read -le 0) { break }
            $window = New-Object byte[] ($tail.Length + $read)
            [Array]::Copy($tail, 0, $window, 0, $tail.Length)
            [Array]::Copy($buffer, 0, $window, $tail.Length, $read)
            # The window is decoded (bounded: one chunk plus the overlap) and
            # matched with the ordinal IndexOf primitive. A byte-at-a-time
            # comparison in managed code was exact but O(window x needle), which
            # is the wrong shape for the startup path this clause exists to make
            # cheap; the needles are ASCII, so a window edge splitting a
            # multi-byte character cannot change any byte they match.
            $text = [System.Text.Encoding]::UTF8.GetString($window)
            foreach ($needle in $wanted) {
                if ($text.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0) { return $true }
            }
            $keep = [Math]::Min(($maxLen - 1), $window.Length)
            $tail = New-Object byte[] $keep
            if ($keep -gt 0) { [Array]::Copy($window, ($window.Length - $keep), $tail, 0, $keep) }
        }
        return $false
    } catch {
        # An unreadable preference file must never invent a loaded theme.
        return $false
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-ProfilePreferenceFingerprint {
    <#
      File identity (length + last-write time) for the preference files a
      profile health answer depends on. A file that appears or changes changes
      the fingerprint, so the cached answer cannot outlive the evidence it was
      derived from. Both files are always represented ('absent' included), so a
      newly created Secure Preferences invalidates too.
    #>
    param([Parameter(Mandatory = $true)][string]$ProfilePath)
    $parts = @()
    foreach ($name in @('Preferences', 'Secure Preferences')) {
        $file = Join-Path $ProfilePath $name
        $info = $null
        try { $info = Get-Item -LiteralPath $file -Force -ErrorAction Stop } catch { $info = $null }
        if ($info -and -not $info.PSIsContainer) {
            $parts += ('{0}:{1}:{2}' -f $name, $info.Length, $info.LastWriteTimeUtc.Ticks)
        } else {
            $parts += ('{0}:absent' -f $name)
        }
    }
    $parts -join '|'
}

function Get-ProfileThemeLoaded {
    <#
      `ThemeLoaded` for one profile: does either preference file mention the
      staged theme path. The bounded byte search replaces the whole-file read;
      both the escaped-backslash and the slash form are matched exactly as
      before. A matching fingerprint serves the cached answer without opening
      the files at all.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ProfilePath,
        [Parameter(Mandatory = $true)][string]$StageRoot,
        [hashtable]$Cache,
        [int]$ChunkBytes = 0
    )
    $fingerprint = Get-ProfilePreferenceFingerprint $ProfilePath
    if ($Cache -and $Cache.ContainsKey($ProfilePath)) {
        $entry = $Cache[$ProfilePath]
        if ($entry -and $entry.fp -eq $fingerprint) { return [bool]$entry.themeLoaded }
    }
    $needles = @($StageRoot.Replace('\', '\\'), $StageRoot.Replace('\', '/'))
    $themeLoaded = $false
    foreach ($name in @('Preferences', 'Secure Preferences')) {
        $file = Join-Path $ProfilePath $name
        if (-not (Test-Path -LiteralPath $file)) { continue }
        if (Test-FileContainsAnyBounded -Path $file -Needles $needles -ChunkBytes $ChunkBytes) { $themeLoaded = $true; break }
    }
    if ($Cache) { $Cache[$ProfilePath] = [pscustomobject]@{ fp = $fingerprint; themeLoaded = $themeLoaded } }
    return $themeLoaded
}

function Get-BrowserPortableCandidates {
    <#
      The production portable walk. Streams executables out of the subtree with
      the name filter applied DURING enumeration (no full-tree list is built)
      and keeps the historical semantics: no depth bound, shortest path first,
      the product name must look like a Chromium browser, and the UserData
      directory must carry Local State or a Default/Profile * child. It is the
      default enumerator, so production and the R015 fixture drive the same
      decision path.
    #>
    param([Parameter(Mandatory = $true)][string]$PortableRoot)
    $matches = @(Get-ChildItem -LiteralPath $PortableRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $script:BROWSER_EXE_NAMES -contains $_.Name } |
        Sort-Object { $_.FullName.Length })
    $candidates = @()
    foreach ($file in $matches) {
        try { $product = $file.VersionInfo.ProductName } catch { $product = '' }
        if ($product -notmatch $script:BROWSER_PRODUCT_RE) { continue }
        $dir = $file.Directory.FullName
        $parent = Split-Path $dir -Parent
        $userDataCandidates = @(
            (Join-Path $dir 'User Data'), (Join-Path $dir 'data'),
            (Join-Path $parent 'User Data'), (Join-Path $parent 'data'),
            (Join-Path $parent 'profile\data')
        )
        if ($product -match '(?i)Opera') {
            $userDataCandidates = @((Join-Path $env:APPDATA 'Opera Software\Opera Stable')) + $userDataCandidates
        }
        $data = $userDataCandidates | Where-Object {
            (Test-Path -LiteralPath $_) -and
            ((Test-Path -LiteralPath (Join-Path $_ 'Local State')) -or
             @(Get-ChildItem -LiteralPath $_ -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }).Count)
        } | Select-Object -First 1
        if ($data) {
            $candidates += [pscustomobject]@{              Name = $product
              Exe = [System.IO.Path]::GetFullPath($file.FullName)
              UserData = [System.IO.Path]::GetFullPath($data).TrimEnd('\')
            }
        }
    }
    $candidates
}

$script:BROWSER_DEFAULT_ENUMERATOR = { param([string]$PortableRoot) Get-BrowserPortableCandidates -PortableRoot $PortableRoot }

function Read-PortableRootEntry($Data, [string]$PortableRoot) {
    if (-not $Data -or -not $Data.portable) { return $null }
    $key = Get-PortableRootKey $PortableRoot
    $entry = $Data.portable.$key
    if (-not $entry) { return $null }
    return $entry
}

function Test-PortableCandidateValid($Candidate) {
    # Cheap validation only: the audit's guardrail is that a stale cache must
    # never invent a browser that no longer exists, and Test-Path answers that
    # without re-reading version metadata or the subtree.
    if (-not $Candidate) { return $false }
    foreach ($field in @('Exe', 'UserData')) {
        $value = [string]$Candidate.$field
        if (-not $value) { return $false }
        if (-not (Test-Path -LiteralPath $value)) { return $false }
    }
    return $true
}

function Get-PortableCandidates {
    <#
      The discovery decision, in one place.

      Returns @{ Candidates = @(...); Mode = 'none'|'cache'|'walked'; Walks = n }.

      `-Enumerator` is the walker: it receives the PortableRoot and returns
      candidate objects (Name/Exe/UserData), already product-validated and
      ordered. It defaults to the production streaming walk; the fixture passes
      its own so filesystem enumeration is countable without a test-only branch
      in the production tool. It is invoked ONLY when the cache cannot answer.
    #>
    param(
        [string]$PortableRoot,
        [string]$CacheRoot,
        [switch]$Rescan,
        [scriptblock]$Enumerator
    )
    $result = @{ Candidates = @(); Mode = 'none'; Walks = 0 }
    if (-not $PortableRoot -or -not (Test-Path -LiteralPath $PortableRoot)) { return $result }

    if (-not $Enumerator) { $Enumerator = $script:BROWSER_DEFAULT_ENUMERATOR }
    $Data = Read-BrowserDiscoveryFile $CacheRoot
    $key = Get-PortableRootKey $PortableRoot

    if (-not $Rescan -and $Data) {
        $entry = Read-PortableRootEntry $Data $PortableRoot
        if ($entry -and $entry.candidates -isnot [string]) {
            $served = @()
            $dropped = 0
            foreach ($candidate in @($entry.candidates)) {
                if (Test-PortableCandidateValid $candidate) { $served += $candidate } else { $dropped++ }
            }
            if (-not $dropped) {
                $result.Candidates = @($served)
                $result.Mode = 'cache'
                return $result
            }
            # A cached candidate became invalid: the cheap answer is no longer
            # trustworthy, so fall through to a real walk.
        }
    }

    # An enumerator may hand back a collection or a bare candidate; flatten one
    # level so an empty result stays empty instead of persisting as `[[]]`.
    $walked = @()
    if ($Enumerator) {
        foreach ($item in @(& $Enumerator $PortableRoot)) {
            if ($null -eq $item) { continue }
            if ($item -is [System.Array]) { $walked += @($item) } else { $walked += $item }
        }
    }
    $result.Walks = 1
    $result.Candidates = @($walked)
    $result.Mode = 'walked'
    # The walk's result is persisted whatever the entry was: a cold cache that
    # discovered nothing is still an answer, and re-walking it every refresh is
    # precisely the cost this clause removes.
    if (-not $Data) {
        $Data = [pscustomobject]@{ schema = $script:BROWSER_DISCOVERY_SCHEMA; portable = [ordered]@{}; profiles = [ordered]@{} }
    }
    $portable = [ordered]@{}
    $portable[$key] = [ordered]@{ root = $PortableRoot; found = ($walked.Count -gt 0); candidates = @($walked) }
    $Data.portable = $portable
    Write-BrowserDiscoveryFile $CacheRoot $Data
    return $result
}

function Merge-ProfileThemeCache {
    <#
      Writes the profile answers this run computed back into the cache, keeping
      entries whose profile still exists (so a Revert/Apply refresh stays cheap)
      and capping the map so a machine with churning profile paths cannot grow
      the file without limit.
    #>
    param(
        [string]$CacheRoot,
        [hashtable]$Cache
    )
    $root = Read-BrowserDiscoveryFile $CacheRoot
    if (-not $root) {
        $root = [pscustomobject]@{ schema = $script:BROWSER_DISCOVERY_SCHEMA; portable = [ordered]@{}; profiles = [ordered]@{} }
    }
    $merged = [ordered]@{}
    foreach ($path in @($Cache.Keys | Sort-Object)) {
        $merged[$path] = $Cache[$path]
    }
    if ($root.profiles) {
        foreach ($property in $root.profiles.PSObject.Properties) {
            if ($merged.Contains($property.Name)) { continue }
            if (-not (Test-Path -LiteralPath $property.Name)) { continue }
            $merged[$property.Name] = $property.Value
        }
    }
    $trimmed = [ordered]@{}
    $names = @($merged.Keys)
    if ($names.Count -gt $script:BROWSER_PROFILE_CACHE_CAP) {
        $names = $names[($names.Count - $script:BROWSER_PROFILE_CACHE_CAP)..($names.Count - 1)]
    }
    foreach ($name in $names) { $trimmed[$name] = $merged[$name] }

    # No-change runs must not rewrite the cache: a status refresh that learned
    # nothing new is exactly the case this clause exists to make free.
    $changed = $true
    if ($root.profiles) {
        $before = @($root.profiles.PSObject.Properties)
        if ($before.Count -eq $trimmed.Keys.Count) {
            $changed = $false
            foreach ($property in $before) {
                if (-not $trimmed.Contains($property.Name)) { $changed = $true; break }
                $existing = $property.Value
                $fresh = $trimmed[$property.Name]
                if ($existing.fp -ne $fresh.fp -or [bool]$existing.themeLoaded -ne [bool]$fresh.themeLoaded) { $changed = $true; break }
            }
        }
    }
    if (-not $changed) { return }
    $root.profiles = $trimmed
    Write-BrowserDiscoveryFile $CacheRoot $root
}
