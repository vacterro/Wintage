# Installs the Wintage look into desktop applications.
#
# Design constraint that shapes everything here: applications update themselves, and
# an update must not take the theme with it. So every target is installed into the
# USER's own profile where the app looks for extensions/config, never into the app's
# program directory -- and where a target has no such profile location (MPC-HC,
# Electron apps), the installer is written to be re-run after an update rather than
# pretending it survived one.
#
#   .\install.ps1                       # list targets and what each one can reach
#   .\install.ps1 -Target antigravity   # install one
#   .\install.ps1 -Target all
#   .\install.ps1 -Target all -WhatIf   # say what would change, touch nothing
#   .\install.ps1 -Target antigravity -Revert
#
# Anything overwritten is copied to desktop/backup/<timestamp>/ first.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('windows', 'browsers', 'antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'codenomad', 'mpchc', 'terminal', 'conhost', 'obs', 'discord', 'totalcmd', 'totalcmd2', 'obsidian', 'saipenview', 'smartvac', 'wildrift', 'all')]
    [string]$Target,
    [string]$Palette = 'goldendefault',
    [switch]$Revert,
    [switch]$Force,
    [string]$CodeNomadPath,
    [string]$TotalCmdIni,
    [string]$TotalCmd2Ini,
    [string]$PortableBrowserRoot,
    [string]$BrowserStageRoot = (Join-Path $env:LOCALAPPDATA 'Wintage\browser-theme'),
    [string]$BrowserCatalog,
    [switch]$NoBrowserLaunch,
    [string]$SaipenviewPath,
    [string]$SmartVacPath,
    [string]$WildRiftPath,
    [switch]$Reapply,
    [switch]$Status,
    [switch]$Quiet,
    [switch]$RegisterLogonTask,
    [switch]$UnregisterLogonTask
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$out = Join-Path $here 'out'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $here "backup/$stamp"

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

# PowerShell 5.1 writes a BOM with `Set-Content -Encoding UTF8`, and `Get-Content`
# falls back to the ANSI codepage on a file that has none. Both halves have already
# bitten this project once: SAIPENVIEW's stylesheet came back with 30 mojibaked
# em-dashes and a stray glyph before `:root` (E-159). The same pair of calls was
# still writing five other targets, including Obsidian's appearance.json -- and a
# BOM there is not cosmetic, because JSON.parse throws on it. Found one already on
# disk in the parent vault.
#
# Every read/write of a file we did not generate goes through these two.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Read-Utf8([string]$path) { [System.IO.File]::ReadAllText($path, $script:Utf8NoBom) }
function Write-Utf8([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text, $script:Utf8NoBom) }
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)
function Write-Utf8BomLines([string]$path, $lines) { [System.IO.File]::WriteAllLines($path, [string[]]$lines, $script:Utf8WithBom) }
# Every palette token read used to inline the same (Read-Utf8 X | ConvertFrom-Json).tokens
# chain; one helper (T-143).
function Get-PaletteTokens([string]$jsonPath) { (Read-Utf8 $jsonPath | ConvertFrom-Json).tokens }

$WintageAppData = Join-Path $env:APPDATA 'Wintage'
$ManifestPath = Join-Path $WintageAppData 'installed.json'
$PathsPath = Join-Path $WintageAppData 'paths.json'

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

. (Join-Path $PSScriptRoot 'i18n.ps1')

function Get-PayloadVersion {
    $raw = (Read-Utf8 (Join-Path $root 'wintage.user.js')) -split "`n" |
        Where-Object { $_ -match '// @version\s+(\S+)' } |
        Select-Object -First 1
    if ($raw -match '// @version\s+(\S+)') { return $matches[1] }
    return 'unknown'
}

$TASK_NAME = 'Wintage Reapply at Logon'

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

# Where each target keeps its extensions. Both are VS Code-family and read the
# identical format, which is why one built extension serves them both.
$TARGETS = @{
    antigravity = @{
        Name  = 'Antigravity IDE'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $HOME '.antigravity/extensions'
        Built = Join-Path $out 'vscode/wintage-themes'
        Note  = 'Six colour themes. Lives in your profile, so an IDE update cannot remove it.'
    }
    vscode      = @{
        Name  = 'Visual Studio Code'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $HOME '.vscode/extensions'
        Built = Join-Path $out 'vscode/wintage-themes'
        Note  = 'Same extension as Antigravity -- VS Code family, identical format.'
    }
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
        (Join-Path $CodeNomadPath 'resources'),
        (Join-Path $env:LOCALAPPDATA 'Programs/CodeNomad/resources'),
        (Join-Path $env:ProgramFiles 'CodeNomad/resources')
    )
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

$ELECTRON = @{
    claude          = @{
        Name      = 'Claude (desktop app)'
        Resources = (Get-ClaudeResources)
        Note      = 'Electron. Update creates a new app-<version> folder, so re-run after an update.'
        InPlace   = $true
    }
    freebuff        = @{
        Name      = 'Freebuff'
        Resources = Join-Path $env:LOCALAPPDATA 'Programs/@codebufffreebuff-desktop/resources'
        Note      = 'Electron.'
    }
    'antigravity-app' = @{
        Name      = 'Antigravity (agent app, not the IDE)'
        Resources = Join-Path $env:LOCALAPPDATA 'Programs/Antigravity/resources'
        Note      = 'Electron. Separate program from the IDE, themed separately.'
    }
    codenomad       = @{
        Name      = 'CodeNomad'
        Resources = (Get-CodeNomadResources)
        Note      = 'Electron, portable. Pass -CodeNomadPath if it lives somewhere else.'
    }
}

# ---- MPC-HC (K-Lite) ----
# Native Win32, no stylesheet, no injection point. Its dark theme's colours are
# COMPILED IN (CMPCTheme in the MPC-HC source) and no registry value exposes them,
# so this target cannot carry a palette at all. What it can do is switch the dark
# theme on and put the UI.md typography rules on the one surface MPC-HC does let a
# user control -- the OSD. Saying that plainly beats claiming a coverage that does
# not exist, which is why the report below names what is out of reach.
$TERMINAL_DIRS = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal')
)
# Terminal renderers lay text on a fixed cell grid. Verdana is proportional:
# forcing it made conhost keep fixed cells while drawing variable-width glyphs,
# so letters visibly collided. Consolas is bundled with Windows, monospace and
# already approved by conhost's TrueTypeFont registry.
$CONSOLE_FONT = 'Consolas'

function Get-WindowsTerminalSettingsPaths {
    @($TERMINAL_DIRS | Where-Object { Test-Path $_ } | ForEach-Object { Join-Path $_ 'settings.json' })
}

function Invoke-WindowsTerminal {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $settingsPaths = @(Get-WindowsTerminalSettingsPaths)
    if (-not $settingsPaths.Count) { Say 'Windows Terminal: not installed on this machine - skipped.' 'DarkYellow'; return }
    if (-not $node) { Say 'Windows Terminal: node is required to patch JSON-with-comments safely - skipped.' 'Yellow'; return }

    $helper = Join-Path $root 'tools/install-terminal.js'
    $paletteFile = Join-Path $root "themes\$PaletteSlug.json"
    foreach ($settings in $settingsPaths) {
        $args = @($helper, '--settings', $settings)
        if ($DoRevert) { $args += '--revert' } else { $args += @('--palette', $paletteFile) }
        $action = if ($DoRevert) { 'Restore the pre-Wintage settings' } else { "Apply $PaletteSlug + $CONSOLE_FONT to every profile" }
        if ($WhatIfPreference) { & node ($args + '--dry-run'); continue }
        if ($PSCmdlet.ShouldProcess($settings, $action)) {
            & node $args
            if ($LASTEXITCODE -ne 0) { throw "Windows Terminal patch failed for $settings" }
        }
    }
    if ($settingsPaths.Count) {
        $firstPath = $settingsPaths[0]
        if ($DoRevert) { Remove-ManifestEntry 'terminal' }
        else { Set-ManifestEntry 'terminal' $PaletteSlug $firstPath 'n/a' (Get-PayloadVersion) }
    }
}

$CONHOST_KEY = 'HKCU:\Console'
$CONHOST_BACKUP = Join-Path $here 'backup/conhost-settings.json'

function Get-ConhostKeys {
    if (-not (Test-Path $CONHOST_KEY)) { return @() }
    @((Get-Item $CONHOST_KEY)) + @(Get-ChildItem $CONHOST_KEY -ErrorAction SilentlyContinue)
}

function Invoke-Conhost {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $keys = @(Get-ConhostKeys)
    if (-not $keys.Count) { Say 'Console Host: HKCU\Console not found - skipped.' 'DarkYellow'; return }

    if ($DoRevert) {
        if (-not (Test-Path $CONHOST_BACKUP)) { Say 'Console Host: no Wintage backup to restore from.' 'DarkYellow'; return }
        if ($PSCmdlet.ShouldProcess($CONHOST_KEY, 'Restore pre-Wintage console colours and font')) {
            # Windows PowerShell 5.1 returns a top-level JSON array as one
            # Object[] pipeline item. Assign first, then enumerate it; wrapping
            # the pipeline itself in @() produces a nested array.
            $parsedSnapshot = Read-Utf8 $CONHOST_BACKUP | ConvertFrom-Json
            $snapshot = @($parsedSnapshot)
            foreach ($item in $snapshot) {
                if (-not (Test-Path -LiteralPath $item.Path)) { continue }
                if ($item.Existed) {
                    New-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value $item.Value -PropertyType $item.Kind -Force | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction SilentlyContinue
                }
            }
            Remove-Item $CONHOST_BACKUP -Force
            Say 'Console Host: restored pre-Wintage registry values.' 'Green'
            Remove-ManifestEntry 'conhost'
        }
        return
    }

    $paletteFile = Join-Path $root "themes\$PaletteSlug.json"
    if (-not (Test-Path $paletteFile)) { Say "Console Host: theme file not found ($PaletteSlug.json)" 'Red'; return }
    $t = Get-PaletteTokens $paletteFile
    $values = [ordered]@{
        FaceName      = @{ Value = $CONSOLE_FONT; Type = 'String' }
        FontFamily    = @{ Value = 54; Type = 'DWord' }
        FontWeight    = @{ Value = 400; Type = 'DWord' }
        FontSize      = @{ Value = 1048576; Type = 'DWord' }
        ScreenColors  = @{ Value = 15; Type = 'DWord' }
        PopupColors   = @{ Value = 240; Type = 'DWord' }
        CursorColor   = @{ Value = (Convert-HexToBgr $t.link); Type = 'DWord' }
        WindowAlpha   = @{ Value = 255; Type = 'DWord' }
        ColorTable00  = @{ Value = (Convert-HexToBgr $t.background); Type = 'DWord' }
        ColorTable01  = @{ Value = (Convert-HexToBgr $t.accentTealDeep); Type = 'DWord' }
        ColorTable02  = @{ Value = (Convert-HexToBgr $t.success); Type = 'DWord' }
        ColorTable03  = @{ Value = (Convert-HexToBgr $t.accentTeal); Type = 'DWord' }
        ColorTable04  = @{ Value = (Convert-HexToBgr $t.danger); Type = 'DWord' }
        ColorTable05  = @{ Value = (Convert-HexToBgr $t.surfaceAlt); Type = 'DWord' }
        ColorTable06  = @{ Value = (Convert-HexToBgr $t.warning); Type = 'DWord' }
        ColorTable07  = @{ Value = (Convert-HexToBgr $t.textSecondary); Type = 'DWord' }
        ColorTable08  = @{ Value = (Convert-HexToBgr $t.borderMuted); Type = 'DWord' }
        ColorTable09  = @{ Value = (Convert-HexToBgr $t.link); Type = 'DWord' }
        ColorTable10  = @{ Value = (Convert-HexToBgr $t.success); Type = 'DWord' }
        ColorTable11  = @{ Value = (Convert-HexToBgr $t.accentTeal); Type = 'DWord' }
        ColorTable12  = @{ Value = (Convert-HexToBgr $t.dangerText); Type = 'DWord' }
        ColorTable13  = @{ Value = (Convert-HexToBgr $t.surfaceAlt); Type = 'DWord' }
        ColorTable14  = @{ Value = (Convert-HexToBgr $t.textPrimary); Type = 'DWord' }
        ColorTable15  = @{ Value = (Convert-HexToBgr $t.textPrimary); Type = 'DWord' }
        WintagePalette = @{ Value = $PaletteSlug; Type = 'String' }
    }

    if ($PSCmdlet.ShouldProcess($CONHOST_KEY, "Apply $PaletteSlug + $CONSOLE_FONT to defaults and existing console profiles")) {
        # Keep the first-seen value for every path/name pair. A console profile can
        # appear after the first install (Git, a shortcut, another shell); repainting
        # must extend the snapshot before touching that new key or Revert would know
        # how to restore the old profiles but not the new one.
        # Do not assign an `if` pipeline directly here: PowerShell unwraps a
        # one-item result to PSObject (and an empty result to $null), so the
        # later `+=` fails as soon as a second value is captured.
        $snapshot = @()
        if (Test-Path $CONHOST_BACKUP) {
            $parsedSnapshot = Read-Utf8 $CONHOST_BACKUP | ConvertFrom-Json
            $snapshot = @($parsedSnapshot)
        }
        $snapshotChanged = $false
        foreach ($key in $keys) {
            foreach ($name in $values.Keys) {
                $known = @($snapshot | Where-Object { $_.Path -eq $key.PSPath -and $_.Name -eq $name }).Count -gt 0
                if ($known) { continue }
                $exists = $key.GetValueNames() -contains $name
                $snapshot += [pscustomobject]@{
                    Path = $key.PSPath
                    Name = $name
                    Existed = $exists
                    Kind = if ($exists) { $key.GetValueKind($name).ToString() } else { $values[$name].Type }
                    Value = if ($exists) { $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
                }
                $snapshotChanged = $true
            }
        }
        if ($snapshotChanged) {
            New-Item -ItemType Directory -Force -Path (Split-Path $CONHOST_BACKUP -Parent) | Out-Null
            $backupTemp = $CONHOST_BACKUP + '.tmp'
            Write-Utf8 $backupTemp ($snapshot | ConvertTo-Json -Depth 4)
            Move-Item $backupTemp $CONHOST_BACKUP -Force
        }
        foreach ($key in $keys) {
            foreach ($name in $values.Keys) {
                New-ItemProperty -LiteralPath $key.PSPath -Name $name -Value $values[$name].Value -PropertyType $values[$name].Type -Force | Out-Null
            }
        }
        Say "Console Host: applied $PaletteSlug + $CONSOLE_FONT to $($keys.Count) registry profile(s)." 'Green'
        Say '  Restart cmd/PowerShell windows to replace the old proportional-font cells.' 'Yellow'
        Set-ManifestEntry 'conhost' $PaletteSlug $CONHOST_KEY 'n/a' (Get-PayloadVersion)
    }
}

$WINDOWS_THEME_KEY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$WINDOWS_THEMES_DIR = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
$WINDOWS_THEME_MARKER = Join-Path $WINDOWS_THEMES_DIR '.wintage-windows-palette'
$WINDOWS_DWM_KEY = 'HKCU:\Software\Microsoft\Windows\DWM'
$WINDOWS_DWM_BACKUP = Join-Path $here 'backup/windows-dwm-settings.json'

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

function Invoke-WindowsTheme {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not $node) { Say 'Windows theme: node is required to preserve and merge the active .theme safely - skipped.' 'Yellow'; return }
    $current = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
    $helper = Join-Path $root 'tools/install-windows-theme.js'
    $built = Join-Path $out "windows/$PaletteSlug/Wintage.theme"
    if (-not $DoRevert -and -not (Test-Path $built)) { throw "No Windows theme build for palette '$PaletteSlug'." }
    if (-not $DoRevert -and (-not $current -or -not (Test-Path $current))) {
        Say 'Windows theme: active .theme file was not found - skipped to avoid losing wallpaper/cursor settings.' 'Yellow'
        return
    }

    $args = @($helper, '--themes-dir', $WINDOWS_THEMES_DIR)
    if ($DoRevert) { $args += '--revert' }
    else { $args += @('--theme', $built, '--current-theme', $current, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore the exact pre-Wintage Windows theme snapshot' } else { "Merge and activate Wintage $PaletteSlug, preserving wallpaper/sounds and selecting ___CURRENT___ cursors" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); return }
    if (-not $PSCmdlet.ShouldProcess($WINDOWS_THEMES_DIR, $action)) { return }

    $helperOutput = @(& node $args)
    if ($LASTEXITCODE -ne 0) { throw 'Windows theme preparation failed.' }
    $payload = $helperOutput[-1] | ConvertFrom-Json

    $expectedAccent = $null
    if ($DoRevert) { Restore-WindowsInactiveAccent }
    else {
        Backup-WindowsInactiveAccent
        $tokens = Get-PaletteTokens (Join-Path $root "themes/$PaletteSlug.json")
        $inactiveAccent = ([uint32](Convert-HexToBgr $tokens.surfaceRaised)) -bor [uint32]4278190080
        $expectedAccent = $inactiveAccent
        New-ItemProperty -Path $WINDOWS_DWM_KEY -Name AccentColorInactive -Value $inactiveAccent -PropertyType DWord -Force | Out-Null
    }

    # Microsoft documents ShellExecute as the supported installer path for .theme
    # files. Show=0 asks the Personalization host to stay hidden while applying;
    # Windows may ignore that hint, but the colours are selected immediately.
    $shell = New-Object -ComObject Shell.Application
    try { $shell.ShellExecute([string]$payload.activate, '', '', 'open', 0) }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    $activated = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        Start-Sleep -Milliseconds 100
        $now = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
        if ($now -and ([IO.Path]::GetFullPath($now) -eq [IO.Path]::GetFullPath([string]$payload.activate))) { $activated = $true; break }
        if (-not $DoRevert) {
            $dwmNow = Get-ItemProperty $WINDOWS_DWM_KEY -ErrorAction SilentlyContinue
            $cursorNow = (Get-ItemProperty 'HKCU:\Control Panel\Cursors' -ErrorAction SilentlyContinue).'(default)'
            if ([uint32]$dwmNow.AccentColor -eq $expectedAccent -and [uint32]$dwmNow.AccentColorInactive -eq $expectedAccent -and $cursorNow -eq '___CURRENT___') { $activated = $true; break }
        }
    }
    if (-not $activated) {
        # Windows 10 keeps a hidden SystemSettings process after some .theme
        # activations. A second ShellExecute is then swallowed by that stale
        # process: no error, no theme change. Close only after the documented path
        # failed, retry once, and keep the retry hidden too.
        Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 250
        Start-Process -FilePath ([string]$payload.activate) -WindowStyle Hidden
        for ($attempt = 0; $attempt -lt 50; $attempt++) {
            Start-Sleep -Milliseconds 100
            $now = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
            if ($now -and ([IO.Path]::GetFullPath($now) -eq [IO.Path]::GetFullPath([string]$payload.activate))) { $activated = $true; break }
            if (-not $DoRevert) {
                $dwmNow = Get-ItemProperty $WINDOWS_DWM_KEY -ErrorAction SilentlyContinue
                $cursorNow = (Get-ItemProperty 'HKCU:\Control Panel\Cursors' -ErrorAction SilentlyContinue).'(default)'
                if ([uint32]$dwmNow.AccentColor -eq $expectedAccent -and [uint32]$dwmNow.AccentColorInactive -eq $expectedAccent -and $cursorNow -eq '___CURRENT___') { $activated = $true; break }
            }
        }
    }
    if (-not $activated) { Say 'Windows: theme activation was dispatched but Windows did not confirm it after both attempts.' 'Yellow'; return }
    foreach ($oldTheme in @($payload.cleanup)) {
        if (-not $oldTheme) { continue }
        $fullOld = [IO.Path]::GetFullPath([string]$oldTheme)
        $safeParent = [IO.Path]::GetFullPath($WINDOWS_THEMES_DIR).TrimEnd('\')
        $safeLeaf = Split-Path $fullOld -Leaf
        if ((Split-Path $fullOld -Parent).TrimEnd('\') -eq $safeParent -and
            $safeLeaf -match '^Wintage(?:-[0-9a-f]{10})?\.theme$' -and
            $fullOld -ne [IO.Path]::GetFullPath([string]$payload.activate)) {
            Remove-Item -LiteralPath $fullOld -Force -ErrorAction SilentlyContinue
        }
    }
    if ($DoRevert) { Say 'Windows: restored the saved pre-Wintage theme.' 'Green'; Remove-ManifestEntry 'windows' }
    else { Say "Windows: activated Wintage $PaletteSlug; wallpaper/sounds preserved, ___CURRENT___ cursors selected." 'Green'; Set-ManifestEntry 'windows' $PaletteSlug $WINDOWS_THEMES_DIR 'n/a' (Get-PayloadVersion) }
}

$MPC_KEY = 'HKCU:\Software\MPC-HC\MPC-HC\Settings'
$MPC_REG = 'HKCU\Software\MPC-HC\MPC-HC\Settings'


function Invoke-TotalCmd {
    param([int]$Index, [switch]$DoRevert, [string]$PaletteSlug)
    $appName = if ($Index -eq 1) { 'Total Commander' } else { 'Total Commander (Local)' }
    $manifestName = if ($Index -eq 1) { 'totalcmd' } else { 'totalcmd2' }
    $candidates = if ($Index -eq 1) {
        @($TotalCmdIni, (Join-Path $env:APPDATA 'GHISLER\wincmd.ini'))
    } else {
        @($TotalCmd2Ini, (Join-Path $env:LOCALAPPDATA 'GHISLER\wincmd.ini'))
    }
    $ini = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if (-not $ini) { Say "$($appName): not installed (no wincmd.ini found)" 'DarkYellow'; return }

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
            if (Test-Path $redirect) {
                $ini = $redirect
            }
            break
        }
    }

    # This is the only target whose config is a file the USER has been editing for
    # years, and it was the only one with no backup. Its revert deleted every
    # BackColor/ForeColor/... line in the whole file -- so a colour the user had set
    # themselves before Wintage ever ran was destroyed, with nothing to restore it
    # from, and a matching key in an unrelated section went with it. One backup,
    # taken before the first write and never overwritten, turns that into an undo.
    $iniBak = $ini + '.wintage.bak'

    if ($DoRevert) {
        if ($PSCmdlet.ShouldProcess($ini, 'Revert Wintage theme')) {
            if (Test-Path $iniBak) {
                Copy-Item $iniBak $ini -Force
                Remove-Item $iniBak -Force
                Say "$($appName): restored wincmd.ini from the pre-Wintage backup" 'Green'
                Remove-ManifestEntry $manifestName
            }
            else {
                # No backup: this ini was themed by an older version that never made
                # one. Strip only inside the colour sections, so a same-named key
                # elsewhere in the file survives -- and say plainly that anything the
                # user had set in those sections before is not recoverable here.
                $lines = (Read-Utf8 $ini) -split '\r?\n'
                $keys = '^(BackColor|BackColor2|ForeColor|MarkColor|CursorColor|CursorText|ActiveTitle|ActiveTitleText|InactiveTitle|InactiveTitleText)='
                $newLines = @(); $inColors = $false
                foreach ($line in $lines) {
                    if ($line -match '^\[(Colors|ColorsDark)\]$') { $inColors = $true; $newLines += $line; continue }
                    if ($line -match '^\[') { $inColors = $false }
                    if ($inColors -and $line.Trim() -match $keys) { continue }
                    $newLines += $line
                }
                Write-Utf8BomLines $ini $newLines
                Say "$($appName): no backup found - stripped the colour keys from [Colors]/[ColorsDark] only." 'Yellow'
                Say "  Colours you had set there before Wintage cannot be restored from here." 'Yellow'
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($ini, 'Apply Wintage theme')) {
        # Once only: a second export would capture the ALREADY themed ini and destroy
        # the one copy of the original. Same discipline as the MPC-HC .reg backup.
        if (-not (Test-Path $iniBak)) {
            Copy-Item $ini $iniBak -Force
            Say "$($appName): backed up wincmd.ini -> $(Split-Path $iniBak -Leaf)" 'DarkGray'
        }
        $jsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "themes\$PaletteSlug.json"
        if (-not (Test-Path $jsonPath)) { Say "$($appName): theme file not found ($PaletteSlug.json)" 'Red'; return }
        $t = Get-PaletteTokens $jsonPath

        $bg = Convert-HexToBgr $t.background
        $fg = Convert-HexToBgr $t.textPrimary
        $cursorBg = Convert-HexToBgr $t.selection
        $cursorFg = Convert-HexToBgr $t.borderHighlight
        $markFg = Convert-HexToBgr $t.danger
        $titleBg = Convert-HexToBgr $t.surface
        $titleFg = Convert-HexToBgr $t.textPrimary
        $titleInBg = Convert-HexToBgr $t.backgroundSoft
        $titleInFg = Convert-HexToBgr $t.textMuted
        # A colour filter may point to a saved search as >Name. SearchFlags fields
        # 4/5 carry its relative age and unit; -1/-1 means no valid relative date.
        # Recolour only existing age filters. User expressions, ordering and every
        # unrelated filter remain byte-for-byte in place.
        $lines = (Read-Utf8 $ini) -split '\r?\n'
        $searchFlags = @{}
        foreach ($line in $lines) {
            if ($line -match '^(.*)_SearchFlags=(.*)$') {
                $searchFlags[$matches[1]] = $matches[2] -split '\|'
            }
        }
        $recentFilterIds = @()
        foreach ($line in $lines) {
            if ($line -notmatch '^ColorFilter(\d+)=(.*)$') { continue }
            $filterId = $matches[1]
            $filter = $matches[2].Trim()
            $isRecent = $filter -match '(?i)(modified|changed|recent|newer)'
            if (-not $isRecent -and $filter.StartsWith('>')) {
                $savedSearch = $filter.Substring(1)
                if ($searchFlags.ContainsKey($savedSearch)) {
                    $parts = $searchFlags[$savedSearch]
                    $age = 0
                    $unit = 0
                    $isRecent = $parts.Count -gt 5 -and
                        [int]::TryParse($parts[4], [ref]$age) -and
                        [int]::TryParse($parts[5], [ref]$unit) -and
                        $age -ge 0 -and $unit -ge -1
                }
            }
            if ($isRecent) { $recentFilterIds += $filterId }
        }
        $recentFilterIds = @($recentFilterIds | Sort-Object -Unique)
        $recentFg = Convert-HexToBgr $t.link

        $newLines = @()
        $inColors = $false
        $colorsFound = $false
        $colorsDarkFound = $false

        foreach ($line in $lines) {
            if ($line -match '^\[Colors\]$') { $inColors = $true; $colorsFound = $true; $newLines += $line; continue }
            if ($line -match '^\[ColorsDark\]$') { $inColors = $true; $colorsDarkFound = $true; $newLines += $line; continue }
            if ($line -match '^\[') { $inColors = $false }
            if ($inColors -and $line -match '^(BackColor|BackColor2|ForeColor|MarkColor|CursorColor|CursorText|ActiveTitle|ActiveTitleText|InactiveTitle|InactiveTitleText)=') {
                continue
            }
            $newLines += $line
        }

        if (-not $colorsFound) { $newLines += '[Colors]' }
        if (-not $colorsDarkFound) { $newLines += '[ColorsDark]' }
        
        $finalLines = @()
        $inColors = $false
        foreach ($line in $newLines) {
            if ($line -match '^\[(Colors|ColorsDark)\]$') { $inColors = $true }
            elseif ($line -match '^\[') { $inColors = $false }
            if ($inColors -and $line -match '^ColorFilter(\d+)Color(Dark)?=') {
                $filterId = $matches[1]
                if ($filterId -in $recentFilterIds) {
                    if ($matches[2]) { $finalLines += "ColorFilter$($filterId)ColorDark=$recentFg,$recentFg" }
                    else { $finalLines += "ColorFilter$($filterId)Color=$recentFg" }
                    continue
                }
            }
            $finalLines += $line
            if ($line -match '^\[Colors\]$' -or $line -match '^\[ColorsDark\]$') {
                $finalLines += "BackColor=$bg"
                $finalLines += "BackColor2=$bg"
                $finalLines += "ForeColor=$fg"
                $finalLines += "MarkColor=$markFg"
                $finalLines += "CursorColor=$cursorBg"
                $finalLines += "CursorText=$cursorFg"
                $finalLines += "ActiveTitle=$titleBg"
                $finalLines += "ActiveTitleText=$titleFg"
                $finalLines += "InactiveTitle=$titleInBg"
                $finalLines += "InactiveTitleText=$titleInFg"
            }
        }
        Write-Utf8BomLines $ini $finalLines
        $recentNote = if ($recentFilterIds.Count) { "; recent-file indicator themed ($($recentFilterIds.Count) filter(s))" } else { '; no existing recent-file filter found' }
        Say "$($appName): applied $PaletteSlug$recentNote" 'Green'
        Set-ManifestEntry $manifestName $PaletteSlug $ini 'n/a' (Get-PayloadVersion)
    }
}

function Invoke-SmartVac {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $SmartVacPath 'SMART VAC CLEANER'
    if (-not (Test-Path $SmartVacPath)) { Say "SMART VAC CLEANER: not found at $SmartVacPath" 'DarkYellow'; return }
    
    $pyFile = Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py'
    $bakFile = Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py.bak'
    if (-not (Test-Path $pyFile)) { Say "SMART VAC CLEANER: _SMART_VAC_CLEANER.py not found" 'DarkYellow'; return }
    
    if ($DoRevert) {
        if (Test-Path $bakFile) {
            if ($PSCmdlet.ShouldProcess($pyFile, 'Restore SMART VAC CLEANER from backup')) {
                Copy-Item $bakFile $pyFile -Force
                Remove-Item $bakFile -Force
                Say "SMART VAC CLEANER: restored from backup" 'Green'
                Remove-ManifestEntry 'smartvac'
            }
        } else {
            Say "SMART VAC CLEANER: nothing to revert." 'DarkYellow'
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($pyFile, "Apply $PaletteSlug theme")) { return }
    
    Copy-Item $pyFile $bakFile -Force
    $json = (Read-Utf8 (Join-Path $root "themes/$PaletteSlug.json")) | ConvertFrom-Json
    $t = $json.tokens
    $code = Read-Utf8 $pyFile
    
    $code = $code -replace '(?m)^WIN95_BG\s*=\s*''[^'']+''', "WIN95_BG           = '$($t.background)'"
    $code = $code -replace '(?m)^WIN95_BG_SOFT\s*=\s*''[^'']+''', "WIN95_BG_SOFT      = '$($t.backgroundSoft)'"
    $code = $code -replace '(?m)^WIN95_SURFACE\s*=\s*''[^'']+''', "WIN95_SURFACE      = '$($t.surface)'"
    $code = $code -replace '(?m)^WIN95_SURFACE_RAISED\s*=\s*''[^'']+''', "WIN95_SURFACE_RAISED = '$($t.surfaceRaised)'"
    $code = $code -replace '(?m)^WIN95_SURFACE_ALT\s*=\s*''[^'']+''', "WIN95_SURFACE_ALT  = '$($t.surfaceAlt)'"
    $code = $code -replace '(?m)^WIN95_BEVEL_HI\s*=\s*''[^'']+''', "WIN95_BEVEL_HI     = '$($t.bevelLight)'"
    $code = $code -replace '(?m)^WIN95_BEVEL_SH\s*=\s*''[^'']+''', "WIN95_BEVEL_SH     = '$($t.borderDark)'"
    $code = $code -replace '(?m)^WIN95_BORDER_MUTED\s*=\s*''[^'']+''', "WIN95_BORDER_MUTED = '$($t.borderMuted)'"
    $code = $code -replace '(?m)^WIN95_TEXT\s*=\s*''[^'']+''', "WIN95_TEXT         = '$($t.textPrimary)'"
    $code = $code -replace '(?m)^WIN95_TEXT_DIM\s*=\s*''[^'']+''', "WIN95_TEXT_DIM     = '$($t.textSecondary)'"
    $code = $code -replace '(?m)^WIN95_TEXT_MUTED\s*=\s*''[^'']+''', "WIN95_TEXT_MUTED   = '$($t.textMuted)'"
    $code = $code -replace '(?m)^WIN95_GOLD\s*=\s*''[^'']+''', "WIN95_GOLD         = '$($t.textPrimary)'"
    $code = $code -replace '(?m)^WIN95_GOLD_LIGHT\s*=\s*''[^'']+''', "WIN95_GOLD_LIGHT   = '$($t.borderHighlight)'"
    $code = $code -replace '(?m)^WIN95_GOLD_DIM\s*=\s*''[^'']+''', "WIN95_GOLD_DIM     = '$($t.textSecondary)'"
    $code = $code -replace '(?m)^WIN95_GOLD_DARK\s*=\s*''[^'']+''', "WIN95_GOLD_DARK    = '$($t.textMuted)'"
    $code = $code -replace '(?m)^WIN95_RED\s*=\s*''[^'']+''', "WIN95_RED          = '$($t.danger)'"
    $code = $code -replace '(?m)^WIN95_DANGER\s*=\s*''[^'']+''', "WIN95_DANGER       = '$($t.danger)'"
    $code = $code -replace '(?m)^WIN95_GREEN\s*=\s*''[^'']+''', "WIN95_GREEN        = '$($t.success)'"
    $code = $code -replace '(?m)^WIN95_BUTTON\s*=\s*''[^'']+''', "WIN95_BUTTON       = '$($t.surfaceRaised)'"
    $code = $code -replace '(?m)^WIN95_BUTTON_HOVER\s*=\s*''[^'']+''', "WIN95_BUTTON_HOVER = '$($t.surfaceAlt)'"
    $code = $code -replace '(?m)^WIN95_ENTRY\s*=\s*''[^'']+''', "WIN95_ENTRY        = '$($t.background)'"
    $code = $code -replace '(?m)^WIN95_SCROLL\s*=\s*''[^'']+''', "WIN95_SCROLL       = '$($t.surfaceRaised)'"
    $code = $code -replace '(?m)^WIN95_SCROLL_HOVER\s*=\s*''[^'']+''', "WIN95_SCROLL_HOVER = '$($t.surfaceAlt)'"
    
    Write-Utf8 $pyFile $code
    Say "SMART VAC CLEANER: installed theme -> $pyFile" 'Green'
    Set-ManifestEntry 'smartvac' $PaletteSlug $pyFile 'n/a' (Get-PayloadVersion)
}

function Invoke-WildRift {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $WildRiftPath 'WildRiftAssistant'
    if (-not (Test-Path $WildRiftPath)) { Say "WildRiftAssistant: not found at $WildRiftPath" 'DarkYellow'; return }
    
    $pyFile = Join-Path $WildRiftPath 'theme.py'
    $bakFile = Join-Path $WildRiftPath 'theme.py.bak'
    if (-not (Test-Path $pyFile)) { Say "WildRiftAssistant: theme.py not found" 'DarkYellow'; return }
    
    if ($DoRevert) {
        if (Test-Path $bakFile) {
            if ($PSCmdlet.ShouldProcess($pyFile, 'Restore WildRiftAssistant from backup')) {
                Copy-Item $bakFile $pyFile -Force
                Remove-Item $bakFile -Force
                Say "WildRiftAssistant: restored from backup" 'Green'
                Remove-ManifestEntry 'wildrift'
            }
        } else {
            Say "WildRiftAssistant: nothing to revert." 'DarkYellow'
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($pyFile, "Apply $PaletteSlug theme")) { return }
    
    if (-not (Test-Path $bakFile)) {
        Copy-Item $pyFile $bakFile -Force
    }
    $json = (Read-Utf8 (Join-Path $root "themes/$PaletteSlug.json")) | ConvertFrom-Json
    $pyTokens = "TOKENS = {`r`n"
    foreach ($p in $json.tokens.psobject.properties) {
        $pyTokens += "    `"$($p.Name)`": `"$($p.Value)`",`r`n"
    }
    $pyTokens += "}"
    $code = Read-Utf8 $bakFile
    $code = $code -replace '(?s)TOKENS\s*=\s*\{.*?\}', $pyTokens
    Write-Utf8 $pyFile $code
    Say "WildRiftAssistant: installed theme -> $pyFile" 'Green'
    Set-ManifestEntry 'wildrift' $PaletteSlug $pyFile 'n/a' (Get-PayloadVersion)
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

function Invoke-Saipenview {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $SaipenviewPath 'SAIPENVIEW'
    if (-not (Test-Path $SaipenviewPath)) { Say "SAIPENVIEW: not found at $SaipenviewPath" 'DarkYellow'; return }
    
    $cssFile = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css'
    $bakFile = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css.bak'
    
    if ($DoRevert) {
        if (Test-Path $bakFile) {
            if ($PSCmdlet.ShouldProcess($cssFile, 'Restore SAIPENVIEW original CSS')) {
                Copy-Item $bakFile $cssFile -Force
                Remove-Item $bakFile -Force
                Say "SAIPENVIEW: restored from backup" 'Green'
                Remove-ManifestEntry 'saipenview'
            }
        } else {
            Say "SAIPENVIEW: nothing to revert." 'DarkYellow'
        }
        return
    }
    
    if (-not (Test-Path $cssFile)) { Say "SAIPENVIEW: CSS file not found ($cssFile)" 'DarkYellow'; return }
    
    if ($PSCmdlet.ShouldProcess($cssFile, "Recolour :root tokens to $PaletteSlug")) {
        # ─── THE BACKUP GOES STALE, AND A STALE BACKUP IS A TIME MACHINE ─────
        # Everything below recolours from $bakFile, never from the live file, so
        # a half-applied run cannot compound. That is right -- but only while the
        # backup is the SAME stylesheet as the live file, differing in colours.
        #
        # It stops being that the moment SAIPENVIEW ships new CSS. The backup is
        # taken once and never refreshed, so every later run rewrote style.css to
        # `<old snapshot> + new colours`, silently deleting whatever rules had
        # landed since -- the --dangerText token, the .conf-list collapse rule,
        # the whole Agent Panel block, the .bmac-btn rule. SAIPENVIEW logged it
        # three times as CSS that "regenerates itself" to a byte-identical file
        # matching no commit in its history (its T-135/T-137). It matched no
        # commit because it was assembled here.
        #
        # So: compare the SHAPE of the two files -- everything except the colour
        # values this patch is allowed to change -- and re-take the backup when
        # they differ. The old one is kept beside it rather than dropped, since
        # it is the only copy of a pre-theme file if the user ever had one.
        if (Test-Path $bakFile) {
            if ((Get-CssShape (Read-Utf8 $bakFile)) -ne (Get-CssShape (Read-Utf8 $cssFile))) {
                Copy-Item $bakFile "$bakFile.stale" -Force
                Copy-Item $cssFile $bakFile -Force
                Say "SAIPENVIEW: style.css has changed since the backup was taken - backup refreshed (previous kept as style.css.bak.stale)" 'DarkYellow'
            }
        } else {
            Copy-Item $cssFile $bakFile -Force
        }

        # Do NOT append the browser stylesheet here. That was the previous approach and
        # it is why the text moved: wintage.css is written for arbitrary web pages, so it
        # carries universal selectors that force font-family, the 10/12/14/16 size ladder,
        # 2px border widths and control min-heights. Dropped on top of SAIPENVIEW's own
        # CSS it rewrites the box model of every element, and the layout shifts.
        #
        # SAIPENVIEW already declares the Wintage token names in its own :root, so the
        # correct patch is to rewrite the token VALUES and nothing else -- no selector,
        # no font, no padding, no border width. Colours change, geometry cannot.
        $jsonPath = Join-Path $root "themes\$PaletteSlug.json"
        if (-not (Test-Path $jsonPath)) { Say "SAIPENVIEW: theme file not found ($PaletteSlug.json)" 'Red'; return }
        $t = Get-PaletteTokens $jsonPath

        # Always recolour from the pristine backup, never from the current file: patching
        # an already-patched file is fine here (the regex is idempotent) but starting from
        # the original keeps a half-applied run from compounding.
        # Read and write as UTF-8 WITHOUT a BOM, explicitly. PowerShell 5.1's
        # Get-Content -Raw falls back to the ANSI codepage when a file has no BOM, so
        # style.css's em-dashes came back as three cp1251 characters each and were
        # written out as that mojibake -- and Set-Content -Encoding UTF8 adds a BOM on
        # top, which then shows up as a stray glyph before `:root`. Caught by diffing
        # the patched file against the backup: 30-odd comment lines had changed that
        # this patch has no business touching.
        $text = Read-Utf8 $bakFile
        $applied = @(); $missing = @()
        foreach ($k in $t.PSObject.Properties.Name) {
            $pattern = "(--$k\s*:\s*)#[0-9A-Fa-f]{6}"
            if ($text -cmatch $pattern) {
                $text = [regex]::Replace($text, $pattern, "`${1}$($t.$k)")
                $applied += $k
            } else { $missing += $k }
        }

        # ─── ONE RED CANNOT DO BOTH JOBS ────────────────────────────────────
        # SAIPENVIEW spends --danger two ways: as a FILL (.phase-BLOCKED, the error
        # badge) where a dark red is right and the label on top is light, and as
        # TEXT (.conf-badge.fail, .blocker, toast-error) where the same dark red on
        # a dark surface measures 1.9:1 and is simply unreadable -- reported as the
        # FAIL badges being illegible. Lightening --danger does not fix it, it moves
        # the problem: the fills then wash out under their own light labels.
        #
        # So the split is made here, by PROPERTY rather than by selector. `color:`
        # and `border-color:` are the roles that must be legible against a backdrop;
        # `background:` is the one that must not be. That rule needs no list of
        # selectors to maintain and keeps working when SAIPENVIEW adds rules of its
        # own -- and it stays inside this patch's one law, that colours may change
        # and geometry may not. Not a single selector, width or padding is touched.
        #
        # --dangerText is declared right after --danger rather than edited into
        # SAIPENVIEW's source, so style.css.bak stays a byte-exact original and
        # -Revert still restores the file the user actually had.
        if ($t.dangerText) {
            $text = [regex]::Replace($text, "(--danger\s*:\s*#[0-9A-Fa-f]{6}\s*;)", "`${1} --dangerText:$($t.dangerText);")
            $text = [regex]::Replace($text, "(?<=(?:^|[;{]\s*|\s)color\s*:\s*)var\(--danger\)", "var(--dangerText)")
            $text = [regex]::Replace($text, "(?<=border-color\s*:\s*)var\(--danger\)", "var(--dangerText)")
            $applied += 'dangerText'
            $missing = @($missing | Where-Object { $_ -ne 'dangerText' })
        }

        Write-Utf8 $cssFile $text

        Say "SAIPENVIEW: recoloured $($applied.Count) tokens to $PaletteSlug - colours only, layout untouched" 'Green'
        Set-ManifestEntry 'saipenview' $PaletteSlug $cssFile 'n/a' (Get-PayloadVersion)
        if ($missing.Count) {
            # Reported, not silently dropped: a token SAIPENVIEW does not declare is a
            # gap in coverage the next person should know about.
            Say "  not declared in SAIPENVIEW's :root, left alone: $($missing -join ', ')" 'DarkGray'
        }
        Say "  Reload the SAIPENVIEW window to see it." 'DarkGray'
    }
}

function Invoke-BetterDiscord {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $bdDir = Join-Path $env:APPDATA 'BetterDiscord/themes'
    $bdCss = Join-Path $bdDir 'wintage.theme.css'
    
    if (-not (Test-Path $bdDir)) { Say "BetterDiscord: not installed (no BetterDiscord/themes)" 'DarkYellow'; return }

    if ($DoRevert) {
        if (Test-Path $bdCss) {
            if ($PSCmdlet.ShouldProcess($bdCss, 'Remove Wintage theme')) {
                Remove-Item $bdCss -Force
                Say "BetterDiscord: removed $bdCss" 'Green'
                Remove-ManifestEntry 'discord'
            }
        } else { Say "BetterDiscord: nothing installed, nothing to revert." }
        return
    }

    if ($PSCmdlet.ShouldProcess($bdCss, 'Install Wintage theme')) {
        $css = Read-Utf8 (Join-Path $out "electron/$PaletteSlug/wintage.css")
        $meta = "/**`n * @name Wintage ($PaletteSlug)`n * @author Wintage Installer`n * @version 1.0.0`n * @description Win95 Theme`n */`n`n"
        Write-Utf8 $bdCss ($meta + $css)
        Say "BetterDiscord: installed theme -> $bdCss" 'Green'
        Set-ManifestEntry 'discord' $PaletteSlug $bdCss 'n/a' (Get-PayloadVersion)
    }
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

function Invoke-Obsidian {
    param([switch]$DoRevert, [string]$PaletteSlug)

    $vaults = Get-ObsidianVaults
    if (-not $vaults) { Say 'Obsidian: no vaults found (no obsidian.json) - skipped.' 'DarkYellow'; return }

    $builtRoot = Join-Path $out 'obsidian'
    if (-not (Test-Path $builtRoot)) { throw "Built Obsidian output missing. Run 'node tools/build-desktop.js'." }
    # The active theme's display name comes from the built manifest for that slug, so
    # it always matches the folder name Obsidian will look for -- never guessed.
    $activeManifest = Join-Path $builtRoot "$PaletteSlug/manifest.json"
    if (-not (Test-Path $activeManifest)) { throw "No Obsidian build for palette '$PaletteSlug'." }
        $activeName = (Read-Utf8 $activeManifest | ConvertFrom-Json).name

    foreach ($vault in $vaults) {
        $themesDir = Join-Path $vault '.obsidian/themes'
        $appearance = Join-Path $vault '.obsidian/appearance.json'

        if ($DoRevert) {
            # Only Wintage-* theme folders are removed; a hand-made theme in the same
            # vault (the user's own VintageWin95) is never touched.
            if (Test-Path $themesDir) {
                Get-ChildItem $themesDir -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove Wintage theme')) { Remove-Item $_.FullName -Recurse -Force }
                }
                # Restore the previous theme choice, so revert does not leave cssTheme
                # pointing at a folder that no longer exists.
                $safe = ($vault -replace '[^A-Za-z0-9]', '_')
                $bak = Join-Path $here "backup/obsidian-appearance-$safe.json"
                if ((Test-Path $bak) -and (Test-Path $appearance)) { Copy-Item $bak $appearance -Force }
                Say "Obsidian: removed Wintage themes from $vault" 'Green'
                Remove-ManifestEntry 'obsidian'
            }
            continue
        }

        if ($PSCmdlet.ShouldProcess($vault, "Install all Wintage themes, activate $PaletteSlug")) {
            New-Item -ItemType Directory -Force -Path $themesDir | Out-Null
            foreach ($pack in (Get-ChildItem $builtRoot -Directory)) {
                $manifest = Read-Utf8 (Join-Path $pack.FullName 'manifest.json') | ConvertFrom-Json
                $dest = Join-Path $themesDir $manifest.name
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Copy-Item (Join-Path $pack.FullName '*') -Destination $dest -Recurse -Force
            }
            $count = (Get-ChildItem $builtRoot -Directory).Count
            # Set the chosen palette active, backing appearance.json up first so the
            # user's previous theme choice is recoverable.
            if (Test-Path $appearance) {
                $bakDir = Join-Path $here 'backup'
                New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
                $safe = ($vault -replace '[^A-Za-z0-9]', '_')
                $bak = Join-Path $bakDir "obsidian-appearance-$safe.json"
                if (-not (Test-Path $bak)) { Copy-Item $appearance $bak -Force }
                $ap = (Read-Utf8 $appearance) | ConvertFrom-Json
                $ap | Add-Member -NotePropertyName cssTheme -NotePropertyValue $activeName -Force
                Write-Utf8 $appearance ($ap | ConvertTo-Json -Depth 10)
            }
            Say "Obsidian: installed $count themes into $vault, active '$activeName'" 'Green'
            Say "  Reload the vault (Ctrl+R) or Settings > Appearance to see it." 'DarkGray'
            Set-ManifestEntry 'obsidian' $PaletteSlug $themesDir 'n/a' (Get-PayloadVersion)
        }
    }
}

$OBS_CONFIG = Join-Path $env:APPDATA 'obs-studio'
$OBS_THEME_ID = 'com.wintage.OBS'

function Invoke-Obs {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not (Test-Path $OBS_CONFIG)) { Say 'OBS Studio: not installed (no obs-studio profile) - skipped.' 'DarkYellow'; return }
    if (Get-Process obs64 -ErrorAction SilentlyContinue) {
        Say 'OBS Studio: close OBS and Apply again so it cannot overwrite user.ini on exit.' 'Yellow'
        return
    }
    if (-not $node) { Say 'OBS Studio: node is required to patch user.ini safely - skipped.' 'Yellow'; return }

    $helper = Join-Path $root 'tools/install-obs.js'
    $theme = Join-Path $out "obs/$PaletteSlug/Wintage.ovt"
    if (-not $DoRevert -and -not (Test-Path $theme)) { throw "No OBS build for palette '$PaletteSlug'." }
    $args = @($helper, '--config', $OBS_CONFIG)
    if ($DoRevert) { $args += '--revert' } else { $args += @('--theme', $theme, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore previous OBS theme and selection' } else { "Install and activate Wintage $PaletteSlug" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); return }
    if ($PSCmdlet.ShouldProcess($OBS_CONFIG, $action)) {
        & node $args
        if ($LASTEXITCODE -ne 0) { throw 'OBS Studio theme patch failed.' }
        if ($DoRevert) { Remove-ManifestEntry 'obs' }
        else { Set-ManifestEntry 'obs' $PaletteSlug $OBS_CONFIG 'n/a' (Get-PayloadVersion) }
    }
}

function Invoke-MpcHc {
    param([switch]$DoRevert)

    if (-not (Test-Path $MPC_KEY)) { Say 'MPC-HC: not installed on this machine - skipped.' 'DarkYellow'; return }

    $bakDir = Join-Path $here 'backup'
    $bak = Join-Path $bakDir 'mpc-hc-settings.reg'

    if ($DoRevert) {
        if (-not (Test-Path $bak)) { Say 'MPC-HC: no backup to restore from.' 'DarkYellow'; return }
        if ($PSCmdlet.ShouldProcess($MPC_REG, "Restore from $bak")) {
            # reg import merges; it restores the values that were captured and leaves
            # anything created since. That is the honest limit of a .reg backup and
            # it is stated rather than glossed.
            & reg import $bak 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "MPC-HC: reg import failed ($LASTEXITCODE) -- values not restored." }
            Say "MPC-HC: restored the captured values from $bak" 'Green'
            Remove-ManifestEntry 'mpchc'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($MPC_REG, 'Back up and apply the Wintage/UI.md settings')) {
        New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
        if (-not (Test-Path $bak)) {
            & reg export $MPC_REG $bak /y 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "MPC-HC: reg export failed ($LASTEXITCODE) -- backup not created, revert will be unavailable." }
            else { Say "MPC-HC: settings backed up to $bak" 'DarkGray' }
        }
        else { Say "MPC-HC: keeping the existing backup at $bak (it holds the pre-Wintage state)" 'DarkGray' }

        # MPCTheme 1 = the dark UI. ModernThemeMode 2 = dark title bar too.
        # OSD: Verdana per UI.md law 1, a size on its ladder, zero transparency
        # (law 2 forbids it outright), and a border so it reads as a raised surface.
        $vals = @{
            MPCTheme         = 1
            ModernThemeMode  = 2
            OSDFont          = 'Verdana'
            OSDSize          = 16
            OSDTransparency  = 0
            OSDBorder        = 1
            TitleBarTextStyle = 1
        }
        foreach ($k in $vals.Keys) {
            $type = if ($vals[$k] -is [string]) { 'String' } else { 'DWord' }
            Set-ItemProperty -Path $MPC_KEY -Name $k -Value $vals[$k] -Type $type
        }
        Say 'MPC-HC: dark theme on, OSD set to Verdana 16, zero transparency, bordered.' 'Green'
        Set-ManifestEntry 'mpchc' 'n/a' $MPC_KEY 'n/a' (Get-PayloadVersion)
        Say '  NOT reachable: the player chrome colours are compiled into MPC-HC and no' 'Yellow'
        Say '  registry value exposes them, so this target cannot take a palette. Only the' 'Yellow'
        Say '  built-in dark theme and the OSD typography are settable.' 'Yellow'
        Say '  MPC-HC rewrites these on exit - close it BEFORE applying, or re-apply after.' 'Yellow'
    }
}

# Resolved BEFORE the listing, not after: the listing reads Electron fuses through
# node, and when this lived below it, $node was still empty there -- so every app
# silently reported "not themed" instead of "fused shut", which is the one line in
# the table a user actually needs when an app refuses to start.
$node = Get-Command node -ErrorAction SilentlyContinue

# Resolve source-tree paths from paths.json when not passed on the command line.
# The GUI writes remembered paths there; the CLI consults the same file so a path
# entered once is available to every install.ps1 invocation without repeating it.
$pathsJson = Read-PathsJson
if (-not $SaipenviewPath -and $pathsJson.ContainsKey('saipenview')) { $SaipenviewPath = $pathsJson['saipenview'] }
if (-not $SmartVacPath -and $pathsJson.ContainsKey('smartvac')) { $SmartVacPath = $pathsJson['smartvac'] }
if (-not $WildRiftPath -and $pathsJson.ContainsKey('wildrift')) { $WildRiftPath = $pathsJson['wildrift'] }
if (-not $CodeNomadPath -and $pathsJson.ContainsKey('codenomad')) { $CodeNomadPath = $pathsJson['codenomad'] }
if (-not $PortableBrowserRoot -and $pathsJson.ContainsKey('portable')) { $PortableBrowserRoot = $pathsJson['portable'] }

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

# ---- Reapply mode: read manifest, rediscover paths, re-apply outdated payloads ----
if ($Reapply) {
    $currentVer = Get-PayloadVersion
    $manifest = Read-Manifest
    if ($manifest.Count -eq 0) { Say 'Nothing to do -- the manifest is empty (no targets have been installed).' 'Green'; exit 0 }
    $didWork = $false
    $passArgs = @{}
    if ($CodeNomadPath) { $passArgs['-CodeNomadPath'] = $CodeNomadPath }
    if ($TotalCmdIni)  { $passArgs['-TotalCmdIni'] = $TotalCmdIni }
    if ($TotalCmd2Ini) { $passArgs['-TotalCmd2Ini'] = $TotalCmd2Ini }
    if ($SaipenviewPath) { $passArgs['-SaipenviewPath'] = $SaipenviewPath }
    if ($SmartVacPath) { $passArgs['-SmartVacPath'] = $SmartVacPath }
    if ($WildRiftPath) { $passArgs['-WildRiftPath'] = $WildRiftPath }
    if ($Force) { $passArgs['-Force'] = $Force }
    if ($PortableBrowserRoot) { $passArgs['-PortableBrowserRoot'] = $PortableBrowserRoot }
    if ($BrowserStageRoot) { $passArgs['-BrowserStageRoot'] = $BrowserStageRoot }
    $sorted = @($manifest.Keys | Sort-Object)
    foreach ($key in $sorted) {
        $data = $manifest[$key]
        if ($data.payloadVersion -ge $currentVer) {
            if (-not $Quiet) { Say "$key`: up to date (manifest v$($data.payloadVersion), repo v$currentVer)." 'DarkGray' }
            continue
        }
        $action = "Re-apply $key @ $($data.palette) (v$($data.payloadVersion) -> v$currentVer)"
        if (-not $PSCmdlet.ShouldProcess("$key ($($data.palette))", $action)) { continue }
        $didWork = $true
        $callArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
            '-Target', $key, '-Palette', $data.palette)
        foreach ($pk in $passArgs.Keys) { $callArgs += $pk; $callArgs += $passArgs[$pk] }
        if ($WhatIfPreference) { $callArgs += '-WhatIf' }
        if (-not $Quiet) { Say "$key`: re-applying $($data.palette) ..." 'Cyan' }
        $result = & powershell @callArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            if (-not $Quiet) { Say "$key`: re-applied successfully." 'Green' }
        }
        else { Say "$key`: FAILED ($LASTEXITCODE)." 'Red'; Write-Warning ($result -join "`n") }
    }
    if (-not $didWork) {
        if (-not $Quiet) { Say 'Nothing to do -- all recorded targets are up to date.' 'Green' }
    }
    exit 0
}

if ($RegisterLogonTask) { Register-WintageLogonTask; exit 0 }
if ($UnregisterLogonTask) { Unregister-WintageLogonTask; exit 0 }

if ($Status) {
    $manifest = Read-Manifest
    if ($manifest.Count -eq 0) { Say 'Nothing installed -- the manifest is empty.' 'Green'; exit 0 }
    Say ('{0,-14} {1,-18} {2,-17} {3}' -f 'target', 'palette', 'payload ver', 'path') 'DarkGray'
    $sorted = @($manifest.Keys | Sort-Object)
    foreach ($key in $sorted) {
        $d = $manifest[$key]
        $pal = if ($d.palette) { $d.palette } else { '-' }
        $ver = if ($d.payloadVersion) { $d.payloadVersion } else { '-' }
        $path = if ($d.path) { $d.path } else { '-' }
        Say ('{0,-14} {1,-18} {2,-17} {3}' -f $key, $pal, $ver, $path)
    }
    exit 0
}

if (-not $Target) {
    # The whole point of the listing is answering three questions at once: is the app
    # here, is it themed, and WHICH palette is on it. Without the third column,
    # "which one did I put on Freebuff again" has no answer short of reading JSON.
    $palettes = (Get-ChildItem (Join-Path $root 'themes') -Filter '*.json' | ForEach-Object { $_.BaseName }) -join '|'

    Say (T 'ListingHeader') 'Cyan'
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f (T 'ColTarget'), (T 'ColApp'), (T 'ColState'), (T 'ColPalette')) 'DarkGray'

    foreach ($k in $TARGETS.Keys | Sort-Object) {
        $t = $TARGETS[$k]
        $dest = Join-Path $t.Dir 'wintage-themes'
        $state = if (-not (Test-Path $t.Dir)) { 'not installed' }
                 elseif (Test-Path $dest) { 'themed' }
                 else { 'found, not themed' }
        # A VS Code target carries EVERY palette at once and the user picks in the
        # editor, so naming one here would be a lie.
        $pal = if (Test-Path $dest) { 'all (pick in the editor)' } else { '-' }
        Say ("  {0,-16} {1,-38} {2,-22} {3}" -f $k, $t.Name, $state, $pal)
    }

    foreach ($k in $ELECTRON.Keys | Sort-Object) {
        $e = $ELECTRON[$k]
        # A resolver that found nothing hands back $null, and Join-Path THROWS on a
        # null path rather than returning one -- so the whole listing died on the
        # first machine that did not have one of these apps. An absent app must read
        # as a row saying "not installed", never as a terminating error.
        $pkg = if ($e.Resources) { Join-Path $e.Resources 'app/package.json' } else { $null }
        $blocked = $null
        if (Test-ElectronApp $e.Resources) {
            $exe = Get-ChildItem (Split-Path $e.Resources -Parent) -Filter '*.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^(Uninstall|elevate|Squirrel|Update)' } |
                Sort-Object Length -Descending | Select-Object -First 1
            if ($exe -and $node) {
                $fuse = & node (Join-Path $root 'tools/electron-fuses.js') $exe.FullName 2>$null
                if ($fuse -match 'NOT themeable') { $blocked = 'fused shut' }
            }
        }
        # An IN-PLACE target writes no package.json of its own, so asking for one
        # reported Claude as unthemed while it was in fact patched and running -- the
        # exact question this column exists to answer, wrong on the one target that
        # uses the other mode. Each mode is asked for its own evidence.
        $palFile = if ($e.Resources) { Join-Path $e.Resources 'wintage-palette.txt' } else { $null }
        $themed = if ($e.InPlace) { $palFile -and (Test-Path $palFile) } else { $pkg -and (Test-Path $pkg) }
        $state = if (-not (Test-ElectronApp $e.Resources)) { 'not installed' }
                 elseif ($blocked) { $blocked }
                 elseif ($themed) { 'themed' }
                 else { 'found, not themed' }
        $pal = if (-not $themed) { '-' }
               elseif ($e.InPlace) { (Read-Utf8 $palFile).Trim() }
               else { (Read-Utf8 $pkg | ConvertFrom-Json).wintagePalette }
        Say ("  {0,-16} {1,-38} {2,-22} {3}" -f $k, $e.Name, $state, $pal)
    }

    $mpc = if (Test-Path $MPC_KEY) {
        if ((Get-ItemProperty $MPC_KEY).OSDFont -eq 'Verdana') { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'mpchc', 'MPC-HC (K-Lite)', $mpc, 'n/a - colours are compiled in')

    $windowsPal = if (Test-Path $WINDOWS_THEME_MARKER) { (Read-Utf8 $WINDOWS_THEME_MARKER).Trim() } else { $null }
    $windows = if ($windowsPal) { 'themed' } else { 'found, not themed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'windows', 'Windows system theme', $windows, $(if ($windowsPal) { $windowsPal } else { '-' }))

    $terminalPaths = @(Get-WindowsTerminalSettingsPaths)
    $terminalMarkers = @($terminalPaths | ForEach-Object { $_ + '.wintage-palette' } | Where-Object { Test-Path $_ })
    $terminal = if (-not $terminalPaths.Count) { 'not installed' }
                elseif ($terminalMarkers.Count -eq $terminalPaths.Count) { 'themed' }
                else { 'found, not themed' }
    $terminalPal = if ($terminalMarkers.Count) {
        (@($terminalMarkers | ForEach-Object { (Read-Utf8 $_).Trim() } | Sort-Object -Unique) -join '|')
    } else { '-' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'terminal', "Windows Terminal ($($terminalPaths.Count) install(s))", $terminal, $terminalPal)

    $conhostPalette = if (Test-Path $CONHOST_KEY) { (Get-ItemProperty $CONHOST_KEY -Name WintagePalette -ErrorAction SilentlyContinue).WintagePalette } else { $null }
    $conhost = if (-not (Test-Path $CONHOST_KEY)) { 'not installed' }
               elseif ($conhostPalette) { 'themed' }
               else { 'found, not themed' }
    $conhostPal = if ($conhostPalette) { $conhostPalette } else { '-' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'conhost', 'Console Host (cmd / PowerShell)', $conhost, $conhostPal)

    $obsUser = Join-Path $OBS_CONFIG 'user.ini'
    $obsTheme = Join-Path $OBS_CONFIG 'themes/Wintage.ovt'
    $obsMarker = Join-Path $OBS_CONFIG '.wintage-obs-palette'
    $obs = if (-not (Test-Path $OBS_CONFIG)) { 'not installed' }
           elseif ((Test-Path $obsTheme) -and (Test-Path $obsMarker) -and
                   (Test-Path $obsUser) -and ((Read-Utf8 $obsUser) -match "(?m)^\s*Theme=$([regex]::Escape($OBS_THEME_ID))\s*$")) { 'themed' }
           else { 'found, not themed' }
    $obsPal = if (Test-Path $obsMarker) { (Read-Utf8 $obsMarker).Trim() } else { '-' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'obs', 'OBS Studio', $obs, $obsPal)

    $browserTool = Join-Path $root 'tools/install-browsers.ps1'
    $browserArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $browserTool, '-ListJson', '-StageRoot', $BrowserStageRoot)
    if ($PortableBrowserRoot) { $browserArgs += @('-PortableRoot', $PortableBrowserRoot) }
    if ($BrowserCatalog) { $browserArgs += @('-Catalog', $BrowserCatalog) }
    $browserInfo = (& powershell @browserArgs 2>$null | Out-String).Trim() | ConvertFrom-Json
    $browserState = if (-not $browserInfo.ProfileCount) { 'not installed' }
                    elseif ($browserInfo.ThemeLoadedCount -eq $browserInfo.ProfileCount) { 'themed' }
                    else { 'found, not themed' }
    $browserName = "Chromium browsers ($($browserInfo.ProfileCount)p/TM$($browserInfo.TampermonkeyCount))"
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'browsers', $browserName, $browserState, $browserInfo.Palette)

    Say ""

    $svCss = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css'
    $svBak = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css.bak'
    $sv = if (Test-Path $SaipenviewPath) {
        if (Test-Path $svBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'saipenview', 'SAIPENVIEW', $sv, '-')

    $smBak = Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py.bak'
    $sm = if (Test-Path $SmartVacPath) {
        if (Test-Path $smBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'smartvac', 'SMART VAC CLEANER', $sm, '-')

    $wrBak = Join-Path $WildRiftPath 'theme.py.bak'
    $wr = if (Test-Path $WildRiftPath) {
        if (Test-Path $wrBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'wildrift', 'WildRiftAssistant', $wr, '-')

    $bdDir = Join-Path $env:APPDATA 'BetterDiscord/themes'
    $bdCss = Join-Path $bdDir 'wintage.theme.css'
    $bd = if (Test-Path $bdDir) {
        if (Test-Path $bdCss) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'discord', 'BetterDiscord', $bd, '-')

    $tc1Dir = Join-Path $env:APPDATA 'GHISLER'
    $tc1Ini = Join-Path $tc1Dir 'wincmd.ini'
    $tc1 = if (Test-Path $tc1Ini) {
        if ((Read-Utf8 $tc1Ini) -match "ActiveTitleText=") { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'totalcmd', 'Total Commander', $tc1, '-')

    $tc2Dir = Join-Path $env:LOCALAPPDATA 'GHISLER'
    $tc2Ini = Join-Path $tc2Dir 'wincmd.ini'
    $tc2 = if (Test-Path $tc2Ini) {
        if ((Read-Utf8 $tc2Ini) -match "ActiveTitleText=") { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'totalcmd2', 'Total Commander (Local)', $tc2, '-')

    $obsVaults = Get-ObsidianVaults
    $obs = if ($obsVaults) {
        $anyThemed = $false
        foreach ($v in $obsVaults) { if (Get-ChildItem (Join-Path $v '.obsidian/themes') -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue) { $anyThemed = $true } }
        if ($anyThemed) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'obsidian', ('Obsidian (' + $obsVaults.Count + ' vault(s))'), $obs, 'all (pick in Appearance)')

    Say ((T 'PalettesLabel') + " $palettes") 'DarkGray'
    Say (T 'HelpOneApp') 'Cyan'
    Say (T 'HelpAll') 'Cyan'
    Say (T 'HelpRevert') 'Cyan'
    Say (T 'RepaintNote') 'DarkGray'
    return
}

# The built output is generated, not committed by hand -- refuse to install a stale
# or missing build rather than silently shipping last week's colours.
if ($node) {
    & node (Join-Path $root 'tools/build-desktop.js') --check 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (-not $Force) { throw (T 'BuildStale') }
        Say (T 'BuildStaleForce') 'Yellow'
    }
}
elseif (-not $Force) {
    Say (T 'NodeNotFoundBuild') 'Yellow'
}

# Every target that is neither a VS Code extension nor an Electron app -- i.e. one
# with its own Invoke-* handler. Declared ONCE, because the hand-kept version of
# this list silently dropped five targets: codenomad, discord, totalcmd, totalcmd2
# and obsidian were all reachable individually but were skipped by `-Target all`,
# so "everything" quietly meant nine of fourteen.
$SIMPLE = @('windows', 'browsers', 'mpchc', 'terminal', 'conhost', 'obs', 'saipenview', 'smartvac', 'wildrift', 'discord', 'totalcmd', 'totalcmd2', 'obsidian')

# And this is the guard that stops it happening a third time: the parameter's own
# ValidateSet is the definition of what a user may ask for, so anything in it that
# no dispatch list covers is a target `-Target all` would skip. Checked at startup
# rather than trusted, because the drift is invisible until someone counts.
$known = @($TARGETS.Keys) + @($ELECTRON.Keys) + $SIMPLE
$declared = (Get-Command $PSCommandPath).Parameters['Target'].Attributes |
    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
    Select-Object -First 1 -ExpandProperty ValidValues
$orphans = @($declared | Where-Object { $_ -ne 'all' -and $known -notcontains $_ })
if ($orphans.Count) {
    Say ((T 'SkippedByTargets') -f ($orphans -join ', ')) 'Yellow'
}

$names = if ($Target -eq 'all') { $known } else { @($Target) }

foreach ($name in $names) {

    if ($name -eq 'windows') { Invoke-WindowsTheme -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'browsers') {
        $browserTool = Join-Path $root 'tools/install-browsers.ps1'
        $browserArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $browserTool, '-Palette', $Palette, '-StageRoot', $BrowserStageRoot)
        if ($PortableBrowserRoot) { $browserArgs += @('-PortableRoot', $PortableBrowserRoot) }
        if ($BrowserCatalog) { $browserArgs += @('-Catalog', $BrowserCatalog) }
        if ($NoBrowserLaunch) { $browserArgs += '-NoLaunch' }
        if ($Revert) { $browserArgs += '-Revert' }
        if ($WhatIfPreference) { $browserArgs += '-WhatIf' }
        & powershell @browserArgs
        if ($LASTEXITCODE -ne 0) { throw 'Browser theme installer failed.' }
        if ($Revert) { Remove-ManifestEntry 'browsers' }
        else { Set-ManifestEntry 'browsers' $Palette $BrowserStageRoot 'n/a' (Get-PayloadVersion) }
        continue
    }
    if ($name -eq 'mpchc') { Invoke-MpcHc -DoRevert:$Revert; continue }
    if ($name -eq 'terminal') { Invoke-WindowsTerminal -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'conhost') { Invoke-Conhost -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'obs') { Invoke-Obs -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'saipenview') { Invoke-Saipenview -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'smartvac') { Invoke-SmartVac -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'wildrift') { Invoke-WildRift -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'discord') { Invoke-BetterDiscord -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd') { Invoke-TotalCmd -Index 1 -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd2') { Invoke-TotalCmd -Index 2 -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'obsidian') { Invoke-Obsidian -DoRevert:$Revert -PaletteSlug $Palette; continue }

                # ---- Electron targets ----
    if ($ELECTRON.ContainsKey($name)) {
        $e = $ELECTRON[$name]
        if ($name -eq 'codenomad') { Remove-DeadCodeNomadCss }
        if (-not (Test-ElectronApp $e.Resources)) {
            Say "$($e.Name): not installed on this machine - skipped." 'DarkYellow'
            continue
        }
        if (-not $node) { Say "$($e.Name): needs node to read the app's package.json out of app.asar - skipped." 'Yellow'; continue }

        $script = Join-Path $root 'tools/install-electron.js'
        $nodeArgs = @($script, '--resources', $e.Resources)
        if ($e.InPlace) { $nodeArgs += '--in-place' }
        
        if ($Revert) {
            if ($PSCmdlet.ShouldProcess($e.Resources, 'Remove the Wintage shim')) {
                & node $nodeArgs --revert
                if ($LASTEXITCODE -eq 0) { Remove-ManifestEntry $name }
            }
            continue
        }
        $action = "Install Wintage ($Palette) shim"
        if ($WhatIfPreference) { & node $nodeArgs --palette $Palette --dry-run; continue }
        if ($PSCmdlet.ShouldProcess($e.Resources, $action)) {
            & node $nodeArgs --palette $Palette
            if ($LASTEXITCODE -ne 0) { Say "$($e.Name): FAILED - see the message above." 'Red' }
            else {
                # FreeBuff ships its own ad network (renderer + orchestrator routes).
                # The shim themes it; this cuts the ads out of the bundle and routes.
                # A custom completion sound is a per-machine preference written by
                # the GUI (WintageInstaller.ps1 -> %APPDATA%\Wintage\freebuff-sound.txt):
                # if one is set, hand it to the same patch run so the ads and the
                # sound are applied together. The patch keeps the stock file as
                # chime-*.mp3.bak and --revert restores it.
                if ($name -eq 'freebuff') {
                    $adPatch = Join-Path $root 'desktop/patch-freebuff-ads.js'
                    if (Test-Path $adPatch) {
                        if ($PSCmdlet.ShouldProcess($e.Resources, 'Cut FreeBuff ads')) {
                            $patchArgs = @()
                            $soundPref = Join-Path $env:APPDATA 'Wintage\freebuff-sound.txt'
                            if (Test-Path $soundPref) {
                                $wav = (Read-Utf8 $soundPref).Trim()
                                if ($wav -and (Test-Path $wav)) { $patchArgs = @('--sound', $wav) }
                            }
                            & node $adPatch @patchArgs
                            if ($LASTEXITCODE -ne 0) { Say 'FreeBuff ads: FAILED - bundle strings may have changed; run patch-freebuff-ads.js --scan to see what this build carries, then update the strings.' 'Red' }
                        }
                    }
                }
                Say "  Restart $($e.Name) to see it. Undo: .\install.ps1 -Target $name -Revert" 'DarkGray'
                $appVer = 'n/a'
                try {
                    $verOut = & node $nodeArgs --version 2>$null
                    if ($LASTEXITCODE -eq 0 -and $verOut) { $appVer = $verOut.Trim() }
                } catch {}
                Set-ManifestEntry $name $Palette $e.Resources $appVer (Get-PayloadVersion)
                Say "  Recorded in $ManifestPath" 'DarkGray'
            }
        }
        continue
    }

    $t = $TARGETS[$name]

    if (-not (Test-Path $t.Dir)) {
        Say "$($t.Name): extensions directory not found ($($t.Dir)) - skipped." 'DarkYellow'
        continue
    }

    $dest = Join-Path $t.Dir 'wintage-themes'

    if ($Revert) {
        if (Test-Path $dest) {
            if ($PSCmdlet.ShouldProcess($dest, 'Remove installed Wintage themes')) {
                Remove-Item $dest -Recurse -Force
                Say "$($t.Name): removed $dest" 'Green'
                Remove-ManifestEntry $name
            }
        }
        else { Say "$($t.Name): nothing installed, nothing to revert." }
        continue
    }

    if (-not (Test-Path $t.Built)) { throw "Built output missing: $($t.Built). Run 'node tools/build-desktop.js'." }

    # Replacing a directory wholesale is how a stale theme file from a previous
    # version survives forever, so the old one is removed - but only after it has
    # been copied out, because "the installer ate my hand-edited theme" is exactly
    # the failure a backup exists for.
    if (Test-Path $dest) {
        if ($PSCmdlet.ShouldProcess($dest, "Back up to $backupRoot and replace")) {
            $bak = Join-Path $backupRoot $name
            New-Item -ItemType Directory -Force -Path $bak | Out-Null
            Copy-Item $dest -Destination $bak -Recurse -Force
            Remove-Item $dest -Recurse -Force
            Say "$($t.Name): previous install backed up to $bak" 'DarkGray'
            Prune-Backups
        }
    }

    if ($PSCmdlet.ShouldProcess($dest, 'Install Wintage themes')) {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $t.Built '*') -Destination $dest -Recurse -Force
        $count = (Get-ChildItem (Join-Path $dest 'themes') -Filter '*.json').Count
        Say "$($t.Name): installed $count themes -> $dest" 'Green'
        Say "  Pick one: Ctrl+K Ctrl+T, look for 'Wintage ...'. Restart the app if it does not appear." 'DarkGray'
        Set-ManifestEntry $name $Palette $dest 'n/a' (Get-PayloadVersion)
    }
}
