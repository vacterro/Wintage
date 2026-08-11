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

# Shared helpers + per-target implementations, split out at T-169. Dot-sourced so they
# resolve install.ps1 scoped variables and the i18n T() loader at call time. Load
# order matters: common.ps1 MUST precede targets.ps1 (targets call Read-Utf8/Say/
# backup helpers), and both must precede the $TARGETS/$ELECTRON tables below, which
# call Get-ClaudeResources/Get-CodeNomadResources at definition time.
. (Join-Path $PSScriptRoot 'modules/common.ps1')
. (Join-Path $PSScriptRoot 'modules/targets.ps1')

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
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)

# Manifest/paths live in the user's %APPDATA%\Wintage. Tests override the whole
# root through WINTAGE_APPDATA so fixtures never touch the live manifest; the env
# var propagates through the child powershell instances -Reapply spawns, which is
# why it is an env var and not a param.
$WintageAppData = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
$ManifestPath = Join-Path $WintageAppData 'installed.json'
$PathsPath = Join-Path $WintageAppData 'paths.json'

. (Join-Path $PSScriptRoot 'i18n.ps1')

$TASK_NAME = 'Wintage Reapply at Logon'

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

$CONHOST_KEY = 'HKCU:\Console'
$CONHOST_BACKUP = Join-Path $here 'backup/conhost-settings.json'

$WINDOWS_THEME_KEY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$WINDOWS_THEMES_DIR = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
$WINDOWS_THEME_MARKER = Join-Path $WINDOWS_THEMES_DIR '.wintage-windows-palette'
$WINDOWS_DWM_KEY = 'HKCU:\Software\Microsoft\Windows\DWM'
$WINDOWS_DWM_BACKUP = Join-Path $here 'backup/windows-dwm-settings.json'

$MPC_KEY = 'HKCU:\Software\MPC-HC\MPC-HC\Settings'
$MPC_REG = 'HKCU\Software\MPC-HC\MPC-HC\Settings'

$OBS_CONFIG = Join-Path $env:APPDATA 'obs-studio'
$OBS_THEME_ID = 'com.wintage.OBS'

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

# ---- Reapply mode: read manifest, rediscover paths, re-apply outdated payloads ----
if ($Reapply) {
    $currentVer = Get-PayloadVersion
    try {
        $manifest = Read-Manifest
    } catch {
        Say "installed.json at ${ManifestPath} is CORRUPT and cannot be read: $($_.Exception.Message)" 'Red'
        Say 'Nothing was re-applied. Fix or remove the file by hand, then run -Reapply again.' 'Yellow'
        exit 1
    }
    if ($manifest.Count -eq 0) { Say 'Nothing to do -- the manifest is empty (no targets have been installed).' 'Green'; exit 0 }
    $didWork = $false
    $failedTargets = @()
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
        # Semantic version comparison: a recorded payload that is older than the
        # repo's needs re-applying. A recorded OR current value that does not
        # parse as a version is never silently "up to date" -- it is treated as
        # needing reapply, because an unknown version is exactly the state that
        # used to skip the refresh forever (1.9.0 vs 1.26.3 compared as strings).
        if (Test-PayloadUpToDate $data.payloadVersion $currentVer) {
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
        # A failing child can emit native stderr (a node stack trace, a reg
        # error). Under EAP=Stop the 2>&1 merge turns each line into a
        # terminating error and aborts the WHOLE reapply loop mid-target --
        # exactly the sibling-loss this mode must not have. Read the child with
        # EAP=Continue and judge it by $LASTEXITCODE alone.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $result = & powershell @callArgs 2>&1
        $childCode = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if ($childCode -eq 0) {
            if (-not $Quiet) { Say "$key`: re-applied successfully." 'Green' }
        }
        else {
            # Failures are NEVER suppressed by -Quiet: a silent reapply loop that
            # reports green while a target stays broken is how a logon task lies.
            Say "$key`: FAILED ($childCode)." 'Red'
            Write-Warning ($result -join "`n")
            $failedTargets += $key
        }
    }
    if (-not $didWork) {
        if (-not $Quiet) { Say 'Nothing to do -- all recorded targets are up to date.' 'Green' }
    }
    if ($failedTargets.Count) {
        Say "Reapply incomplete: $($failedTargets.Count) target(s) failed ($($failedTargets -join ', '))." 'Red'
        exit 1
    }
    exit 0
}

if ($RegisterLogonTask) { Register-WintageLogonTask; exit 0 }
if ($UnregisterLogonTask) { Unregister-WintageLogonTask; exit 0 }

if ($Status) {
    try {
        $manifest = Read-Manifest
    } catch {
        Say "installed.json at ${ManifestPath} is CORRUPT and cannot be read: $($_.Exception.Message)" 'Red'
        Say 'No target will be listed or re-applied until the file is fixed or removed by hand.' 'Yellow'
        exit 1
    }
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
    $browserOut = (& powershell @browserArgs 2>$null | Out-String).Trim()
    $browserInfo = $null
    if ($LASTEXITCODE -eq 0 -and $browserOut) {
        try { $browserInfo = $browserOut | ConvertFrom-Json } catch { $browserInfo = $null }
    }
    if (-not $browserInfo) {
        Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'browsers', 'Chromium browsers', 'listing failed', '-')
        Say "  install-browsers.ps1 did not return a listing ($LASTEXITCODE) - install it directly to see why." 'DarkGray'
    } else {
        $browserState = if (-not $browserInfo.ProfileCount) { 'not installed' }
                        elseif ($browserInfo.ThemeLoadedCount -eq $browserInfo.ProfileCount) { 'themed' }
                        else { 'found, not themed' }
        $browserName = "Chromium browsers ($($browserInfo.ProfileCount)p/TM$($browserInfo.TampermonkeyCount))"
        Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'browsers', $browserName, $browserState, $browserInfo.Palette)
    }

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

$dispatchFailures = @()

foreach ($name in $names) {
    try {

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
        if (-not $node) { throw "$($e.Name): needs node to read the app's package.json out of app.asar." }

        $script = Join-Path $root 'tools/install-electron.js'
        $nodeArgs = @($script, '--resources', $e.Resources)
        if ($e.InPlace) { $nodeArgs += '--in-place' }
        
        if ($Revert) {
            if ($PSCmdlet.ShouldProcess($e.Resources, 'Remove the Wintage shim')) {
                & node $nodeArgs --revert
                if ($LASTEXITCODE -ne 0) { throw "$($e.Name): revert FAILED ($LASTEXITCODE) - manifest kept, see the message above." }
                Remove-ManifestEntry $name
            }
            continue
        }
        $action = "Install Wintage ($Palette) shim"
        if ($WhatIfPreference) {
            # Dry-run is a validation pass too: a failing helper must fail the
            # parent, or -WhatIf reports a plan the real apply cannot honour.
            & node $nodeArgs --palette $Palette --dry-run
            if ($LASTEXITCODE -ne 0) { throw "$($e.Name): dry-run FAILED ($LASTEXITCODE) - see the message above." }
            continue
        }
        if ($PSCmdlet.ShouldProcess($e.Resources, $action)) {
            & node $nodeArgs --palette $Palette
            if ($LASTEXITCODE -ne 0) { throw "$($e.Name): apply FAILED ($LASTEXITCODE) - see the message above." }
            # FreeBuff ships its own ad network (renderer + orchestrator routes).
            # The shim themes it; this cuts the ads out of the bundle and routes.
            # A custom completion sound is a per-machine preference written by
            # the GUI (WintageInstaller.ps1 -> %APPDATA%\Wintage\freebuff-sound.txt):
            # if one is set, hand it to the same patch run so the ads and the
            # sound are applied together. The patch keeps the stock file as
            # chime-*.mp3.bak and --revert restores it.
            #
            # The manifest is written only AFTER both the shim AND the mandatory
            # FreeBuff post-step succeeded. A partial apply (shim in, ads not cut)
            # must never record the target as current -- it stays incomplete so
            # the next -Reapply actually retries it.
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
                        if ($LASTEXITCODE -ne 0) {
                            throw 'FreeBuff: shim applied but the ad/sound patch FAILED - run patch-freebuff-ads.js --scan to see what this build carries, then update the strings. The manifest was NOT updated, so -Reapply will retry.'
                        }
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
    catch {
        # A target that threw must never read as a green run. Record it, keep
        # applying the remaining siblings, and leave the exit code nonzero.
        Say "$name`: FAILED - $($_.Exception.Message)" 'Red'
        $dispatchFailures += $name
    }
}

if ($dispatchFailures.Count) {
    Say "Install incomplete: $($dispatchFailures.Count) target(s) failed ($($dispatchFailures -join ', '))." 'Red'
    exit 1
}

