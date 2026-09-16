# Canonical cross-runtime generation publication lock (W2-004, SRC-007:R009).
#
# ONE protocol shared by every runtime that can publish or consume a Custom
# generation: install.ps1/common.ps1 (Enter-BatchLock), the GUI
# (Enter-BatchLockShared) and tools/build-desktop.js (acquireGenLock). The
# PowerShell side lives here so the two PowerShell callers cannot drift; the
# Node side mirrors this contract byte-for-byte in tools/build-desktop.js and
# tools/test-batch-generation.ps1 pins both.
#
# Lock file: <appdata>\build-generation.lock, created EXCLUSIVELY
# (CreateNew + FileShare.None in PowerShell, 'wx' in Node), so exactly one
# process owns it and a crashed owner's handle is released by the OS.
#
# METADATA CONTRACT (single-line JSON, UTF-8, no BOM):
#   token       - unique ownership token (GUID hex) minted at acquisition
#   pid         - owning process id
#   runtime     - 'powershell' | 'node'
#   acquired    - ISO-8601 UTC acquisition time
#   ownerCreated- UTC creation time of the OWNING PROCESS (StartTime), so a
#                 contender never trusts a bare pid: a reused pid whose
#                 StartTime does not match the recorded one is reported dead.
#
# RECOVERY CONTRACT (the R009 fix; age-only stealing is GONE):
#   - a contender may steal a lock only when it can POSITIVELY establish that
#     the recorded owner is no longer alive (pid gone, or pid alive but its
#     process start time does not match the recorded ownerCreated - i.e. the
#     recorder is gone and the pid was reused);
#   - age alone NEVER proves staleness: a valid long-running holder never
#     loses ownership, no matter how long it holds;
#   - a lock that cannot be read because another holder keeps it exclusively
#     is a LIVE holder as far as we can know -> wait;
#   - a readable but malformed/empty lock (crash between create and metadata
#     write) has no owner identity to protect. It is recovered only after its
#     mtime ages past the stale threshold - never while a writer could still
#     be mid-write - and every timeout error names the file so a wedged
#     machine can be cleared by hand deliberately;
#   - release is OWNERSHIP-VERIFIED: the file is unlinked only when it still
#     carries OUR token. A stale/old holder can never unlink a replacement
#     generation (no unconditional Remove-Item / unlinkSync anywhere).
#
# TEST SEAMS (never set in production):
#   WINTAGE_TEST_LOCK_TIMEOUT_MS - contention timeout, default 15000
#   WINTAGE_TEST_LOCK_STALE_MS   - malformed-lock recovery age, default 30000

function Get-GenerationLockTimeoutMs {
    if ($env:WINTAGE_TEST_LOCK_TIMEOUT_MS) { return [int]$env:WINTAGE_TEST_LOCK_TIMEOUT_MS }
    return 15000
}

function Get-GenerationLockStaleMs {
    if ($env:WINTAGE_TEST_LOCK_STALE_MS) { return [int]$env:WINTAGE_TEST_LOCK_STALE_MS }
    return 30000
}

# Read + classify the lock file WITHOUT stealing anything.
#   State = 'held'      -> unreadable (an owner keeps it exclusively) or gone
#   State = 'malformed' -> readable but empty/unparseable/no pid
#   State = 'ok'        -> parseable owner metadata in .Meta
function Get-GenerationLockState([string]$Path) {
    $raw = $null
    try {
        $raw = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        return [pscustomobject]@{ State = 'held'; Meta = $null }
    }
    if (-not $raw -or -not $raw.Trim()) {
        return [pscustomobject]@{ State = 'malformed'; Meta = $null }
    }
    try {
        $meta = $raw.Trim() | ConvertFrom-Json
        if (-not $meta -or -not $meta.pid) { return [pscustomobject]@{ State = 'malformed'; Meta = $null } }
        return [pscustomobject]@{ State = 'ok'; Meta = $meta }
    } catch {
        return [pscustomobject]@{ State = 'malformed'; Meta = $null }
    }
}

# Positively establish owner liveness from parsed metadata.
# Returns 'alive', 'dead' or 'unknown' (unknown = fail closed, never steal).
function Test-GenerationLockOwnerAlive($meta) {
    if (-not $meta -or -not $meta.pid) { return 'unknown' }
    $proc = $null
    try { $proc = Get-Process -Id ([int]$meta.pid) -ErrorAction Stop } catch { }
    if (-not $proc) { return 'dead' }
    if ($meta.ownerCreated) {
        # PID-reuse guard: a live process whose start time does not match the
        # recorded owner is NOT the recorded owner - the recorder is dead.
        try {
            $recorded = ([datetime]$meta.ownerCreated).ToUniversalTime()
            $actual = $proc.StartTime.ToUniversalTime()
            if ([Math]::Abs(($actual - $recorded).TotalSeconds) -gt 5) { return 'dead' }
        } catch {
            return 'unknown'
        }
    }
    return 'alive'
}

# Acquire the cross-runtime generation lock for $AppData.
# Returns { Stream; Token; Path; MetadataWritten } or throws after the bounded
# timeout. Self-cleaning: a failed metadata write releases the just-created
# file before throwing, so an acquisition never returns a lock that cannot
# later be proven ours.
function Enter-BuildGenerationLockCore([string]$AppData) {
    $lockPath = Join-Path $AppData 'build-generation.lock'
    $timeoutMs = Get-GenerationLockTimeoutMs
    $staleMs = Get-GenerationLockStaleMs
    $token = [guid]::NewGuid().ToString('N')
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    $ownerCreated = $self.StartTime.ToUniversalTime().ToString('o')
    $start = [DateTime]::UtcNow
    while ($true) {
        $fs = $null
        try {
            $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            # Lock exists (or vanished between the attempt and the read).
            if (Test-Path -LiteralPath $lockPath) {
                $state = Get-GenerationLockState $lockPath
                $steal = $false
                if ($state.State -eq 'ok') {
                    $steal = (Test-GenerationLockOwnerAlive $state.Meta) -eq 'dead'
                } elseif ($state.State -eq 'malformed') {
                    # No owner identity to protect: recover only after the
                    # stale age, so an in-progress write is never interrupted.
                    try {
                        $ageMs = ([DateTime]::UtcNow - (Get-Item -LiteralPath $lockPath).LastWriteTimeUtc).TotalMilliseconds
                        if ($ageMs -gt $staleMs) { $steal = $true }
                    } catch { }
                }
                if ($steal) {
                    try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop } catch { $steal = $false }
                }
                if ($steal) { continue }
            }
            if (([DateTime]::UtcNow - $start).TotalMilliseconds -ge $timeoutMs) {
                $state2 = $null
                try { $state2 = Get-GenerationLockState $lockPath } catch { }
                if ($state2 -and $state2.State -eq 'malformed') {
                    throw "W2-004: build/output busy - generation lock contended and $lockPath is malformed (no usable owner metadata). Clear it by hand if no build is running."
                }
                throw "W2-004: build/output busy - generation lock contended (timeout $([int]($timeoutMs / 1000))s). Retry; if recurring, clear stale $lockPath."
            }
            Start-Sleep -Milliseconds 100
            continue
        }
        try {
            $meta = [ordered]@{
                token        = $token
                pid          = $self.Id
                runtime      = 'powershell'
                acquired     = [DateTime]::UtcNow.ToString('o')
                ownerCreated = $ownerCreated
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes(($meta | ConvertTo-Json -Compress) + "`n")
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush()
            return [pscustomobject]@{ Stream = $fs; Token = $token; Path = $lockPath; MetadataWritten = $true }
        } catch {
            try { $fs.Close() } catch { }
            try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch { }
            throw
        }
    }
}

# Ownership-verified release: remove the lock file only when it still carries
# OUR token. Never an unconditional delete. Fail closed on any current state we
# cannot positively tie to THIS acquisition:
#   ok + matching token   -> remove;
#   ok + foreign token    -> leave untouched (a newer generation owns it);
#   malformed/empty/unknown -> leave untouched. MetadataWritten proves only that
#       THIS acquisition wrote metadata earlier - never that the file now at the
#       path is still ours once the exclusive handle has been closed. It is NOT
#       delete authority (the stale-release delete race W2-004).
#   held (exclusively locked by someone else) -> leave untouched;
#   absent -> already released, safe.
function Exit-BuildGenerationLockCore($genLock) {
    if (-not $genLock) { return }
    try { if ($genLock.Stream) { $genLock.Stream.Close() } } catch { }
    try {
        if (-not (Test-Path -LiteralPath $genLock.Path)) { return }
        $state = Get-GenerationLockState $genLock.Path
        if ($state.State -eq 'ok' -and [string]$state.Meta.token -eq [string]$genLock.Token) {
            Remove-Item -LiteralPath $genLock.Path -Force -ErrorAction SilentlyContinue
        }
        # Anything else (foreign token, malformed/empty, held) is left exactly
        # as found: a release that cannot prove ownership never destroys.
    } catch { }
}
