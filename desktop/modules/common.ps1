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

# Every palette token read used to inline the same (Read-Utf8 X | ConvertFrom-Json).tokens
# chain; one helper (T-143).
function Get-PaletteTokens([string]$jsonPath) { (Read-Utf8 $jsonPath | ConvertFrom-Json).tokens }

# Known paths.json keys: the source-tree targets whose folders the GUI can remember.
$script:PATHS_KEYS = @('saipenview', 'smartvac', 'wildrift', 'codenomad', 'portable')

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
        $null = $mutex.WaitOne(15000)
        $got = $true
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
        $null = $mutex.WaitOne(60000)
        $got = $true
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

# Revert-with-recovery contract (T-189): when the manifest says a target was
# installed but the restore source is gone, that is a FAIL, not a happy
# "nothing to revert" — the user is left with half a theme and no undo. Only a
# target with NO recovery state (never installed by us) is a legitimate NOOP.
function Assert-RevertSource([string]$key, [string]$sourcePath, [string]$label) {
    if (Test-Path $sourcePath) { return }
    $m = Read-Manifest
    if ($m.ContainsKey($key)) {
        throw "$label : manifest says $key is installed but the restore source is missing ($sourcePath) - cannot restore. The manifest entry is kept as recovery evidence; fix the backup or remove the entry by hand."
    }
    Say "$label : nothing to revert (no Wintage recovery state)." 'DarkYellow'
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
    $proc = Get-Process CodeNomad -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($proc) {
        $r = Join-Path (Split-Path $proc.Path -Parent) 'resources'
        if (Test-ElectronApp $r) { return $r }
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/CodeNomad/resources'),
        (Join-Path $env:ProgramFiles 'CodeNomad/resources')
    )
    if ($CodeNomadPath) { $candidates = @((Join-Path $CodeNomadPath 'resources')) + $candidates }
    foreach ($c in $candidates) { if (Test-ElectronApp $c) { return $c } }
    return $null
}

# The dead stylesheet the old CodeNomad path left behind. Removed on both install
# and revert, because leaving it there means the next person to look sees a themed
# -looking config directory and re-learns the same wrong thing.
function Remove-DeadCodeNomadCss {
    $dead = Join-Path $env:USERPROFILE '.config/codenomad/custom.css'
    if (-not (Test-Path $dead)) { return }
    if ($PSCmdlet.ShouldProcess($dead, 'Remove the stylesheet CodeNomad never read')) {
        Remove-Item $dead -Force
        Say "CodeNomad: removed $dead - the app never read it (see the note in install.ps1)." 'DarkGray'
    }
}

function Get-WindowsTerminalSettingsPaths {
    @($TERMINAL_DIRS | Where-Object { Test-Path $_ } | ForEach-Object { Join-Path $_ 'settings.json' })
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
}

function Restore-WindowsInactiveAccent([switch]$Keep) {
    if (-not (Test-Path $WINDOWS_DWM_BACKUP)) { return }
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
