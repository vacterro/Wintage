# Shared helpers for install.ps1 (T-169 split). Functions here run in the calling
# script's scope, so they see install.ps1's variables and parameters at call time.
# Dot-sourced by install.ps1 before the target tables are built, because those call
# Get-ClaudeResources/Get-CodeNomadResources at definition time.

# Keep only the newest timestamped backup dirs. Every apply that replaces an
# existing install adds one, and nothing ever removed them (T-160). Fixed-name
# files (conhost-settings.json, windows-dwm-settings.json) are single revert
# sources and are deliberately NOT pruned.
function Prune-Backups([int]$keep = 8) {
    if ($WhatIfPreference) { return }
    $backupDir = Join-Path $here 'backup'
    if (-not (Test-Path $backupDir)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $backupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
        Sort-Object Name -Descending)
    if ($dirs.Count -le $keep) { return }
    foreach ($old in $dirs[$keep..($dirs.Count - 1)]) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force
        Say "Pruned old backup: $($old.Name)" 'DarkGray'
    }
}

function Say($msg, $colour = 'Gray') { Write-Host $msg -ForegroundColor $colour }

function Read-Utf8([string]$path) { [System.IO.File]::ReadAllText($path, $script:Utf8NoBom) }

function Write-Utf8([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text, $script:Utf8NoBom) }

function Write-Utf8BomLines([string]$path, $lines) { [System.IO.File]::WriteAllLines($path, [string[]]$lines, $script:Utf8WithBom) }

# W2-004 (SRC-005:R008): atomic recovery-file writer. Recovery artifacts and
# their provenance are themselves part of the rollback authority, so a crash
# mid-write must never leave a partial authoritative file on its final name.
# The temp is a same-directory sibling (same volume -> rename is atomic), the
# bytes are fully flushed before the rename, and the temp is always cleaned up
# even when validation or the rename fails. A unique temp name per writer keeps
# concurrent runs from colliding (same rule as Write-Manifest, T-189).
function Write-Utf8Atomic([string]$path, [string]$text, [switch]$ValidateJson) {
    $parent = Split-Path $path -Parent
    if (-not $parent -or -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tmp = $path + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllText($tmp, $text, $script:Utf8NoBom)
        if ($ValidateJson) { $null = [System.IO.File]::ReadAllText($tmp, $script:Utf8NoBom) | ConvertFrom-Json }
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# Atomic copy of a recovery source into its final authoritative path. The
# destination is only replaced once the temp sibling holds the COMPLETE source
# bytes (validated by length), so a crash before the rename keeps the prior
# authoritative backup intact.
function Copy-FileAtomic([string]$source, [string]$dest) {
    if (-not (Test-Path -LiteralPath $source)) { throw "Copy-FileAtomic: source missing: $source" }
    $parent = Split-Path $dest -Parent
    if (-not $parent -or -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tmp = $dest + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
    try {
        Copy-Item -LiteralPath $source -Destination $tmp -Force
        if ((Get-Item -LiteralPath $tmp).Length -ne (Get-Item -LiteralPath $source).Length) {
            throw "Copy-FileAtomic: temp copy is incomplete ($tmp) - refusing to promote it to the authoritative path."
        }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# Every palette token read used to inline the same (Read-Utf8 X | ConvertFrom-Json).tokens
# chain; one helper (T-143).
function Get-PaletteTokens([string]$jsonPath) { (Read-Utf8 $jsonPath | ConvertFrom-Json).tokens }

# Known paths.json keys: the source-tree targets whose folders the GUI can remember.
$script:PATHS_KEYS = @('saipenview', 'smartvac', 'wildrift', 'codenomad', 'workbuddy', 'portable')

function Read-PathsJson {
    if (-not (Test-Path $PathsPath)) { return @{} }
    try {
        $json = (Read-Utf8 $PathsPath).Trim()
        if (-not $json) { return @{} }
        $obj = $json | ConvertFrom-Json
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            # T-191 P2#19: schema-validate the remembered paths. A key outside the
            # known target set or a non-string value is garbage a later
            # Join-Path would throw on - it is dropped here, never trusted.
            if ($prop.Name -notin $script:PATHS_KEYS) { continue }
            if ($prop.Value -isnot [string] -or -not $prop.Value) { continue }
            $ht[$prop.Name] = $prop.Value
        }
        return $ht
    } catch {
        Write-Warning "could not read ${PathsPath}: $($_.Exception.Message) -- remembered paths ignored"
        return @{}
    }
}

# T-192 P1#20: semantic manifest validation. JSON syntax is NOT the contract: a
# top-level array, a scalar, a non-object entry, a wrongly-typed palette/path/
# version field, or a non-array/duplicate-path `items` set must be rejected just
# like corrupt JSON. Unknown target keys are PRESERVED (never destroyed) - they
# are reported, not dropped. Returns an error string array (empty = valid).
function Test-ManifestSchema($m) {
    $errors = @()
    if ($null -eq $m) { return @('manifest is null') }
    if ($m -is [System.Array] -or $m -is [string] -or $m -is [int] -or $m -is [bool]) {
        return @('top-level manifest is not an object')
    }
    if ($m -isnot [System.Collections.IDictionary] -and $m -isnot [PSCustomObject]) {
        return @('top-level manifest is not an object')
    }
    # A Hashtable exposes Count/Keys/Values/etc. as adapted PSProperties - those
    # are NOT manifest entries. Enumerate the real keys explicitly.
    $entryNames = if ($m -is [System.Collections.IDictionary]) { @($m.Keys) } else { @($m.PSObject.Properties.Name) }
    foreach ($key in $entryNames) {
        $e = $m.$key
        if ($e -isnot [PSCustomObject] -and $e -isnot [System.Collections.IDictionary]) {
            $errors += "${key}: entry is not an object"
            continue
        }
        foreach ($field in @('palette', 'path', 'appVersion', 'payloadVersion', 'applied')) {
            if ($null -ne $e.$field -and $e.$field -isnot [string]) { $errors += "${key}.${field}: not a string" }
        }
        if ($null -ne $e.items) {
            if ($e.items -isnot [System.Array] -and $e.items -isnot [System.Collections.IList]) {
                $errors += "${key}.items: not an array"
            } else {
                $seen = @{}
                foreach ($item in $e.items) {
                    if ($item -isnot [PSCustomObject] -and $item -isnot [System.Collections.IDictionary]) {
                        $errors += "${key}.items: item is not an object"
                    } elseif ($null -eq $item.path -or $item.path -isnot [string] -or -not ([string]$item.path).Trim()) {
                        $errors += "${key}.items: item has no nonempty path"
                    } else {
                        try { $canon = [IO.Path]::GetFullPath([string]$item.path).TrimEnd('\').ToLowerInvariant() } catch { $canon = ([string]$item.path).TrimEnd('\').ToLowerInvariant() }
                        if ($seen.ContainsKey($canon)) { $errors += "${key}.items: duplicate canonical path $canon" }
                        $seen[$canon] = $true
                    }
                }
            }
        }
    }
    return $errors
}

# PowerShell 6+ silently retypes any JSON string that LOOKS like a timestamp into
# [datetime], so the `applied` field this project writes as ISO-8601 text comes back
# as a DateTime object there and as a String on Windows PowerShell 5.1. The schema
# then rejected the installer's own manifest on pwsh 7 and EVERY target failed with
# "applied: not a string" before doing any work (T-199). Normalising on read keeps
# one type contract for every host: the `-DateKind` switch that would also fix it
# does not exist on 5.1, which is still the interpreter the GUI and the logon task
# spawn, so it cannot be the fix.
function ConvertTo-ManifestJsonStrings($obj) {
    if ($null -eq $obj) { return $obj }
    if ($obj -isnot [PSCustomObject]) { return $obj }
    foreach ($entry in $obj.PSObject.Properties) {
        $e = $entry.Value
        if ($e -isnot [PSCustomObject]) { continue }
        foreach ($field in @('palette', 'path', 'appVersion', 'payloadVersion', 'applied')) {
            $v = $e.$field
            if ($v -is [datetime]) {
                $e.$field = $v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            } elseif ($v -is [System.DateTimeOffset]) {
                $e.$field = $v.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
        if ($null -ne $e.items -and ($e.items -is [System.Array] -or $e.items -is [System.Collections.IList])) {
            foreach ($item in $e.items) {
                if ($item -isnot [PSCustomObject]) { continue }
                foreach ($field in @('path', 'applied')) {
                    $v = $item.$field
                    if ($v -is [datetime]) {
                        $item.$field = $v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    } elseif ($v -is [System.DateTimeOffset]) {
                        $item.$field = $v.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    }
                }
            }
        }
    }
    return $obj
}

function Read-Manifest {
    # Missing or empty manifest = "nothing installed", a normal state. A file that
    # EXISTS and does not parse is a DISTINCT corrupt state (T-187): the mutation
    # paths must refuse to work on it rather than overwrite every target's history
    # with `{}`, so this throws instead of silently returning empty. Callers that
    # only report (Status, listing) catch and say what is wrong; callers that would
    # write (Set/Remove-ManifestEntry) let the throw abort before any mutation.
    # T-192 P1#20: syntax-valid but schema-invalid content (top-level array, wrong
    # types, non-array items) is treated the same as corrupt - never mutated over.
    if (-not (Test-Path $ManifestPath)) { return @{} }
    $json = (Read-Utf8 $ManifestPath).Trim()
    if (-not $json) { return @{} }
    $obj = $json | ConvertFrom-Json
    $obj = ConvertTo-ManifestJsonStrings $obj
    $schemaErrs = Test-ManifestSchema $obj
    if ($schemaErrs.Count) { throw "manifest schema invalid: $($schemaErrs -join '; ')" }
    $ht = @{}
    foreach ($prop in $obj.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
    return $ht
}

function Write-Manifest($manifest) {
    if ($WhatIfPreference) { return }
    # Refuse to write a schema-invalid manifest BEFORE touching the file.
    $schemaErrs = Test-ManifestSchema $manifest
    if ($schemaErrs.Count) { throw "refusing to write a schema-invalid manifest: $($schemaErrs -join '; ')" }
    New-Item -ItemType Directory -Force -Path $WintageAppData | Out-Null
    $content = (($manifest | ConvertTo-Json -Depth 5) + "`n")
    # Atomic replace with a UNIQUE temp name per writer (T-189): a fixed
    # installed.json.tmp would let two writers collide on the temp path itself.
    # The temp is always cleaned up, even when validation or the rename fails
    # (T-190): a failed write leaves the OLD manifest intact and no tmp garbage.
    $tmp = $ManifestPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        Write-Utf8 $tmp $content
        $null = Read-Utf8 $tmp | ConvertFrom-Json
        # Test seam: exercise the replace-failure cleanup path.
        if ($env:WINTAGE_TEST_FAIL_MANIFEST_MOVE) { throw 'simulated manifest replace failure (WINTAGE_TEST_FAIL_MANIFEST_MOVE)' }
        Move-Item $tmp $ManifestPath -Force
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# Serialize the FULL read-modify-write of the manifest across processes (T-189).
# The atomic rename protects the FILE, not the read->mutate->write cycle: two
# independent writers (GUI + CLI + logon task) can read the same old state and
# overwrite each other's entry. A named mutex scoped to the app-data root covers
# exactly the transaction. The mutex is abandoned (auto-released) if a writer
# crashes mid-write.
function Enter-ManifestLock {
    $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($WintageAppData))).Replace('-', '').Substring(0, 20)
    $mutex = New-Object System.Threading.Mutex($false, "Local\Wintage-Manifest-$hash")
    $got = $false
    try {
        # W2-001: WaitOne returns $false on timeout and does NOT throw. The
        # discarded-result pattern below treated a real 15s timeout as
        # acquisition and proceeded WITHOUT ownership - two manifest writers
        # could then lose each other's entries exactly when the lock should
        # have failed closed. Assign the actual Boolean.
        $got = $mutex.WaitOne(15000)
    } catch [System.Threading.AbandonedMutexException] {
        # AbandonedMutexException means WE now own the mutex whose previous owner
        # died mid-write. That is acquisition, not a timeout (T-190): proceed, but
        # Read-Manifest below still fails closed if the dead writer left corrupt
        # JSON - the lock serializes writers, it never excuses bad state.
        $got = $true
    } catch {
        $got = $false
    }
    if (-not $got) {
        try { $mutex.Dispose() } catch { }
        throw 'could not acquire the manifest lock within 15s - another writer is stuck; retry.'
    }
    return $mutex
}

function Exit-ManifestLock($mutex) {
    if (-not $mutex) { return }
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}

# Named PER-TARGET mutation lock (T-191): two processes applying the same target
# concurrently must serialize DISCOVER..COMMIT, not just the manifest write. The
# lock name is derived from the app-data root + the target name (ASCII-safe hash
# hex), so different targets on the same machine run concurrently while the same
# target serializes. Lock ORDER is always TARGET -> MANIFEST (Set-ManifestEntry
# acquires the manifest lock inside), never the reverse.
function Enter-TargetLock([string]$target) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $base = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($WintageAppData))).Replace('-', '').Substring(0, 16)
    $tHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($target))).Replace('-', '').Substring(0, 16)
    $mutex = New-Object System.Threading.Mutex($false, "Local\Wintage-Target-$base-$tHash")
    $got = $false
    try {
        # W2-001: same fail-closed contract as Enter-ManifestLock - a real
        # WaitOne timeout returns $false and must NOT be treated as ownership.
        $got = $mutex.WaitOne(60000)
    } catch [System.Threading.AbandonedMutexException] {
        # Ownership is acquired; the previous owner died mid-operation. Proceed,
        # but the caller's own preflight/validation still fails closed on bad state.
        $got = $true
    } catch {
        $got = $false
    }
    if (-not $got) {
        try { $mutex.Dispose() } catch { }
        throw "could not acquire the $target mutation lock within 60s - another operation is stuck; retry."
    }
    return $mutex
}

function Exit-TargetLock($mutex) {
    if (-not $mutex) { return }
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}

function Set-ManifestEntry($target, $palette, $resolvedPath, $appVersion, $payloadVersion) {
    $lock = Enter-ManifestLock
    try {
        $m = Read-Manifest
        $m[$target] = @{
            palette       = $palette
            path          = $resolvedPath
            appVersion    = $appVersion
            payloadVersion = $payloadVersion
            applied       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        Write-Manifest $m
    } finally { Exit-ManifestLock $lock }
}

function Remove-ManifestEntry($target) {
    $lock = Enter-ManifestLock
    try {
        $m = Read-Manifest
        if ($m.ContainsKey($target)) {
            $m.Remove($target)
            Write-Manifest $m
        }
    } finally { Exit-ManifestLock $lock }
}

# Multi-item ownership (T-190): targets that install into MANY locations (e.g.
# every Obsidian vault, every Windows Terminal settings.json) record the exact
# owned SET as `items: [{ path }]`, keeping scalar `path` = first item for
# backward compatibility. Revert and health walk the RECORDED set, never a
# re-discovery, so an install whose items later disappear still has its ledger.
function Set-ManifestEntryMulti($target, $palette, [string[]]$paths, $appVersion, $payloadVersion) {
    $lock = Enter-ManifestLock
    try {
        $m = Read-Manifest
        $m[$target] = @{
            palette       = $palette
            path          = if ($paths.Count) { $paths[0] } else { '' }
            items         = @($paths | ForEach-Object { @{ path = $_ } })
            appVersion    = $appVersion
            payloadVersion = $payloadVersion
            applied       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        Write-Manifest $m
    } finally { Exit-ManifestLock $lock }
}

function Get-ManifestItems($entry) {
    if (-not $entry) { return @() }
    if ($entry.items) { return @($entry.items | ForEach-Object { $_.path }) }
    if ($entry.path) { return @($entry.path) }
    return @()
}

# Semver comparison for the payload/version manifest check. String comparison
# reports 1.9.0 as newer than 1.26.3, so a repo that bumped 1.9 -> 1.26 was
# silently "up to date" and never re-applied (T-187). A value either side cannot
# parse is treated as needing reapply -- an unknown version is never "current".
function Test-PayloadUpToDate([string]$recorded, [string]$current) {
    $rv = $null; $cv = $null
    if (-not [version]::TryParse($recorded, [ref]$rv)) { return $false }
    if (-not [version]::TryParse($current, [ref]$cv)) { return $false }
    return $rv -ge $cv
}

# W2-001: recovery-file provenance. Every persistent recovery file written by
# this installer is stamped with an INSTALL EPOCH — a machine-local, first-run
# identity. A recovery file stamped by a different install (a foreign epoch, a
# copied folder, a stale parallel baseline) is never adopted to rewrite the
# user's live state: presence in a Wintage-looking path is not ownership.
#
# CORE-008: the epoch is the foundation. Silently inventing a new GUID when the
# existing file is corrupt (parse failure, missing/empty id, wrong shape)
# rotates the install identity and disconnects every provenance-stamped
# recovery file from the install that wrote it. Assert-RecoveryProvenance
# would then reject its own files as foreign, locking the user out of every
# recovery. The contract is therefore fail-closed on corruption: the corrupt
# bytes are preserved exactly, no rotation, and the caller sees an error. A
# genuinely absent file is still created exactly once and remains stable.
function Get-InstallEpoch {
    $epochFile = Join-Path $WintageAppData 'install-epoch.json'
    New-Item -ItemType Directory -Force -Path $WintageAppData | Out-Null
    # W2-003: first creation must be a race with exactly one winner. The old
    # absent-check + private GUID + forced rename let two concurrent processes
    # each observe "absent", each write a valid file, and each return its OWN
    # id -- the loser then stamped recovery provenance with an identity the
    # persisted file never carried, and Assert-RecoveryProvenance later
    # rejected Wintage's own backup as foreign. The fix is a real OS lock on a
    # dedicated lock file held across the whole absent-check + create + re-read
    # sequence: every loser re-reads the winner and returns THAT id. The lock
    # is acquired with a retry so a crashed holder (whose handle the OS has
    # already released) cannot wedge the epoch forever, and it is always
    # released in the finally below.
    #
    # Lock ordering: nothing may acquire a target lock and then call this
    # while another path holds the epoch lock and wants a target lock. Every
    # caller reaches Get-InstallEpoch either outside any target lock or while
    # holding only that one target lock and acquiring the epoch lock alone,
    # so no inverse acquisition path exists.
    $lockPath = Join-Path $WintageAppData 'install-epoch.lock'
    $lockStream = $null
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            break
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (10 + (Get-Random -Maximum 40))
        }
    }
    if ($null -eq $lockStream) { throw "could not acquire the install-epoch lock at $lockPath after 100 attempts." }
    try {
        if (Test-Path $epochFile) {
            $raw = Read-Utf8 $epochFile
            try {
                $parsed = $raw | ConvertFrom-Json
            } catch {
                throw "install epoch at $epochFile is corrupt (cannot parse JSON) -- refusing to rotate the install identity because every recovery file on this machine is stamped with it. Preserve the original bytes or delete the file by hand after a backup."
            }
            # Tolerant of an id that arrives as any single scalar (string/number/guid);
            # strict on shape -- a non-object root, a missing id, or an empty id is
            # corruption, not "no identity".
            if ($null -eq $parsed -or $parsed -is [System.Array] -or $parsed -is [string] -or $parsed -is [int] -or $parsed -is [bool]) {
                throw "install epoch at $epochFile is not a JSON object -- refusing to rotate the install identity. Preserve the original bytes or delete the file by hand after a backup."
            }
            if ($parsed -isnot [System.Collections.IDictionary] -and $parsed -isnot [PSCustomObject]) {
                throw "install epoch at $epochFile has an unrecognised shape -- refusing to rotate the install identity. Preserve the original bytes or delete the file by hand after a backup."
            }
            $id = $parsed.id
            if ($null -eq $id -or ($id -isnot [string]) -or -not $id.Trim()) {
                throw "install epoch at $epochFile has no usable id field -- refusing to rotate the install identity. Preserve the original bytes or delete the file by hand after a backup."
            }
            return $id.ToString()
        }
        $id = [guid]::NewGuid().ToString('N')
        # Write atomically: same-directory temp + rename, so a crash between the
        # Write-Utf8 and the rename can never leave a half-written epoch on disk
        # that the next call would read as corrupt.
        $tmp = "$epochFile.tmp-$([guid]::NewGuid().ToString('N'))"
        Write-Utf8 $tmp (@{ id = $id; firstSeen = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json)
        Move-Item -LiteralPath $tmp -Destination $epochFile -Force
        # Clean abandoned creation temps from crashed writers (deterministic:
        # anything matching the creation pattern that is not the file itself).
        Get-ChildItem -LiteralPath $WintageAppData -Filter 'install-epoch.json.tmp-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ($tmp + '*') } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        return $id
    } finally {
        $lockStream.Dispose()
    }
}

# Stamp a recovery source with its owning install epoch. Written at the same
# moment the recovery file itself becomes authoritative (after its temp rename).
# W2-004: the stamp is itself rollback authority, so it is written ATOMICALLY
# and validated as JSON before the rename -- a corrupt provenance sidecar can
# never reach its final name.
function Write-RecoveryProvenance([string]$sourcePath, [string]$target) {
    Write-Utf8Atomic ($sourcePath + '.provenance.json') (@{
        owner = 'wintage'
        target = $target
        epoch = Get-InstallEpoch
        created = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json) -ValidateJson
}

# Shared foreign-provenance gate (W2-001): returns $true when the recovery
# file passes provenance (or predates it - installs before this contract have no
# stamp and remain accepted, or every pre-existing install would lose its undo),
# and THROWS when the stamp names another install. The recovery file's own
# existence is the caller's concern.
function Assert-RecoveryProvenance([string]$sourcePath, [string]$target, [string]$label) {
    $provPath = $sourcePath + '.provenance.json'
    if (-not (Test-Path $provPath)) { return $true }
    # A corrupt/unreadable provenance file also throws here, which IS the
    # fail-closed behaviour: unverifiable ownership is never consumed.
    $p = Read-Utf8 $provPath | ConvertFrom-Json
    $epochOk = $null -ne $p.epoch -and $p.epoch.ToString() -eq (Get-InstallEpoch)
    if (-not ($p.owner -eq 'wintage' -and $p.target -eq $target -and $epochOk)) {
        throw "$label : the recovery file $sourcePath carries foreign provenance (owner=$($p.owner) target=$($p.target) epoch=$($p.epoch)) - refusing to adopt recovery from another install. The manifest entry and recovery files are kept; fix the backup or remove the entry by hand."
    }
    return $true
}

# Revert-with-recovery contract (T-189 + W2-001/W2-002): when the manifest says
# a target was installed but the restore source is gone, that is a FAIL, not a
# happy "nothing to revert" — the user is left with half a theme and no undo.
# Only a target with NO recovery state (never installed by us) is a legitimate
# NOOP. A recovery file that EXISTS but carries foreign provenance (a stamp from
# a different install epoch, or a non-wintage owner) is adopted NEITHER: it is
# kept untouched and the revert fails closed. Returns $true = proceed with
# recovery, $false = no-op (caller must stop), throws = fail closed.
function Assert-RevertSource([string]$key, [string]$sourcePath, [string]$label) {
    if (Test-Path $sourcePath) {
        Assert-RecoveryProvenance $sourcePath $key $label | Out-Null
        return $true
    }
    $m = Read-Manifest
    if ($m.ContainsKey($key)) {
        throw "$label : manifest says $key is installed but the restore source is missing ($sourcePath) - cannot restore. The manifest entry is kept as recovery evidence; fix the backup or remove the entry by hand."
    }
    Say "$label : nothing to revert (no Wintage recovery state)." 'DarkYellow'
    return $false
}

function Get-PayloadVersion {
    $raw = (Read-Utf8 (Join-Path $root 'wintage.user.js')) -split "`n" |
        Where-Object { $_ -match '// @version\s+(\S+)' } |
        Select-Object -First 1
    if ($raw -match '// @version\s+(\S+)') { return $matches[1] }
    return 'unknown'
}

function Register-WintageLogonTask {
    if ($WhatIfPreference) {
        Say "Would register logon task: '$TASK_NAME'" 'Cyan'
        return
    }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Reapply -Quiet"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Say "Registered logon task: '$TASK_NAME' -- install.ps1 -Reapply -Quiet runs at every logon." 'Green'
}

function Unregister-WintageLogonTask {
    if (-not (Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue)) {
        Say "Logon task '$TASK_NAME' not found -- nothing to remove." 'DarkGray'
        return
    }
    if ($WhatIfPreference) {
        Say "Would unregister logon task: '$TASK_NAME'" 'Cyan'
        return
    }
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
    Say "Unregistered logon task: '$TASK_NAME'." 'Green'
}

function Convert-HexToBgr([string]$hex) {
    $hex = $hex.Replace('#', '')
    if ($hex.Length -eq 8) { $hex = $hex.Substring(0, 6) }
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    ($b -shl 16) -bor ($g -shl 8) -bor $r
}

# Electron applications. These are themed by dropping a resources/app/ folder that
# Electron loads INSTEAD of app.asar, which then injects the stylesheet and loads
# the original asar untouched. Nothing of the app is rewritten, and -Revert deletes
# the folder. The catch, stated plainly rather than glossed: an app update replaces
# its program folder, so the shim goes with it and the installer has to be re-run.
# An app is "present" if its archive is at EITHER location: resources/app.asar for a
# clean install, or resources/app/app.asar once the shim has moved it. Checking only
# the first made an already-themed app report itself as not installed, which then
# refused to revert -- the one situation where you most need the command to work.
function Test-ElectronApp($resources) {
    if (-not $resources) { return $false }
    (Test-Path (Join-Path $resources 'app.asar')) -or (Test-Path (Join-Path $resources 'app/app.asar'))
}

# PERF-005 (T-240): unchanged-file fuse-verdict cache for the install.ps1
# listing. Keyed on exe identity (path + size + mtimeUtc ticks); ANY mismatch
# or ANY doubt (missing/corrupt cache file, unreadable exe) returns $null and
# the caller scans fresh. Fail-closed: only a past SCAN result is ever cached,
# an unscanned exe is never reported safe from here.
#
# ponytail: best-effort write, no paths.lock. A lost update or torn write only
# costs one rescan (the next read treats a corrupt file as a miss); correctness
# never depends on the cache. Add locking when concurrent listings contend.
function Get-CachedFuseBlocked([string]$exePath) {
    try {
        $item = Get-Item -LiteralPath $exePath -ErrorAction Stop
        $cacheFile = Join-Path $WintageAppData 'fuse-cache.json'
        if (-not (Test-Path $cacheFile)) { return $null }
        $cache = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $entry = $cache.PSObject.Properties[$exePath]
        if (-not $entry) { return $null }
        $v = $entry.Value
        if ($v.size -ne $item.Length) { return $null }
        if ($v.mtime -ne $item.LastWriteTimeUtc.Ticks) { return $null }
        return [string]$v.blocked
    } catch { return $null }
}

function Set-CachedFuseBlocked([string]$exePath, [string]$blocked) {
    try {
        $item = Get-Item -LiteralPath $exePath -ErrorAction Stop
        $cacheFile = Join-Path $WintageAppData 'fuse-cache.json'
        $cache = @{}
        if (Test-Path $cacheFile) {
            try {
                $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                foreach ($p in $raw.PSObject.Properties) { $cache[$p.Name] = $p.Value }
            } catch { $cache = @{} }
        }
        $cache[$exePath] = [pscustomobject]@{
            size    = $item.Length
            mtime   = $item.LastWriteTimeUtc.Ticks
            blocked = $blocked
        }
        $dir = Split-Path $cacheFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $tmp = "$cacheFile.tmp"
        [System.IO.File]::WriteAllText($tmp, ($cache | ConvertTo-Json -Depth 4), $script:Utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $cacheFile -Force
    } catch { }
}

# Read the manifest without letting a corrupt file abort a LISTING or a path
# probe. Callers that would write let the real Read-Manifest throw.
function Read-ManifestQuiet { try { return Read-Manifest } catch { return @{} } }

# Persist a validated explicit portable-path override into paths.json, atomically
# (W2-004): the CLI owns these keys, so a fresh process without the flag reuses
# what the previous successful run remembered - one source of truth.
# W2-007: serialized update. paths.json has two writers -- this CLI function
# and the GUI's Save-CustomPaths. Atomic file rename stops torn JSON but does
# not stop a lost update: if both read state S concurrently, each merges its
# own keys and the second rename silently deletes the other's freshly added
# entries. The fix is a dedicated lock file held across the whole read -> merge
# -> write-temp -> move sequence for BOTH writers.
function Save-PathPreference([string]$key, [string]$path) {
    if (-not $key -or -not $path) { return }
    if ($key -notin $script:PATHS_KEYS) { return }
    $dir = Split-Path $PathsPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lockPath = Join-Path $dir 'paths.lock'
    $lockStream = $null
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            break
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (10 + (Get-Random -Maximum 40))
        }
    }
    if ($null -eq $lockStream) { throw "could not acquire paths.json lock at $lockPath after 100 attempts." }
    try {
        $o = [ordered]@{}
        if (Test-Path $PathsPath) {
            try {
                $existing = (Read-Utf8 $PathsPath).Trim() | ConvertFrom-Json
                foreach ($prop in $existing.PSObject.Properties) { $o[$prop.Name] = $prop.Value }
            } catch { }
        }
        # W2-007 test seam: widen the read -> write window so a concurrency gate
        # can prove the lock is what serialises the update rather than luck. With
        # the lock held this delay is inside the critical section; without it both
        # writers read the same state and the second replace loses the first's
        # key. Never set outside tests.
        if ($env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS) { Start-Sleep -Milliseconds ([int]$env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS) }
        $o[$key] = $path
        $tmp = $PathsPath + '.tmp-' + [guid]::NewGuid().ToString('N')
        try {
            Write-Utf8 $tmp (($o | ConvertTo-Json) + "`n")
            Move-Item $tmp $PathsPath -Force
        } finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }
    } finally {
        $lockStream.Dispose()
    }
}

# CORE-004: the ONLY independently verifiable legacy Wintage identity for a
# VS Code-family extension directory is the built extension's own package.json:
# name wintage-themes, publisher vacterro. Nothing else - a pathname alone is
# never ownership proof.
function Test-LegacyWintageExtension([string]$dir) {
    $pkg = Join-Path $dir 'package.json'
    if (-not (Test-Path $pkg)) { return $false }
    try {
        $j = Read-Utf8 $pkg | ConvertFrom-Json
        return ([string]$j.name -eq 'wintage-themes') -and ([string]$j.publisher -eq 'vacterro')
    } catch { return $false }
}

# ─── Target path authority (W2-004) ─────────────────────────────────────────
# ONE precedence for every target-location consumer (resource tables, listing,
# health, dispatch), applied lazily AFTER preferences are loaded:
#   1. explicit CLI override
#   2. validated remembered preference (paths.json)
#   3. validated manifest-recorded path (recovering / Reapplying)
#   4. process / default discovery (last resort)
# A running process must NEVER outrank an explicitly requested or remembered
# installation, and the eager resource tables must not freeze values before
# paths.json is read.
function Resolve-PortableElectron([string]$key, [string]$explicitPath, [hashtable]$remembered, [string[]]$processName, [string[]]$defaultDirs) {
    # CORE-009: candidate semantic types are NOT uniform.
    #   - explicit / remembered / process / default = APP ROOT (need 'resources' appended)
    #   - manifest-recorded = ALREADY the resources directory (the installer
    #     writes Set-ManifestEntry ... $e.Resources, so the manifest value
    #     is the resources path itself; appending another 'resources' would
    #     test `<resources>\resources` and never resolve the install the
    #     manifest claims to be recording).
    $manifest = Read-ManifestQuiet
    $candidates = @()
    if ($explicitPath) { $candidates += (Join-Path $explicitPath 'resources') }
    if ($remembered -and $remembered.ContainsKey($key)) { $candidates += (Join-Path $remembered[$key] 'resources') }
    if ($manifest -and $manifest.ContainsKey($key) -and $manifest[$key].path) {
        # Manifest path is already the resources directory -- use it directly.
        $candidates += [string]$manifest[$key].path
    }
    foreach ($c in $candidates) { if (Test-ElectronApp $c) { return $c } }
    # Process / default discovery last.
    if ($processName) {
        $proc = Get-Process $processName -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($proc) {
            $r = Join-Path (Split-Path $proc.Path -Parent) 'resources'
            if (Test-ElectronApp $r) { return $r }
        }
    }
    foreach ($d in $defaultDirs) { if (Test-ElectronApp $d) { return $d } }
    return $null
}

function Get-ClaudeResources {
    # Squirrel keeps every version side by side; only the newest is the live one.
    # A malformed app-* dir (e.g. app-beta) must be ignored, never crash the sort
    # with a [version] cast (T-189).
    $root = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (-not (Test-Path $root)) { return $null }
    $app = Get-ChildItem $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object { $v = $null; [version]::TryParse(($_.Name -replace '^app-', ''), [ref]$v) } |
        Sort-Object { [version]($_.Name -replace '^app-', '') } | Select-Object -Last 1
    if (-not $app) { return $null }
    Join-Path $app.FullName 'resources'
}

# CodeNomad ships as a PORTABLE folder: no installer, no registry key, no fixed
# path. That is why it was originally themed by writing a stylesheet into
# ~/.config/codenomad/ instead -- a location the app does read config from, but a
# file it has no code to load. It was a 43 KB no-op, which is exactly what "still
# not themed" meant. It is an ordinary Electron app (resources/app.asar,
# "type": "module", hence the .cjs shim) and is themed like every other one.
#
# The running process is asked first because it is the only source that is right
# on a machine nobody has told this script about; the rest is where a portable
# folder tends to be dropped, with -CodeNomadPath as the explicit override.
function Get-CodeNomadResources {
    # W2-004 precedence: explicit > remembered > manifest-recorded > process/default.
    $script:pathsJson = if ($script:pathsJson) { $script:pathsJson } else { Read-PathsJson }
    return Resolve-PortableElectron 'codenomad' $CodeNomadPath $script:pathsJson 'CodeNomad' @(
        (Join-Path $env:LOCALAPPDATA 'Programs/CodeNomad/resources'),
        (Join-Path $env:ProgramFiles 'CodeNomad/resources')
    )
}

function Get-WorkBuddyResources {
    $script:pathsJson = if ($script:pathsJson) { $script:pathsJson } else { Read-PathsJson }
    return Resolve-PortableElectron 'workbuddy' $WorkBuddyPath $script:pathsJson @('WorkBuddy', 'CodeBuddy', 'WorkBuddyAI') @(
        (Join-Path $env:LOCALAPPDATA 'Programs/WorkBuddy/resources'),
        (Join-Path $env:LOCALAPPDATA 'Programs/WorkBuddy AI/resources'),
        (Join-Path $env:LOCALAPPDATA 'Programs/WorkBuddyAI/resources'),
        (Join-Path $env:LOCALAPPDATA 'Programs/CodeBuddy/resources'),
        (Join-Path $env:ProgramFiles 'WorkBuddy/resources'),
        (Join-Path $env:ProgramFiles 'CodeBuddy/resources')
    )
}

# The dead stylesheet the old CodeNomad path left behind. CORE-005: this
# cleanup is DESTRUCTIVE, so it requires verifiable Wintage provenance - a file
# that is byte-identical to a KNOWN historical Wintage payload (the exact
# generated wintage.css the installer wrote into custom.css before the target
# became an Electron shim). Unknown contents are user data and are preserved,
# even though they occupy a path Wintage once wrote.
$script:CODEDEAD_CONTENT_HASHES = @{
    # historical Wintage CSS written to custom.css (v1.15.0 golden default)
    '1ffdd98675c6664e38ffecf3fa0cb043cd232b07' = $true
    # v1.16.0-era generated wintage.css (golden default)
    '2d776c0f0aa809c9c85401664811dc1eda18af57' = $true
}
# Hash the file content WITHOUT a leading UTF-8 BOM: the historical installer
# wrote custom.css via Set-Content -Encoding UTF8, which prepends a BOM on
# Windows PowerShell 5.1, so byte equality with the git-object CSS would never
# match. The BOM is an artefact of the writer, not part of the payload.
function Get-FileSha1([string]$path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bytes = $bytes[3..($bytes.Length - 1)]
        }
        return [BitConverter]::ToString([System.Security.Cryptography.SHA1]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    catch { return $null }
}
function Remove-DeadCodeNomadCss {
    $dead = Join-Path $env:USERPROFILE '.config/codenomad/custom.css'
    if (-not (Test-Path $dead)) { return }
    $hash = Get-FileSha1 $dead
    if (-not $hash -or -not $script:CODEDEAD_CONTENT_HASHES.ContainsKey($hash)) {
        Say "CodeNomad: left $dead in place - it is not a known Wintage-written stylesheet (content hash $hash does not match any historical Wintage payload); preserving it as user data." 'DarkYellow'
        return
    }
    if ($PSCmdlet.ShouldProcess($dead, 'Remove the stylesheet CodeNomad never read (known Wintage payload)')) {
        Remove-Item $dead -Force
        Say "CodeNomad: removed $dead - it matched the known historical Wintage payload the app never read (see the note in install.ps1)." 'DarkGray'
    }
}

# W2-004: ONE Total Commander INI resolver shared by Apply, Revert and health -
# the [Colors] RedirectSection indirection is followed identically everywhere,
# so an unattended Reapply resolves the same EFFECTIVE file Apply recorded.
function Resolve-TotalCmdIni([int]$Index) {
    $candidates = if ($Index -eq 1) {
        @($TotalCmdIni, (Join-Path $env:APPDATA 'GHISLER\wincmd.ini'))
    } else {
        @($TotalCmd2Ini, (Join-Path $env:LOCALAPPDATA 'GHISLER\wincmd.ini'))
    }
    $ini = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $ini) { return $null }
    $lines = (Read-Utf8 $ini) -split '\r?\n'
    $inColors = $false
    foreach ($line in $lines) {
        if ($line -match '^\[Colors\]$') { $inColors = $true; continue }
        if ($line -match '^\[') { $inColors = $false }
        if ($inColors -and $line -match '^RedirectSection=(.+)$') {
            $redirect = $matches[1].Trim('"')
            $tcDir = Split-Path $ini -Parent
            $redirect = $redirect -replace '%COMMANDER_PATH%', $tcDir
            $redirect = $redirect -replace '%COMMANDER_INI%', $ini
            if (Test-Path $redirect) { $ini = $redirect }
            break
        }
    }
    return $ini
}

function Get-WindowsTerminalSettingsPaths {
    $paths = @($TERMINAL_DIRS | Where-Object { Test-Path $_ } | ForEach-Object { Join-Path $_ 'settings.json' })
    if ($wt = Get-Command wt.exe -ErrorAction SilentlyContinue) {
        $dir = Split-Path $wt.Source -Parent
        if (Test-Path (Join-Path $dir '.portable')) {
            $paths += Join-Path $dir 'settings.json'
        }
    }
    # T-194: Also check Scoop installations
    $scoopApp = Join-Path $env:USERPROFILE 'scoop\apps\windows-terminal\current'
    if (Test-Path $scoopApp) {
        $paths += Join-Path $scoopApp 'settings.json'
    }
    @($paths | Select-Object -Unique)
}

function Get-ConhostKeys {
    if (-not (Test-Path $CONHOST_KEY)) { return @() }
    @((Get-Item $CONHOST_KEY)) + @(Get-ChildItem $CONHOST_KEY -ErrorAction SilentlyContinue)
}

function Backup-WindowsInactiveAccent {
    if (Test-Path $WINDOWS_DWM_BACKUP) { return }
    $item = Get-Item $WINDOWS_DWM_KEY
    $name = 'AccentColorInactive'
    $existed = $item.GetValueNames() -contains $name
    $snapshot = [ordered]@{
        Name = $name
        Existed = $existed
        Kind = if ($existed) { $item.GetValueKind($name).ToString() } else { 'DWord' }
        Value = if ($existed) { $item.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $WINDOWS_DWM_BACKUP -Parent) | Out-Null
    Write-Utf8 $WINDOWS_DWM_BACKUP ($snapshot | ConvertTo-Json)
    # W2-001: the backup is now authoritative - stamp it with the owning epoch.
    Write-RecoveryProvenance $WINDOWS_DWM_BACKUP 'windows'
}

function Restore-WindowsInactiveAccent([switch]$Keep) {
    if (-not (Test-Path $WINDOWS_DWM_BACKUP)) { return }
    # W2-001: a backup stamped by another install is never used to rewrite the
    # live accent - fail closed before any registry write.
    Assert-RecoveryProvenance $WINDOWS_DWM_BACKUP 'windows' 'Windows system theme' | Out-Null
    $snapshot = Read-Utf8 $WINDOWS_DWM_BACKUP | ConvertFrom-Json
    if ($snapshot.Existed) {
        New-ItemProperty -Path $WINDOWS_DWM_KEY -Name $snapshot.Name -Value $snapshot.Value -PropertyType $snapshot.Kind -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $WINDOWS_DWM_KEY -Name $snapshot.Name -ErrorAction SilentlyContinue
    }
    # T-192 P1#27: the backup is the ONLY recovery authority for the accent value.
    # Callers that still face a manifest transition pass -Keep and delete it only
    # after the transition succeeded; a failed transition must not lose it.
    if (-not $Keep) { Remove-Item $WINDOWS_DWM_BACKUP -Force }
}

function Get-CssShape {
    # A stylesheet reduced to everything this patch is NOT allowed to touch, so
    # two files can be compared for "same stylesheet, different colours".
    #
    # ONLY the hex values of Wintage-owned `--token:` declarations are erased
    # (T-189). A blanket `#rrggbb -> #` strip used to erase EVERY hard-coded
    # colour in the file, so a legitimate upstream colour outside :root was
    # silently treated as "same shape" and lost when the backup was refreshed.
    # Whitespace is collapsed last so a CRLF/LF or re-indent difference does not
    # read as a content change.
    param([string]$Text)
    $t = $Text -replace '(--[A-Za-z0-9_-]+\s*:\s*)#[0-9A-Fa-f]{6}', '$1#'
    $t = $t -replace '\s*--dangerText\s*:\s*#\s*;', ''
    $t = $t -replace 'var\(--dangerText\)', 'var(--danger)'
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

# T-192 P1#18: rebuild a "new pristine" stylesheet from a possibly-THEMED live
# file + the OLD pristine authority. Every Wintage-owned `--token:` VALUE comes
# from the old pristine (stock); every other byte (new selectors, new tokens,
# comments) comes from the current live file. A known-themed live CSS is never
# allowed to become the pristine authority wholesale.
function Rebase-CssTokens([string]$live, [string]$oldPristine) {
    $result = $live
    foreach ($m in [regex]::Matches($oldPristine, '(--[A-Za-z0-9_-]+\s*:\s*)#[0-9A-Fa-f]{6}')) {
        $name = $m.Groups[1].Value
        $value = [regex]::Match($m.Value, '#[0-9A-Fa-f]{6}').Value
        $result = [regex]::Replace($result, ([regex]::Escape($name) + '#[0-9A-Fa-f]{6}'), ($name + $value))
    }
    return $result
}

function Get-ObsidianVaults {
    # Obsidian records every vault it has opened in %APPDATA%/obsidian/obsidian.json.
    # Themes are per-vault, so there is no single install location -- every vault
    # gets its own copy, which is also why an app update cannot remove them.
    $cfg = Join-Path $env:APPDATA 'obsidian/obsidian.json'
    if (-not (Test-Path $cfg)) { return @() }
    $j = (Read-Utf8 $cfg) | ConvertFrom-Json
    $out = @()
    foreach ($v in $j.vaults.PSObject.Properties) {
        if (Test-Path $v.Value.path) { $out += $v.Value.path }
    }
    $out
}

function Assert-SafeProjectPath([string]$path, [string]$label) {
    # Source-tree targets write into a folder the user owns. A path inside a
    # system directory, a drive root, or the user-profile root itself is either
    # a mistake (the tool path typed as C:\Windows) or a write where the user
    # should not be writing (a theme patch must not reach System32). Refuse it
    # loudly rather than patching whatever file happens to live there.
    if (-not $path) { return }
    $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
    $forbidden = @(
        [System.IO.Path]::GetPathRoot($full).TrimEnd('\'),
        ([System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\'))
    ) | Where-Object { $_ }
    if ($full -in $forbidden -or $full.StartsWith(([System.IO.Path]::GetFullPath($env:WINDIR) + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe $label path: $full - refusing to write outside a user-writable project root."
    }
    if ($env:ProgramFiles -and $full.StartsWith(([System.IO.Path]::GetFullPath($env:ProgramFiles) + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe $label path: $full - Program Files is not a source-tree project location."
    }
}
