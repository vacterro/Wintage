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
    [ValidateSet('antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'codenomad', 'mpchc', 'discord', 'totalcmd', 'totalcmd2', 'all')]
    [string]$Target,
    [string]$Palette = 'golden',
    [switch]$Revert,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$out = Join-Path $here 'out'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $here "backup/$stamp"

function Say($msg, $colour = 'Gray') { Write-Host $msg -ForegroundColor $colour }

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

$ELECTRON = @{
    claude          = @{
        Name      = 'Claude (desktop app)'
        Resources = (Get-ClaudeResources)
        Note      = 'Electron. Update creates a new app-<version> folder, so re-run after an update.'
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
}

# РІвЂќР‚РІвЂќР‚РІвЂќР‚ MPC-HC (K-Lite) РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
# Native Win32, no stylesheet, no injection point. Its dark theme's colours are
# COMPILED IN (CMPCTheme in the MPC-HC source) and no registry value exposes them,
# so this target cannot carry a palette at all. What it can do is switch the dark
# theme on and put the UI.md typography rules on the one surface MPC-HC does let a
# user control -- the OSD. Saying that plainly beats claiming a coverage that does
# not exist, which is why the report below names what is out of reach.
$MPC_KEY = 'HKCU:\Software\MPC-HC\MPC-HC\Settings'
$MPC_REG = 'HKCU\Software\MPC-HC\MPC-HC\Settings'


function Invoke-TotalCmd {
    param([int]$Index, [switch]$DoRevert, [string]$PaletteSlug)
    $appName = if ($Index -eq 1) { 'Total Commander' } else { 'Total Commander (Local)' }
    $candidates = if ($Index -eq 1) {
        @('V:\___VAC\__P\_TOTALCMD\wincmd.ini', (Join-Path $env:APPDATA 'GHISLER\wincmd.ini'))
    } else {
        @('V:\___VAC\__P\_TOTALCMD2\wincmd.ini', (Join-Path $env:LOCALAPPDATA 'GHISLER\wincmd.ini'))
    }
    $ini = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $ini) { Say "$($appName): not installed (no wincmd.ini found)" 'DarkYellow'; return }

    if ($DoRevert) {
        if ($PSCmdlet.ShouldProcess($ini, 'Revert Wintage theme')) {
            $lines = Get-Content $ini
            $newLines = $lines | Where-Object { $_.Trim() -notmatch '^(BackColor|BackColor2|ForeColor|MarkColor|CursorColor|CursorText|ActiveTitle|ActiveTitleText|InactiveTitle|InactiveTitleText)=' }
            Set-Content $ini $newLines -Encoding UTF8
            Say "$($appName): removed Wintage theme" 'Green'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($ini, 'Apply Wintage theme')) {
        $jsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "themes\$PaletteSlug.json"
        if (-not (Test-Path $jsonPath)) { Say "$($appName): theme file not found ($PaletteSlug.json)" 'Red'; return }
        $t = (Get-Content $jsonPath -Raw | ConvertFrom-Json).tokens
        
        function HexToBgr([string]$hex) {
            $hex = $hex.Replace('#', '')
            if ($hex.Length -eq 8) { $hex = $hex.Substring(0, 6) }
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
            return ($b -shl 16) -bor ($g -shl 8) -bor $r
        }

        $bg = HexToBgr $t.background
        $fg = HexToBgr $t.textPrimary
        $cursorBg = HexToBgr $t.selection
        $cursorFg = HexToBgr $t.borderHighlight
        $markFg = HexToBgr $t.danger
        $titleBg = HexToBgr $t.surface
        $titleFg = HexToBgr $t.textPrimary
        $titleInBg = HexToBgr $t.backgroundSoft
        $titleInFg = HexToBgr $t.textMuted

        $lines = Get-Content $ini
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
        foreach ($line in $newLines) {
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
        Set-Content $ini $finalLines -Encoding UTF8
        Say "$($appName): applied $PaletteSlug" 'Green'
    }
}

function Invoke-CodeNomad {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $cnConfig = Join-Path $env:USERPROFILE '.config/codenomad'
    $cnCss = Join-Path $cnConfig 'custom.css'
    
    if (-not (Test-Path $cnConfig)) { Say "CodeNomad: not installed (no .config/codenomad)" 'DarkYellow'; return }

    if ($DoRevert) {
        if (Test-Path $cnCss) {
            if ($PSCmdlet.ShouldProcess($cnCss, 'Remove Wintage theme')) {
                Remove-Item $cnCss -Force
                Say "CodeNomad: removed $cnCss" 'Green'
            }
        } else { Say "CodeNomad: nothing installed, nothing to revert." }
        return
    }

    if ($PSCmdlet.ShouldProcess($cnCss, 'Install Wintage theme')) {
        $css = Get-Content (Join-Path $out ('browser/wintage-' + $PaletteSlug + '.css')) -Raw
        Set-Content $cnCss $css -Encoding UTF8
        Say "CodeNomad: installed theme -> $cnCss" 'Green'
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
            }
        } else { Say "BetterDiscord: nothing installed, nothing to revert." }
        return
    }

    if ($PSCmdlet.ShouldProcess($bdCss, 'Install Wintage theme')) {
        $css = Get-Content (Join-Path $out ('browser/wintage-' + $PaletteSlug + '.css')) -Raw
        $meta = "/**`n * @name Wintage ($PaletteSlug)`n * @author Wintage Installer`n * @version 1.0.0`n * @description Win95 Theme`n */`n`n"
        Set-Content $bdCss ($meta + $css) -Encoding UTF8
        Say "BetterDiscord: installed theme -> $bdCss" 'Green'
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
            Say "MPC-HC: restored the captured values from $bak" 'Green'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($MPC_REG, 'Back up and apply the Wintage/UI.md settings')) {
        New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
        if (-not (Test-Path $bak)) {
            & reg export $MPC_REG $bak /y 2>&1 | Out-Null
            Say "MPC-HC: settings backed up to $bak" 'DarkGray'
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

if (-not $Target) {
    # The whole point of the listing is answering three questions at once: is the app
    # here, is it themed, and WHICH palette is on it. Without the third column,
    # "which one did I put on Freebuff again" has no answer short of reading JSON.
    $palettes = (Get-ChildItem (Join-Path $root 'themes') -Filter '*.json' | ForEach-Object { $_.BaseName }) -join '|'

    Say "Wintage desktop targets:" 'Cyan'
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'target', 'application', 'state', 'palette') 'DarkGray'

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
        $pkg = Join-Path $e.Resources 'app/package.json'
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
        $state = if (-not (Test-ElectronApp $e.Resources)) { 'not installed' }
                 elseif ($blocked) { $blocked }
                 elseif (Test-Path $pkg) { 'themed' }
                 else { 'found, not themed' }
        $pal = if (Test-Path $pkg) { (Get-Content $pkg -Raw | ConvertFrom-Json).wintagePalette } else { '-' }
        Say ("  {0,-16} {1,-38} {2,-22} {3}" -f $k, $e.Name, $state, $pal)
    }

    $mpc = if (Test-Path $MPC_KEY) {
        if ((Get-ItemProperty $MPC_KEY).OSDFont -eq 'Verdana') { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'mpchc', 'MPC-HC (K-Lite)', $mpc, 'n/a - colours are compiled in')

    Say ""

    $cnConfig = Join-Path $env:USERPROFILE '.config/codenomad'
    $cnCss = Join-Path $cnConfig 'custom.css'
    $cn = if (Test-Path $cnConfig) {
        if (Test-Path $cnCss) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'codenomad', 'CodeNomad', $cn, '-')

    $bdDir = Join-Path $env:APPDATA 'BetterDiscord/themes'
    $bdCss = Join-Path $bdDir 'wintage.theme.css'
    $bd = if (Test-Path $bdDir) {
        if (Test-Path $bdCss) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'discord', 'BetterDiscord', $bd, '-')

    $tc1Dir = Join-Path $env:APPDATA 'GHISLER'
    $tc1Ini = Join-Path $tc1Dir 'wincmd.ini'
    $tc1 = if (Test-Path $tc1Ini) {
        if ((Get-Content $tc1Ini | Select-String "ActiveTitleText=") -ne $null) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'totalcmd', 'Total Commander', $tc1, '-')

    $tc2Dir = Join-Path $env:LOCALAPPDATA 'GHISLER'
    $tc2Ini = Join-Path $tc2Dir 'wincmd.ini'
    $tc2 = if (Test-Path $tc2Ini) {
        if ((Get-Content $tc2Ini | Select-String "ActiveTitleText=") -ne $null) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'totalcmd2', 'Total Commander (Local)', $tc2, '-')

    Say "Palettes: $palettes" 'DarkGray'
    Say "  .\install.ps1 -Target freebuff -Palette klite     one app, one palette" 'Cyan'
    Say "  .\install.ps1 -Target all -Palette golden         everything, one palette" 'Cyan'
    Say "  .\install.ps1 -Target freebuff -Revert            undo one" 'Cyan'
    Say "Repainting an already-themed app works while it is running; a first install does not." 'DarkGray'
    return
}

# The built output is generated, not committed by hand -- refuse to install a stale
# or missing build rather than silently shipping last week's colours.
if ($node) {
    & node (Join-Path $root 'tools/build-desktop.js') --check | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (-not $Force) { throw "desktop/out is out of date with themes/*.json. Run 'node tools/build-desktop.js' first, or pass -Force to install what is already built." }
        Say "WARNING: installing a build that is out of date with themes/*.json (-Force)." 'Yellow'
    }
}
elseif (-not $Force) {
    Say "node not found - cannot verify the build is current. Installing what is in desktop/out as-is." 'Yellow'
}

$names = if ($Target -eq 'all') { @($TARGETS.Keys) + @($ELECTRON.Keys) + @('mpchc') } else { @($Target) }

foreach ($name in $names) {

    if ($name -eq 'mpchc') { Invoke-MpcHc -DoRevert:$Revert; continue }
    if ($name -eq 'codenomad') { Invoke-CodeNomad -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'discord') { Invoke-BetterDiscord -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd') { Invoke-TotalCmd -Index 1 -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd2') { Invoke-TotalCmd -Index 2 -DoRevert:$Revert -PaletteSlug $Palette; continue }

    # РІвЂќР‚РІвЂќР‚РІвЂќР‚ Electron targets РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
    if ($ELECTRON.ContainsKey($name)) {
        $e = $ELECTRON[$name]
        if (-not (Test-ElectronApp $e.Resources)) {
            Say "$($e.Name): not installed on this machine - skipped." 'DarkYellow'
            continue
        }
        if (-not $node) { Say "$($e.Name): needs node to read the app's package.json out of app.asar - skipped." 'Yellow'; continue }

        $script = Join-Path $root 'tools/install-electron.js'
        if ($Revert) {
            if ($PSCmdlet.ShouldProcess($e.Resources, 'Remove the Wintage shim')) {
                & node $script --resources $e.Resources --revert
            }
            continue
        }
        $action = "Install Wintage ($Palette) shim"
        if ($WhatIfPreference) { & node $script --resources $e.Resources --palette $Palette --dry-run; continue }
        if ($PSCmdlet.ShouldProcess($e.Resources, $action)) {
            & node $script --resources $e.Resources --palette $Palette
            if ($LASTEXITCODE -ne 0) { Say "$($e.Name): FAILED - see the message above." 'Red' }
            else { Say "  Restart $($e.Name) to see it. Undo: .\install.ps1 -Target $name -Revert" 'DarkGray' }
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
        }
    }

    if ($PSCmdlet.ShouldProcess($dest, 'Install Wintage themes')) {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $t.Built '*') -Destination $dest -Recurse -Force
        $count = (Get-ChildItem (Join-Path $dest 'themes') -Filter '*.json').Count
        Say "$($t.Name): installed $count themes -> $dest" 'Green'
        Say "  Pick one: Ctrl+K Ctrl+T, look for 'Wintage ...'. Restart the app if it does not appear." 'DarkGray'
    }
}

