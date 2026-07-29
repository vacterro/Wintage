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
    [ValidateSet('antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'nomadcode', 'all')]
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
    nomadcode       = @{
        Name      = 'NomadCode'
        Resources = Join-Path $env:LOCALAPPDATA 'Programs/codenomad-electron-app/resources'
        Note      = 'Electron. Only AppData leftovers found on this machine - no installed program.'
    }
}

if (-not $Target) {
    Say "Wintage desktop targets:" 'Cyan'
    foreach ($k in $TARGETS.Keys | Sort-Object) {
        $t = $TARGETS[$k]
        $present = if (Test-Path $t.Dir) { 'found' } else { 'NOT found on this machine' }
        Say ("  {0,-12} {1,-22} {2}" -f $k, $t.Name, $present)
        Say ("               {0}" -f $t.Note) 'DarkGray'
    }
    foreach ($k in $ELECTRON.Keys | Sort-Object) {
        $e = $ELECTRON[$k]
        $present = if (Test-ElectronApp $e.Resources) { if (Test-Path (Join-Path $e.Resources 'app/package.json')) { 'found, THEMED' } else { 'found' } } else { 'NOT found on this machine' }
        Say ("  {0,-16} {1,-38} {2}" -f $k, $e.Name, $present)
        Say ("                   {0}" -f $e.Note) 'DarkGray'
    }
    Say ""
    Say "Run:  .\install.ps1 -Target <name> [-Palette golden|claudecode|antigravity|klite|freebuff|nomadcode]" 'Cyan'
    Say "      .\install.ps1 -Target all          .\install.ps1 -Target claude -Revert" 'Cyan'
    return
}

# The built output is generated, not committed by hand -- refuse to install a stale
# or missing build rather than silently shipping last week's colours.
$node = Get-Command node -ErrorAction SilentlyContinue
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

$names = if ($Target -eq 'all') { @($TARGETS.Keys) + @($ELECTRON.Keys) } else { @($Target) }

foreach ($name in $names) {

    # ─── Electron targets ────────────────────────────────────────────────────
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
