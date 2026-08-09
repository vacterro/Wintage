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

function Read-PathsJson {
    if (-not (Test-Path $PathsPath)) { return @{} }
    try {
        $json = (Read-Utf8 $PathsPath).Trim()
        if (-not $json) { return @{} }
        $obj = $json | ConvertFrom-Json
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
        return $ht
    } catch {
        Write-Warning "could not read ${PathsPath}: $($_.Exception.Message) -- remembered paths ignored"
        return @{}
    }
}

function Read-Manifest {
    if (-not (Test-Path $ManifestPath)) { return @{} }
    $json = (Read-Utf8 $ManifestPath).Trim()
    if (-not $json) { return @{} }
    try {
        $obj = $json | ConvertFrom-Json
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
        return $ht
    } catch {
        Write-Warning "could not read ${ManifestPath}: $($_.Exception.Message) -- treating as empty"
        return @{}
    }
}

function Write-Manifest($manifest) {
    if ($WhatIfPreference) { return }
    New-Item -ItemType Directory -Force -Path $WintageAppData | Out-Null
    Write-Utf8 $ManifestPath (($manifest | ConvertTo-Json -Depth 3) + "`n")
}

function Set-ManifestEntry($target, $palette, $resolvedPath, $appVersion, $payloadVersion) {
    $m = Read-Manifest
    $m[$target] = @{
        palette       = $palette
        path          = $resolvedPath
        appVersion    = $appVersion
        payloadVersion = $payloadVersion
        applied       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    Write-Manifest $m
}

function Remove-ManifestEntry($target) {
    $m = Read-Manifest
    if ($m.ContainsKey($target)) {
        $m.Remove($target)
        Write-Manifest $m
    }
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
    $root = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (-not (Test-Path $root)) { return $null }
    $app = Get-ChildItem $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
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

function Restore-WindowsInactiveAccent {
    if (-not (Test-Path $WINDOWS_DWM_BACKUP)) { return }
    $snapshot = Read-Utf8 $WINDOWS_DWM_BACKUP | ConvertFrom-Json
    if ($snapshot.Existed) {
        New-ItemProperty -Path $WINDOWS_DWM_KEY -Name $snapshot.Name -Value $snapshot.Value -PropertyType $snapshot.Kind -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $WINDOWS_DWM_KEY -Name $snapshot.Name -ErrorAction SilentlyContinue
    }
    Remove-Item $WINDOWS_DWM_BACKUP -Force
}

function Get-CssShape {
    # A stylesheet reduced to everything this patch is NOT allowed to touch, so
    # two files can be compared for "same stylesheet, different colours".
    #
    # Removed: every #rrggbb literal (the token rewrite), the --dangerText
    # declaration this function's caller inserts, and the var(--dangerText)
    # substitutions it makes. Whitespace is collapsed last so a CRLF/LF or
    # re-indent difference does not read as a content change.
    param([string]$Text)
    $t = $Text -replace '#[0-9A-Fa-f]{6}', '#'
    $t = $t -replace '\s*--dangerText\s*:\s*#\s*;', ''
    $t = $t -replace 'var\(--dangerText\)', 'var(--danger)'
    $t = $t -replace '\s+', ' '
    return $t.Trim()
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
