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
# Anything overwritten is copied to the recovery tree in your profile
# (%APPDATA%\Wintage\recovery\<timestamp>/) first.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('windows', 'browsers', 'antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'codenomad', 'workbuddy', 'zcode', 'mpchc', 'terminal', 'conhost', 'obs', 'discord', 'totalcmd', 'totalcmd2', 'obsidian', 'qbittorrent', 'notepadplusplus', 'cinema4d', 'all')]
    [string]$Target,
    # PERF-005 (T-240): batch mode for the GUI. A comma-separated selected set
    # (e.g. -Selected "vscode,obs") that feeds the SAME $names dispatcher below
    # in ONE worker process, with ONE shared build verification. Mutually
    # exclusive with -Target. Deliberately NOT named $Targets: that collides
    # case-insensitively with the $TARGETS config hashtable and broke every
    # invocation at metadata validation (E-851).
    [string]$Selected,
    [string]$Palette = 'goldendefault',
    [string]$Language,
    [switch]$Revert,
    [switch]$Force,
    [string]$CodeNomadPath,
    [string]$WorkBuddyPath,
    [string]$ZCodePath,
    [string]$TotalCmdIni,
    [string]$TotalCmd2Ini,
    [string]$PortableBrowserRoot,
    [string]$BrowserStageRoot = (Join-Path $env:LOCALAPPDATA 'Wintage\browser-theme'),
    [string]$BrowserCatalog,
    [switch]$NoBrowserLaunch,
    [string]$Cinema4DPath,
    [string]$NotepadPlusPlusPath,
    [switch]$Reapply,
    # SRC-006:R005: internal Reapply-only parameter. The parent passes the
    # intent fingerprint of the manifest entry it planned from; the child
    # re-validates it under the target lock and skips with ZERO mutation when
    # the live entry no longer matches. Never set it by hand.
    [string]$ExpectedIntent,
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

# Shared helpers + per-target implementations, split out at T-169. Dot-sourced so they
# resolve install.ps1 scoped variables and the i18n T() loader at call time. Load
# order matters: common.ps1 MUST precede targets.ps1 (targets call Read-Utf8/Say/
# backup helpers), and both must precede the $TARGETS/$ELECTRON tables below, which
# call Get-ClaudeResources/Get-CodeNomadResources at definition time.
. (Join-Path $PSScriptRoot 'modules/common.ps1')
. (Join-Path $PSScriptRoot 'modules/targets.ps1')

# PowerShell 5.1 writes a BOM with `Set-Content -Encoding UTF8`, and `Get-Content`
# falls back to the ANSI codepage on a file that has none. Both halves have already
# bitten this project once: a target's stylesheet came back with 30 mojibaked
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

# Recovery root (W2-001): fixed-name recovery files (conhost-settings.json,
# windows-dwm-settings.json) and the timestamped apply-time backups live under
# the same user-profile recovery tree as the manifest, so an installer copy can
# never strand ownership evidence outside the profile (and %APPDATA% owns the
# install epoch that stamps those files). The env seam lets fixtures isolate it.
$backupBase = if ($env:WINTAGE_BACKUP_ROOT) { $env:WINTAGE_BACKUP_ROOT } else { Join-Path $WintageAppData 'recovery' }
$backupRoot = Join-Path $backupBase $stamp

# W2-004: preferences are loaded BEFORE the target tables freeze their values.
# The $ELECTRON table below resolves CodeNomad/WorkBuddy at definition time, so
# remembered paths must be in scope first or the eager resolution ignores them.
$pathsJson = Read-PathsJson
$script:pathsJson = $pathsJson

. (Join-Path $PSScriptRoot 'i18n.ps1')

# Explicit -Language wins over the machine-wide saved pick; an unknown code is a
# hard error, not a silent English fallback -- a typo'd flag that quietly does
# nothing is worse than a failed run.
if ($Language -and $Language -ne $script:SavedLocale) {
    if (-not (Test-Path (Join-Path $PSScriptRoot "locales\$Language.json"))) {
        throw "unknown -Language '$Language' - no desktop/locales/$Language.json (available: $((Get-I18nLocales) -join ', '))"
    }
    Load-I18n $Language
}

$TASK_NAME = 'Wintage Reapply at Logon'

# Where each target keeps its extensions. Both are VS Code-family and read the
# identical format, which is why one built extension serves them both.
$userHome = if ($env:HOME) { $env:HOME } else { $HOME }
$TARGETS = @{
    antigravity = @{
        Name  = 'Antigravity IDE'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $userHome '.antigravity/extensions'
        Built = Join-Path $out 'vscode/wintage-themes'
        Note  = 'Six colour themes. Lives in your profile, so an IDE update cannot remove it.'
    }
    vscode      = @{
        Name  = 'Visual Studio Code'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $userHome '.vscode/extensions'
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
    workbuddy       = @{
        Name      = 'WorkBuddy AI'
        Resources = (Get-WorkBuddyResources)
        Note      = 'Electron, portable. Pass -WorkBuddyPath if it lives somewhere else.'
    }
    zcode           = @{
        Name      = 'ZCode'
        Resources = (Get-ZCodeResources)
        Note      = 'Electron. Pass -ZCodePath if it lives somewhere else.'
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
# so letters visibly collided. Terminus (TTF) for Windows is the user's installed
# bitmap-style monospace (the classic console look), monospaced and safe for the
# fixed cell grid; Consolas remains the bundled fallback if Terminus is absent.
$CONSOLE_FONT = 'Terminus (TTF) for Windows'

# Fixed-name recovery files (conhost-settings.json, windows-dwm-settings.json)
# share the backup base with the timestamped apply backups; the env seam lets
# fixtures isolate BOTH. Timestamped dirs are pruned, fixed-name files are not.
$CONHOST_KEY = if ($env:WINTAGE_TEST_CONHOST_KEY) { $env:WINTAGE_TEST_CONHOST_KEY } else { 'HKCU:\Console' }
$CONHOST_BACKUP = Join-Path $backupBase 'conhost-settings.json'

$WINDOWS_THEME_KEY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$WINDOWS_THEMES_DIR = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
$WINDOWS_THEME_MARKER = Join-Path $WINDOWS_THEMES_DIR '.wintage-windows-palette'
$WINDOWS_DWM_KEY = 'HKCU:\Software\Microsoft\Windows\DWM'
$WINDOWS_DWM_BACKUP = Join-Path $backupBase 'windows-dwm-settings.json'

$MPC_KEY = 'HKCU:\Software\MPC-HC\MPC-HC\Settings'
$MPC_REG = 'HKCU\Software\MPC-HC\MPC-HC\Settings'

$OBS_CONFIG = Join-Path $env:APPDATA 'obs-studio'
$OBS_THEME_ID = 'com.wintage.OBS'

# qBittorrent keeps its settings in a QSettings INI and its themes under the same
# config root, so the theme survives an application update untouched. The theme is
# a DIRECTORY (config.json + stylesheet.qss): pointing CustomUIThemePath at the
# config.json is what makes qBittorrent read the pair as an unpacked theme.
$QBT_CONFIG = Join-Path $env:APPDATA 'qBittorrent'
$QBT_INI = Join-Path $QBT_CONFIG 'qBittorrent.ini'
$QBT_THEME_DIR = Join-Path $QBT_CONFIG 'themes\wintage'
$QBT_MARKER = Join-Path $QBT_CONFIG '.wintage-qbt-palette'

# Resolved BEFORE the listing, not after: the listing reads Electron fuses through
# node, and when this lived below it, $node was still empty there — so every app
# silently reported "not themed" instead of "fused shut", which is the one line in
# the table a user actually needs when an app refuses to start.
# Test seam: WINTAGE_TEST_NO_NODE lets fixtures exercise the no-Node code paths.
$node = if ($env:WINTAGE_TEST_NO_NODE) { $null } else { Get-Command node -ErrorAction SilentlyContinue }

# Resolve source-tree paths from paths.json when not passed on the command line.
# The GUI and (since W2-004) the CLI both write remembered paths there; the CLI
# consults the same file so a path entered once is available to every install.ps1
# invocation without repeating it.
if (-not $CodeNomadPath -and $pathsJson.ContainsKey('codenomad')) { $CodeNomadPath = $pathsJson['codenomad'] }
if (-not $WorkBuddyPath -and $pathsJson.ContainsKey('workbuddy')) { $WorkBuddyPath = $pathsJson['workbuddy'] }
if (-not $ZCodePath -and $pathsJson.ContainsKey('zcode')) { $ZCodePath = $pathsJson['zcode'] }
if (-not $PortableBrowserRoot -and $pathsJson.ContainsKey('portable')) { $PortableBrowserRoot = $pathsJson['portable'] }
if (-not $Cinema4DPath -and $pathsJson.ContainsKey('cinema4d')) { $Cinema4DPath = $pathsJson['cinema4d'] }
if (-not $NotepadPlusPlusPath -and $pathsJson.ContainsKey('notepadplusplus')) { $NotepadPlusPlusPath = $pathsJson['notepadplusplus'] }

# PERF-005 (T-240): batch-mode guards, BEFORE any mode branch (-Reapply/-Status
# exit before the dispatcher, so a conflict rejected only there would never fire).
if ($Target -and $Selected) { throw '-Target and -Selected are mutually exclusive - pass exactly one of them.' }
if ($Selected -and ($Reapply -or $Status -or $RegisterLogonTask -or $UnregisterLogonTask)) { throw '-Selected runs a batch Apply/Revert - it cannot be combined with -Reapply, -Status or logon-task switches.' }

# SRC-006:R005: a Reapply child reports its outcome through a DEDICATED EXIT
# CODE, never through prose the parent would have to parse:
#   0                    = the target was processed normally (mutated for real,
#                          or -WhatIf-validated)
#   $REAPPLY_STALE_EXIT  = the live manifest entry no longer matches the intent
#                          the parent planned from; the child skipped with ZERO
#                          target, recovery, and manifest mutation
#   anything else        = failure
# The parent maps 3 to STALE_SKIPPED, which is a SUCCESS for the overall
# -Reapply operation: dropping a stale plan is exactly what the child should
# do. Only real failures make the run exit nonzero.
$REAPPLY_STALE_EXIT = 3
# The mapping above is only unambiguous for the shape the parent dispatches:
# ONE explicit target per -ExpectedIntent child.
if ($ExpectedIntent -and (-not $Target -or $Target -eq 'all' -or $Selected)) {
    throw '-ExpectedIntent is internal to -Reapply and requires exactly one explicit -Target.'
}

# ---- Reapply mode: read manifest, probe TARGET health, re-apply unhealthy targets ----
# The decision is target health, not just the Wintage payload version (T-189):
# an application update or a moved install leaves payloadVersion unchanged while
# the theme is gone, so needsReapply fires on any of payload-outdated, resolved
# path moved, app version changed, marker/theme state missing, or unresolved.
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
    # plannedWork = a target needs re-apply (decided by health probe).
    # appliedTargets / staleTargets / failedTargets = the OUTCOME each child
    # reported through its exit code (see $REAPPLY_STALE_EXIT), booked here.
    # The old single $mutatedWork flag conflated "a child ran" with "the target
    # was mutated", which is how a stale skip used to surface as a green
    # "re-applied successfully". The two are deliberately separate from
    # -WhatIf: under -WhatIf the child MUST run its own preflight so a broken
    # helper surfaces as a nonzero exit, and the "all up to date" message must
    # never be printed merely because ShouldProcess suppressed a mutation
    # (T-189).
    $plannedWork = $false
    $appliedTargets = @()
    $staleTargets = @()
    $failedTargets = @()
    $passArgs = @{}
    if ($CodeNomadPath) { $passArgs['-CodeNomadPath'] = $CodeNomadPath }
    if ($WorkBuddyPath) { $passArgs['-WorkBuddyPath'] = $WorkBuddyPath }
    if ($TotalCmdIni)  { $passArgs['-TotalCmdIni'] = $TotalCmdIni }
    if ($TotalCmd2Ini) { $passArgs['-TotalCmd2Ini'] = $TotalCmd2Ini }
    if ($Cinema4DPath) { $passArgs['-Cinema4DPath'] = $Cinema4DPath }
    if ($NotepadPlusPlusPath) { $passArgs['-NotepadPlusPlusPath'] = $NotepadPlusPlusPath }
    if ($Force) { $passArgs['-Force'] = $Force }
    if ($PortableBrowserRoot) { $passArgs['-PortableBrowserRoot'] = $PortableBrowserRoot }
    if ($BrowserStageRoot) { $passArgs['-BrowserStageRoot'] = $BrowserStageRoot }
    if ($BrowserCatalog) { $passArgs['-BrowserCatalog'] = $BrowserCatalog }
    if ($NoBrowserLaunch) { $passArgs['-NoBrowserLaunch'] = $NoBrowserLaunch }
    $sorted = @($manifest.Keys | Sort-Object)
    foreach ($key in $sorted) {
        $data = $manifest[$key]
        $health = Test-TargetNeedsReapply $key $data $currentVer
        if (-not $health.Needs) {
            if (-not $Quiet) { Say "$key`: up to date (payload v$($data.payloadVersion), path $($data.path))." 'DarkGray' }
            continue
        }
        $plannedWork = $true
        $action = "Re-apply $key @ $($data.palette) ($($health.Reasons))"
        # SRC-006:R005: the child re-validates THIS manifest intent under the
        # target lock before mutating anything, so a Revert or palette change
        # that wins the plan->lock race makes the child skip instead of blindly
        # resurrecting a stale snapshot.
        $callArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
            '-Target', $key, '-Palette', $data.palette,
            '-ExpectedIntent', (Get-ReapplyIntentToken $data))
        foreach ($pk in $passArgs.Keys) { $callArgs += $pk; $callArgs += $passArgs[$pk] }
        # A browsers RE-APPLY must never reopen the browser: the theme loads from a
        # stable stage path that is already registered in the profile, so a repaint
        # has nothing to set up. Reopening here is how a background -Reapply can
        # yank a browser window over a fullscreen game (T-191).
        if ($key -eq 'browsers' -and $callArgs -notcontains '-NoBrowserLaunch') { $callArgs += '-NoBrowserLaunch' }
        if ($WhatIfPreference) {
            # Planned work, no mutation: run the child with -WhatIf so ITS real
            # preflight executes (dry-runs, anchor checks, helper validation).
            $callArgs += '-WhatIf'
            if (-not $Quiet) { Say "$key`: WOULD re-apply $($data.palette) - $($health.Reasons)" 'Cyan' }
        } elseif (-not $PSCmdlet.ShouldProcess("$key ($($data.palette))", $action)) {
            continue
        } else {
            if (-not $Quiet) { Say "$key`: re-applying $($data.palette) - $($health.Reasons)" 'Cyan' }
        }
        # TEST-ONLY synchronization seam (SRC-006:R005). Inert unless
        # WINTAGE_TEST_REAPPLY_PARENT_SEAM is set exactly as '<target>|<dir>'.
        # After planning a real child dispatch the parent writes '<dir>\planned'
        # and waits (bounded) for '<dir>\resume' BEFORE spawning the child, so a
        # race fixture can run a REAL competing Apply/Revert inside the
        # plan->child window and still finish deterministically. Never set
        # outside tests.
        if ($env:WINTAGE_TEST_REAPPLY_PARENT_SEAM -and -not $WhatIfPreference) {
            $seamParts = @($env:WINTAGE_TEST_REAPPLY_PARENT_SEAM -split '\|', 2)
            if ($seamParts.Count -eq 2 -and $seamParts[0] -eq $key) {
                Set-Content -LiteralPath (Join-Path $seamParts[1] 'planned') -Value $key
                $seamDeadline = [DateTime]::UtcNow.AddSeconds(120)
                while (-not (Test-Path (Join-Path $seamParts[1] 'resume'))) {
                    if ([DateTime]::UtcNow -gt $seamDeadline) { throw "test seam: the resume signal never arrived for $key" }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
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
            $appliedTargets += $key
            if ($WhatIfPreference) {
                if (-not $Quiet) { Say "$key`: would re-apply $($data.palette) - the child's own preflight validated the plan (-WhatIf dry-run)." 'Cyan' }
            } else {
                if (-not $Quiet) { Say "$key`: re-applied successfully." 'Green' }
            }
        }
        elseif ($childCode -eq $REAPPLY_STALE_EXIT) {
            # SRC-006:R005: the child's intent revalidation lost the plan->lock
            # race - a Revert or a palette change owns the target now. Skipping
            # IS the correct outcome (the run still exits 0), the stale plan is
            # dropped, and nothing was mutated: this is never reported as, or
            # counted as, a re-apply.
            $staleTargets += $key
            if (-not $Quiet) { Say "$key`: SKIPPED - the manifest intent changed after this Reapply was planned (a Revert or palette change won the race); the stale plan was dropped, nothing was mutated." 'Yellow' }
        }
        else {
            # Failures are NEVER suppressed by -Quiet: a silent reapply loop that
            # reports green while a target stays broken is how a logon task lies.
            Say "$key`: FAILED ($childCode)." 'Red'
            Write-Warning ($result -join "`n")
            $failedTargets += $key
        }
    }
    if (-not $plannedWork) {
        if (-not $Quiet) { Say 'Nothing to do -- all recorded targets are up to date.' 'Green' }
    } elseif ($WhatIfPreference -and -not $failedTargets.Count) {
        if (-not $Quiet) { Say 'Reapply planned: no real mutation happened (-WhatIf dry-run complete).' 'Cyan' }
    }
    if ($staleTargets.Count -and -not $Quiet) {
        Say "Skipped $($staleTargets.Count) target(s) whose manifest intent changed since planning ($($staleTargets -join ', ')) - they were NOT re-applied." 'Yellow'
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

if (-not $Target -and -not $Selected) {
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
                # PERF-005 (T-240): unchanged-file fuse cache. The listing runs at
                # startup AND after every Apply/Revert, and each run re-scanned
                # every Electron executable (128 MiB read for one unchanged 64 MiB
                # exe across two listings). The verdict is cached on disk keyed on
                # exe identity (path + size + mtimeUtc); ANY change or ANY doubt
                # (missing/corrupt cache, unreadable exe) means a fresh scan.
                # Fail-closed: a cache entry is only ever a past SCAN result, an
                # unscanned exe is never accepted as safe from the cache.
                $blocked = Get-CachedFuseBlocked $exe.FullName
                if ($null -eq $blocked) {
                    try {
                        $prevEap = $ErrorActionPreference
                        $ErrorActionPreference = 'Continue'
                        $fuse = & node (Join-Path $root 'tools/electron-fuses.js') $exe.FullName 2>$null
                        $ErrorActionPreference = $prevEap
                        if ($LASTEXITCODE -ne 0) { $blocked = 'listing failed' }
                        elseif ($fuse -match 'NOT themeable') { $blocked = 'fused shut' }
                        else { $blocked = '' }
                        Set-CachedFuseBlocked $exe.FullName $blocked
                    } catch {
                        $blocked = 'listing failed'
                    }
                }
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

    # "themed" here means what the app itself needs to load the theme: the two
    # files present AND both INI keys pointing at them. A marker alone would call
    # it themed after the user unticked "Use custom UI theme".
    $qbtCfg = Join-Path $QBT_THEME_DIR 'config.json'
    $qbtPal = if (Test-Path $QBT_MARKER) { (Read-Utf8 $QBT_MARKER).Trim() } else { '-' }
    $qbt = if (-not (Test-Path $QBT_INI)) { 'not installed' }
           else {
               $qbtLines = (Read-Utf8 $QBT_INI) -split '\r?\n'
               $qbtOn = "$(Get-IniKey $qbtLines 'Preferences' 'General\UseCustomUITheme')".Trim() -eq 'true'
               $qbtSel = Test-QbtThemePath (Get-IniKey $qbtLines 'Preferences' 'General\CustomUIThemePath') $qbtCfg
               if ((Test-Path $qbtCfg) -and (Test-Path (Join-Path $QBT_THEME_DIR 'stylesheet.qss')) -and $qbtOn -and $qbtSel) { 'themed' }
               else { 'found, not themed' }
           }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'qbittorrent', 'qBittorrent', $qbt, $qbtPal)

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

    $nppConfigDir = Join-Path $env:APPDATA 'Notepad++'
    $npp = if (Test-Path $nppConfigDir) {
        if (Test-Path (Join-Path $nppConfigDir 'themes\Wintage.xml')) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'notepadplusplus', 'Notepad++', $npp, '-')

    $c4dPath = Get-Cinema4DPath
    $c4d = if ($c4dPath) {
        $c4dSchemes = Get-Cinema4DSchemesDir $c4dPath
        if ($c4dSchemes -and (Test-Path (Join-Path $c4dSchemes 'Wintage\wintage.col'))) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'cinema4d', 'Cinema 4D', $c4d, '-')

    Say ((T 'PalettesLabel') + " $palettes") 'DarkGray'
    Say (T 'HelpOneApp') 'Cyan'
    Say (T 'HelpAll') 'Cyan'
    Say (T 'HelpRevert') 'Cyan'
    Say (T 'RepaintNote') 'DarkGray'
    return
}

# The built output is generated, not committed by hand -- refuse to install a stale
# or missing build rather than silently shipping last week's colours. This is
# TARGET-AWARE (T-189/T-190): only targets that CONSUME desktop/out need the build
# verified, and a missing Node is then a FAIL unless -Force (the user explicitly
# accepted unverified/stale generated output). For `-Target all` the check is NOT
# global (T-190): each build-consuming target verifies its own prerequisites at
# dispatch, absent ones SKIP, and unrelated native/source-tree targets execute.
$BUILD_CONSUMING = @($TARGETS.Keys) + @($ELECTRON.Keys) + @('windows', 'browsers', 'obs', 'discord', 'obsidian', 'qbittorrent', 'notepadplusplus', 'cinema4d')

# For an EXPLICIT build-consuming target the global check still applies: the user
# asked for exactly this target, so an unverifiable build aborts before dispatch.
if ($Target -in $BUILD_CONSUMING -and $Target -ne 'all') {
    if ($node) {
        & node (Join-Path $root 'tools/build-desktop.js') --check 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            if (-not $Force) { throw (T 'BuildStale') }
            Say (T 'BuildStaleForce') 'Yellow'
        }
    }
    elseif (-not $Force) {
        throw (T 'NodeNotFoundBuild')
    }
}

# For `-Target all`, run the build check ONCE and cache it; the dispatch loop
# applies it per PRESENT build-consuming target (T-190).
$allBuildCurrent = $null   # $null = unknown (no node), $true/$false = check result
if ($Target -eq 'all' -and $node) {
    & node (Join-Path $root 'tools/build-desktop.js') --check 2>&1 | Out-Null
    $allBuildCurrent = ($LASTEXITCODE -eq 0)
}

# Every target that is neither a VS Code extension nor an Electron app -- i.e. one
# with its own Invoke-* handler. Declared ONCE, because the hand-kept version of
# this list silently dropped five targets: codenomad, discord, totalcmd, totalcmd2
# and obsidian were all reachable individually but were skipped by `-Target all`,
# so "everything" quietly meant nine of fourteen.
$SIMPLE = @('windows', 'browsers', 'mpchc', 'terminal', 'conhost', 'obs', 'discord', 'totalcmd', 'totalcmd2', 'obsidian', 'qbittorrent', 'notepadplusplus', 'cinema4d')

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

# PERF-005 (T-240): the batch set. Split, trimmed, de-duplicated and validated
# against the known set -- an unknown name is a hard error, never a silent
# skip, because a GUI typo that quietly themes nothing is worse than a failed
# run.
$selectedList = @()
if ($Selected) {
    $selectedList = @($Selected -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $selectedList.Count) { throw '-Selected is empty - pass a comma-separated target list (e.g. -Selected "vscode,obs").' }
    # De-duplicate keeping first-seen order: a doubled name would otherwise run
    # the target twice behind one batch flag.
    $seen = @{}
    $selectedList = @($selectedList | Where-Object { -not $seen.ContainsKey($_) -and ($seen[$_] = $true) })
    $unknown = @($selectedList | Where-Object { $known -notcontains $_ })
    if ($unknown.Count) { throw "-Selected names unknown target(s): $($unknown -join ', ') (known: $($known -join ', '))." }
}

$names = if ($Target -eq 'all') { $known } elseif ($selectedList.Count) { $selectedList } else { @($Target) }

# PERF-005 (T-240): a -Selected batch shares ONE build verification across the
# whole batch, exactly as `-Target all` already does with $allBuildCurrent.
# The dispatch loop below applies it per PRESENT build-consuming target.
$selectedBuildCurrent = $null   # $null = unknown (no node), $true/$false = check result
if ($selectedList.Count -and $node) {
    & node (Join-Path $root 'tools/build-desktop.js') --check 2>&1 | Out-Null
    $selectedBuildCurrent = ($LASTEXITCODE -eq 0)
}

# Strict-target semantics (T-189): an explicitly-requested target (or a
# manifest-recorded one reached via -Reapply) must not silently skip an absent
# prerequisite — absence is a FAIL there, while `-Target all` legitimately SKIPs
# software that simply is not installed. Handlers consult $script:StrictTarget.
# A -Selected batch is explicit too: every name in it was asked for by name.
$script:StrictTarget = ($Target -and $Target -ne 'all') -or $selectedList.Count -gt 0

$dispatchFailures = @()
# SRC-006:R005: targets this child declined because the live manifest entry no
# longer matched the planned -ExpectedIntent. Zero mutation happened for each.
$staleSkips = @()

function Save-FreeBuffPatchState([string]$resources) {
    $orchestrator = Join-Path $resources 'orchestrator\orchestrator.js'
    $index = Join-Path $resources 'orchestrator\ui\index.html'
    $bundle = $null
    if (Test-Path $index) {
        $match = [regex]::Match((Read-Utf8 $index), 'assets/(index-[A-Za-z0-9_-]+\.js)')
        if ($match.Success) { $bundle = Join-Path $resources ('orchestrator\ui\assets\' + $match.Groups[1].Value) }
    }
    $assets = Join-Path $resources 'orchestrator\ui\assets'
    $chime = if (Test-Path $assets) { Get-ChildItem $assets -Filter 'chime-*.mp3' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } else { $null }
    $paths = @($orchestrator, $bundle, $(if ($chime) { $chime.FullName })) | Where-Object { $_ }
    @($paths | ForEach-Object {
        [pscustomobject]@{
            Path = $_
            Exists = (Test-Path $_)
            Bytes = if (Test-Path $_) { [System.IO.File]::ReadAllBytes($_) } else { $null }
        }
    })
}

function Restore-FreeBuffPatchState($state) {
    foreach ($item in @($state)) {
        if ($item.Exists) {
            $parent = Split-Path $item.Path -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            [System.IO.File]::WriteAllBytes($item.Path, $item.Bytes)
        } elseif (Test-Path $item.Path) {
            Remove-Item $item.Path -Force
        }
    }
}

foreach ($name in $names) {
    $targetLock = $null
    try {
        # T-191: the WHOLE DISCOVER..COMMIT for one target lives under a named
        # per-target mutex, so two processes cannot mutate the same target
        # concurrently. Lock order is TARGET -> MANIFEST (never reversed).
        $targetLock = Enter-TargetLock $name

        # P0#1: validate the manifest BEFORE any real mutation. A corrupt
        # installed.json must abort with ZERO target changes, not mutate the
        # target and then fail the manifest commit.
        $manifestAtLock = Read-Manifest

        # SRC-006:R005: intent revalidation. Between the Reapply parent's
        # snapshot and THIS lock acquisition, a Revert or an explicit palette
        # change may have won the race. Serialization protects the mutation,
        # not the intent, so a stale or missing entry means ZERO target
        # mutation, ZERO recovery mutation, ZERO manifest mutation: the child
        # reports the skip and exits successfully. A corrupt manifest still
        # fails closed through Read-Manifest above.
        if ($ExpectedIntent) {
            $entryAtLock = if ($manifestAtLock.ContainsKey($name)) { $manifestAtLock[$name] } else { $null }
            $intentAtLock = Get-ReapplyIntentToken $entryAtLock
            if ($intentAtLock -ne $ExpectedIntent) {
                if (-not $Quiet) { Say "$name`: stale Reapply intent skipped - the manifest entry changed after this Reapply was planned (a Revert or palette change won the race); nothing was mutated." 'Yellow' }
                $staleSkips += $name
                continue
            }
        }

    # T-190: for `-Target all` (and PERF-005 -Selected batches), a PRESENT
    # build-consuming target needs a verifiable current build; absent
    # build-consuming targets are skipped by their own handlers.
    # Native/source-tree targets are never blocked.
    if (($Target -eq 'all' -or $selectedList.Count) -and $name -in $BUILD_CONSUMING -and -not $Force) {
        $present = Get-TargetCurrentPath $name
        if (-not $present -and $TARGETS.ContainsKey($name)) { $present = $TARGETS[$name].Dir }
        if ($present) {
            if (-not $node) { throw "${name}: cannot verify the generated build without Node (use -Force to accept unverified output)." }
            $batchCurrent = if ($Target -eq 'all') { $allBuildCurrent } else { $selectedBuildCurrent }
            if ($batchCurrent -eq $false) { throw "${name}: the generated build is stale - run 'node tools/build-desktop.js' (or use -Force)." }
        }
    }

    if ($name -eq 'windows') { Invoke-WindowsTheme -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'browsers') {
        $browserTool = Join-Path $root 'tools/install-browsers.ps1'
        $browserArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $browserTool, '-Palette', $Palette, '-StageRoot', $BrowserStageRoot)
        if ($PortableBrowserRoot) { $browserArgs += @('-PortableRoot', $PortableBrowserRoot) }
        if ($BrowserCatalog) { $browserArgs += @('-Catalog', $BrowserCatalog) }
        if ($NoBrowserLaunch) { $browserArgs += '-NoLaunch' }
        if ($Revert) { $browserArgs += '-Revert' }
        if ($WhatIfPreference) { $browserArgs += '-WhatIf' }
        # T-191 P0#10: the stage root is a directory the target OWNS wholesale
        # (manifest.json + .wintage-palette + any subdirectories the tool stages).
        # Snapshot it before the tool runs so a failed manifest commit can restore
        # the exact pre-operation stage, never a half-written one.
        # SRC-005 W2-002: the CHILD INVOCATION itself is part of the mutation
        # and runs INSIDE the commit scriptblock. It used to run before the
        # wrapper, so a nonzero child exit (or the strict-profile refusal)
        # AFTER the child had already altered the stage threw past the
        # snapshot: the stage stayed half-written and the manifest unchanged.
        # Now every post-snapshot terminating error restores the captured
        # pre-stage through the rollback callback before failing.
        $preStage = Save-DirPreState $BrowserStageRoot
        Invoke-TargetCommit 'browsers' 'Chromium browsers' {
            $script:browserOut = & powershell @browserArgs 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Browser theme installer failed.' }
            if (-not $Revert -and $script:StrictTarget -and ($script:browserOut -match 'no installed or portable profiles')) {
                throw 'browsers: no Chromium profiles found - expected to be present (strict target), refusing to record an install.'
            }
            if ($Revert) {
                Remove-ManifestEntry 'browsers'
            } else {
                Set-ManifestEntry 'browsers' $Palette $BrowserStageRoot 'n/a' (Get-PayloadVersion)
            }
        } { Restore-DirPreState $BrowserStageRoot $preStage }
        # W2-004: remember a validated portable browser root for later runs.
        if (-not $Revert -and $PortableBrowserRoot) { Save-PathPreference 'portable' $PortableBrowserRoot }
        continue
    }
    if ($name -eq 'mpchc') { Invoke-MpcHc -DoRevert:$Revert; continue }
    if ($name -eq 'terminal') { Invoke-WindowsTerminal -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'conhost') { Invoke-Conhost -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'obs') { Invoke-Obs -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'qbittorrent') { Invoke-Qbittorrent -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'discord') { Invoke-BetterDiscord -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd') { Invoke-TotalCmd -Index 1 -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'totalcmd2') { Invoke-TotalCmd -Index 2 -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'obsidian') { Invoke-Obsidian -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'notepadplusplus') { Invoke-NotepadPlusPlus -DoRevert:$Revert -PaletteSlug $Palette; continue }
    if ($name -eq 'cinema4d') { Invoke-Cinema4D -DoRevert:$Revert -PaletteSlug $Palette; continue }

                # ---- Electron targets ----
    if ($ELECTRON.ContainsKey($name)) {
        $e = $ELECTRON[$name]
        if ($name -eq 'codenomad') { Remove-DeadCodeNomadCss }
        if (-not (Test-ElectronApp $e.Resources)) {
            # Absent app: SKIP under `-Target all`, FAIL for an explicit/recorded
            # target that is expected to exist (T-189).
            if ($script:StrictTarget) { throw "$($e.Name): expected to be present but its archive cannot be found - refusing to continue." }
            Say "$($e.Name): not installed on this machine - skipped." 'DarkYellow'
            continue
        }
        if (-not $node) { throw "$($e.Name): needs node to read the app's package.json out of app.asar." }

        $script = Join-Path $root 'tools/install-electron.js'
        $nodeArgs = @($script, '--resources', $e.Resources)
        if ($e.InPlace) { $nodeArgs += '--in-place' }
        # Test seam: an env override lets fixtures point the mandatory FreeBuff
        # post-step at a fake app or at a deliberately missing path.
        $adPatch = if ($env:WINTAGE_FREEBUFF_PATCH_PATH) { $env:WINTAGE_FREEBUFF_PATCH_PATH } else { Join-Path $root 'desktop/patch-freebuff-ads.js' }

        if ($Revert) {
            # FreeBuff owns TWO layers (the Electron shim AND the ad/sound patch on
            # the bundle), so Revert must undo both before the manifest goes away
            # (T-189). Any failure keeps the manifest and returns nonzero.
            if ($PSCmdlet.ShouldProcess($e.Resources, 'Remove the Wintage shim and (for FreeBuff) the ad/sound patch')) {
                # T-192 P2/B: snapshot the THEMED state before the revert so a failed
                # manifest transition can restore it instead of leaving the app
                # unthemed while the manifest still claims an install.
                $elSnap = Save-ElectronStateSnapshot $name -Operation 'Revert'
                $fbPatchSnap = if ($name -eq 'freebuff') { Save-FreeBuffPatchState $e.Resources } else { $null }
                $revertFailures = @()
                if ($name -eq 'freebuff') {
                    if (Test-Path $adPatch) {
                        & node $adPatch --revert
                        if ($LASTEXITCODE -ne 0) { $revertFailures += 'patch-freebuff-ads --revert' }
                    } else {
                        $revertFailures += 'missing patch-freebuff-ads helper'
                    }
                }
                if (-not $revertFailures.Count) {
                    & node $nodeArgs --revert
                    if ($LASTEXITCODE -ne 0) { $revertFailures += 'install-electron --revert' }
                }
                if ($revertFailures.Count) {
                    if ($name -eq 'freebuff' -and $fbPatchSnap) { Restore-FreeBuffPatchState $fbPatchSnap }
                    if ($elSnap) { Restore-ElectronStateSnapshot $name $elSnap }
                    if ($elSnap) { Remove-Item $elSnap -Recurse -Force -ErrorAction SilentlyContinue }
                    throw "$($e.Name): revert INCOMPLETE ($($revertFailures -join ', ')) - the manifest and recovery evidence are kept."
                }
                Invoke-TargetCommit $name $e.Name {
                    Remove-ManifestEntry $name
                } {
                    if ($name -eq 'freebuff' -and $fbPatchSnap) { Restore-FreeBuffPatchState $fbPatchSnap }
                    if ($elSnap) { Restore-ElectronStateSnapshot $name $elSnap }
                }
                if ($elSnap) { Remove-Item $elSnap -Recurse -Force -ErrorAction SilentlyContinue }
            }
            continue
        }
        if ($WhatIfPreference) {
            # Dry-run is a validation pass too: a failing helper must fail the
            # parent, or -WhatIf reports a plan the real apply cannot honour.
            & node $nodeArgs --palette $Palette --dry-run
            if ($LASTEXITCODE -ne 0) { throw "$($e.Name): dry-run FAILED ($LASTEXITCODE) - see the message above." }
            if ($name -eq 'freebuff') {
                # FreeBuff WhatIf validates BOTH layers (T-189/T-190) with the
                # IDENTICAL patch args the real apply would use.
                if (-not (Test-Path $adPatch)) { throw 'FreeBuff: patch-freebuff-ads.js is missing - the mandatory post-step cannot be validated.' }
                $fbPatchArgs = Get-FreeBuffPatchArgs
                & node $adPatch @fbPatchArgs --dry-run
                if ($LASTEXITCODE -ne 0) { throw "FreeBuff: ad/sound patch dry-run FAILED ($LASTEXITCODE) - see the message above." }
            }
            continue
        }
        if ($PSCmdlet.ShouldProcess($e.Resources, $action)) {
            # FreeBuff is atomic AS A WHOLE (T-190): BOTH layers are preflighted
            # before ANY mutation, and if the second layer fails the first is
            # restored to its exact pre-operation state (never a blind --revert,
            # which would uninstall a valid previously-themed install).
            $fbPatchArgs = @()
            if ($name -eq 'freebuff') {
                if (-not (Test-Path $adPatch)) { throw 'FreeBuff: patch-freebuff-ads.js is missing - the mandatory ad/sound post-step cannot run, so the target is NOT recorded as installed.' }
                $fbPatchArgs = Get-FreeBuffPatchArgs
                & node $nodeArgs --palette $Palette --dry-run
                if ($LASTEXITCODE -ne 0) { throw "FreeBuff: Electron dry-run FAILED ($LASTEXITCODE) - nothing was changed." }
                & node $adPatch @fbPatchArgs --dry-run
                if ($LASTEXITCODE -ne 0) { throw "FreeBuff: ad/sound patch dry-run FAILED ($LASTEXITCODE) - nothing was changed." }
            }
            # T-192 P2/B: snapshot the EXACT owned pre-state for EVERY Electron
            # target (not just FreeBuff) so a failed manifest commit rolls the
            # app back instead of leaving it themed with an old manifest.
            # SRC-006:R007: the snapshot class follows the state machine truth
            # from Get-ElectronStatus, never a re-inferred layout. A palette
            # repaint of a HEALTHY themed target (themed-relocated /
            # themed-inplace) can only mutate small sidecars, so it takes the
            # lightweight -Operation Repaint snapshot; stock, updated-*,
            # ambiguous repair paths and Revert keep the full archive-safe
            # pre-state.
            $elSnapOperation = 'Apply'
            $elStatus = Get-ElectronStatus $name
            if ($elStatus -and $elStatus.state -in @('themed-relocated', 'themed-inplace')) {
                $elSnapOperation = 'Repaint'
            }
            $elSnap = Save-ElectronStateSnapshot $name -Operation $elSnapOperation
            & node $nodeArgs --palette $Palette
            if ($LASTEXITCODE -ne 0) {
                # W2-003: the parent owns an independent snapshot precisely so
                # a child failure (or the child's own failed rollback, CORE-001)
                # does not destroy the user's original installation. Restore
                # from $elSnap FIRST, only delete it once the restore succeeded
                # (or failed with a recoverable error).
                if ($elSnap) {
                    $parentRestoreErr = $null
                    try {
                        Restore-ElectronStateSnapshot $name $elSnap
                    } catch {
                        $parentRestoreErr = $_.Exception.Message
                    }
                    if ($parentRestoreErr) {
                        throw "$($e.Name): apply FAILED ($LASTEXITCODE) AND parent restore INCOMPLETE ($parentRestoreErr). Pre-apply snapshot preserved at $elSnap for manual recovery."
                    }
                    Remove-Item $elSnap -Recurse -Force -ErrorAction SilentlyContinue
                }
                throw "$($e.Name): apply FAILED ($LASTEXITCODE) - parent restored the exact pre-Apply state from its independent snapshot. See the message above."
            }
            if ($name -eq 'freebuff') {
                & node $adPatch @fbPatchArgs
                if ($LASTEXITCODE -ne 0) {
                    Restore-ElectronStateSnapshot $name $elSnap
                    Remove-Item $elSnap -Recurse -Force -ErrorAction SilentlyContinue
                    throw 'FreeBuff: shim applied but the ad/sound patch FAILED - the Electron layer was restored to its exact pre-operation state; the manifest was NOT updated. Run patch-freebuff-ads.js --scan to see what this build carries.'
                }
            }
            Say "  Restart $($e.Name) to see it. Undo: .\install.ps1 -Target $name -Revert" 'DarkGray'
            $appVer = 'n/a'
            try {
                $verOut = & node $nodeArgs --version 2>$null
                if ($LASTEXITCODE -eq 0 -and $verOut) { $appVer = $verOut.Trim() }
            } catch {}
            Invoke-TargetCommit $name $e.Name {
                Set-ManifestEntry $name $Palette $e.Resources $appVer (Get-PayloadVersion)
            } {
                if ($elSnap) { Restore-ElectronStateSnapshot $name $elSnap }
            }
            if ($elSnap) { Remove-Item $elSnap -Recurse -Force -ErrorAction SilentlyContinue }
            # W2-004: a validated explicit portable override is remembered here so
            # a later run without the flag resolves the same installation.
            if ($name -eq 'codenomad' -and $CodeNomadPath) { Save-PathPreference 'codenomad' $CodeNomadPath }
            if ($name -eq 'workbuddy' -and $WorkBuddyPath) { Save-PathPreference 'workbuddy' $WorkBuddyPath }
            if ($name -eq 'zcode' -and $ZCodePath) { Save-PathPreference 'zcode' $ZCodePath }
            Say "  Recorded in $ManifestPath" 'DarkGray'
        }
        continue
    }

    $t = $TARGETS[$name]

    if (-not (Test-Path $t.Dir)) {
        if ($script:StrictTarget) { throw "$($t.Name): extensions directory not found ($($t.Dir)) - refusing to continue (strict target)." }
        Say "$($t.Name): extensions directory not found ($($t.Dir)) - skipped." 'DarkYellow'
        continue
    }

    $dest = Join-Path $t.Dir 'wintage-themes'

    # T-192 P1#15: persistent recovery under WINTAGE_APPDATA/recovery/<target>,
    # NEVER under the pruned timestamped backup tree. recovery.json records WHO
    # the directory is: 'replaced' (a pre-existing user folder was swapped) or
    # 'created' (Wintage made it from nothing). Revert restores 'replaced' exactly
    # and removes 'created'; repaint never overwrites the captured pristine.
    $recoveryDir = Join-Path $WintageAppData "recovery\$name"
    $recoveryMeta = Join-Path $recoveryDir 'recovery.json'
    $pristineDir = Join-Path $recoveryDir 'pristine'

    if ($Revert) {
        if (Test-Path $dest) {
            if ($PSCmdlet.ShouldProcess($dest, 'Restore the previous Wintage install')) {
                $preDest = Save-DirPreState $dest
                if (Test-Path $recoveryMeta) {
                    $metaRaw = Read-Utf8 $recoveryMeta
                    try { $meta = $metaRaw | ConvertFrom-Json } catch { throw "$($t.Name): recovery metadata at $recoveryMeta is not valid JSON - refusing to modify the live destination, manifest, or recovery evidence. Fix or delete $recoveryMeta by hand after a backup." }
                    if ($null -eq $meta -or $meta -is [System.Array] -or $meta -is [string] -or $meta -is [int] -or $meta -is [bool]) { throw "$($t.Name): recovery metadata at $recoveryMeta is not a JSON object (got $($meta.GetType().Name)) - refusing to modify the live destination, manifest, or recovery evidence." }
                    if ($null -eq $meta.mode -or $null -eq $meta.target) { throw "$($t.Name): recovery metadata at $recoveryMeta is missing required fields (mode and target are required). Found mode='$($meta.mode)' target='$($meta.target)' - refusing to modify the live destination, manifest, or recovery evidence." }
                    if ($meta.target -ne $name) { throw "$($t.Name): recovery target mismatch at $recoveryMeta (expected '$name', found '$($meta.target)') - refusing to modify the live destination, manifest, or recovery evidence. The recovery file may belong to a different target." }
                    if ($meta.mode -notin @('created', 'replaced')) { throw "$($t.Name): unknown recovery mode '$($meta.mode)' at $recoveryMeta (expected 'created' or 'replaced') - refusing to modify the live destination, manifest, or recovery evidence. Fix the mode or delete the recovery by hand after a backup." }
                        if ($meta.mode -eq 'replaced') {
                        if (-not (Test-Path $pristineDir)) { throw "$($t.Name): recovery mode is 'replaced' but the pristine snapshot is missing at $pristineDir - refusing to modify the live destination, manifest, or recovery evidence. Restore the pristine or delete the recovery by hand after a backup." }
                        $recoveryTombstone = $recoveryDir + '.wintage-retired-' + [guid]::NewGuid().ToString('N')
                        $retiredRecovery = $false
                        try { Move-Item -LiteralPath $recoveryDir -Destination $recoveryTombstone -Force; $retiredRecovery = $true } catch { throw "$($t.Name): recovery epoch retirement failed (cannot rename $recoveryDir) - recovery evidence preserved and no live mutation attempted: $($_.Exception.Message)" }
                        # SRC-006:R004: the retirement rename moved the WHOLE epoch,
                        # pristine included, so the active $pristineDir no longer
                        # exists. Every recovery read after this point must go
                        # through the tombstone.
                        $retiredPristine = Join-Path $recoveryTombstone 'pristine'
                        try {
                            Invoke-TargetCommit $name $t.Name {
                                Remove-Item $dest -Recurse -Force
                                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                                # A legitimately empty original directory is a valid
                                # user state, so an empty pristine restores to an
                                # empty directory instead of erroring on the glob.
                                if (@(Get-ChildItem -LiteralPath $retiredPristine -Force).Count) {
                                    Copy-Item (Join-Path $retiredPristine '*') $dest -Recurse -Force
                                }
                                Remove-ManifestEntry $name
                            } { Restore-DirPreState $dest $preDest }
                            Say "$($t.Name): restored the pre-Wintage directory from $retiredPristine" 'Green'
                            if (Test-Path -LiteralPath $recoveryTombstone) { Remove-Item -LiteralPath $recoveryTombstone -Recurse -Force -ErrorAction SilentlyContinue }
                        } catch {
                            $commitErr = $_
                            try { Restore-DirPreState $dest $preDest } catch { }
                            if ($retiredRecovery -and (Test-Path -LiteralPath $recoveryTombstone) -and -not (Test-Path -LiteralPath $recoveryDir)) {
                                try { Move-Item -LiteralPath $recoveryTombstone -Destination $recoveryDir -Force } catch {
                                    throw "$($t.Name): revert FAILED ($($commitErr.Exception.Message)) AND the retired epoch could not be restored to $recoveryDir - it is preserved at $recoveryTombstone for a manual retry."
                                }
                            }
                            throw $commitErr
                        }
                    } else {
                        $recoveryTombstone = $recoveryDir + '.wintage-retired-' + [guid]::NewGuid().ToString('N')
                        $retiredRecovery = $false
                        try { Move-Item -LiteralPath $recoveryDir -Destination $recoveryTombstone -Force; $retiredRecovery = $true } catch { throw "$($t.Name): recovery epoch retirement failed (cannot rename $recoveryDir) - recovery evidence preserved and no live mutation attempted: $($_.Exception.Message)" }
                        try {
                            Invoke-TargetCommit $name $t.Name {
                                Remove-Item $dest -Recurse -Force
                                Remove-ManifestEntry $name
                            } { Restore-DirPreState $dest $preDest }
                            Say "$($t.Name): removed $dest (Wintage-created, nothing pre-existed to restore)" 'Green'
                            if (Test-Path -LiteralPath $recoveryTombstone) { Remove-Item -LiteralPath $recoveryTombstone -Recurse -Force -ErrorAction SilentlyContinue }
                        } catch {
                            $commitErr = $_
                            try { Restore-DirPreState $dest $preDest } catch { }
                            if ($retiredRecovery -and (Test-Path -LiteralPath $recoveryTombstone) -and -not (Test-Path -LiteralPath $recoveryDir)) {
                                try { Move-Item -LiteralPath $recoveryTombstone -Destination $recoveryDir -Force } catch { }
                            }
                            throw $commitErr
                        }
                    }
                } else {
                    $m = Read-Manifest
                    if ($m.ContainsKey($name)) {
                        throw "$($t.Name): the manifest records an install but the persistent recovery is missing ($recoveryMeta) - refusing a destructive fallback; the directory and the manifest entry are both preserved for recovery evidence. Remove the entry by hand only after confirming the directory contents."
                    }
                    if (Test-LegacyWintageExtension $dest) {
                        # A genuinely identifiable legacy Wintage directory: the
                        # built extension's own package.json proves it.
                        # SRC-005 W2-002: the removal runs INSIDE the commit
                        # scriptblock (same reason as the recovery branches).
                        Invoke-TargetCommit $name $t.Name {
                            Remove-Item $dest -Recurse -Force
                            Remove-ManifestEntry $name
                        } { Restore-DirPreState $dest $preDest }
                        Say "$($t.Name): removed the verified legacy Wintage extension directory $dest" 'Green'
                    } else {
                        Say "$($t.Name): nothing to revert - $dest is not a verified Wintage extension and no recovery state exists; it was left untouched." 'DarkYellow'
                    }
                }
            }
        }
        else { Say "$($t.Name): nothing installed, nothing to revert." }
        continue
    }

    if (-not (Test-Path $t.Built)) { throw "Built output missing: $($t.Built). Run 'node tools/build-desktop.js'." }

    # W2-006: first-touch recovery creation is a WRITE, so it belongs inside the
    # committed Apply branch, after ShouldProcess approves mutation. It used to
    # run BEFORE the gate, so `-WhatIf` -- the dry run whose contract is
    # read-only -- became the first writer of persistent recovery state (or
    # crashed on a recovery.json write whose directory the suppressed
    # New-Item never created). For a real Apply the ordering contract is
    # unchanged: pristine is still captured before the destination is touched.
    if ($PSCmdlet.ShouldProcess($dest, 'Install Wintage themes')) {
        # Capture the pristine ONLY on the first-ever apply of this target. A
        # repaint (dest exists, recovery already captured) must never overwrite
        # the pristine snapshot with Wintage output (P1#15).
        if (-not (Test-Path $recoveryMeta)) {
            New-Item -ItemType Directory -Force -Path $recoveryDir | Out-Null
            # W2-004: a crash between an older direct write and its rename can
            # leave a `.wintage-tmp-*` sibling behind; those orphans are never
            # recovery authority, so sweep them at first-touch.
            Get-ChildItem -LiteralPath $recoveryDir -Filter '*.wintage-tmp-*' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $mode = if (Test-Path $dest) { 'replaced' } else { 'created' }
            if ($mode -eq 'replaced') {
                # W2-004: capture into a temp sibling and promote with one
                # rename, so a crash can never leave a partial pristine that a
                # later Test-Path check would trust. The meta record is written
                # AFTER the pristine exists, so meta-presence implies a complete
                # capture (a replaced-mode pristine that vanished anyway fails
                # closed in Revert, keeping the manifest as evidence).
                $tmpPristine = "$pristineDir.wintage-tmp-" + [guid]::NewGuid().ToString('N')
                New-Item -ItemType Directory -Force -Path $tmpPristine | Out-Null
                try {
                    Copy-Item (Join-Path $dest '*') $tmpPristine -Recurse -Force
                    Move-Item -LiteralPath $tmpPristine -Destination $pristineDir -Force
                } finally {
                    if (Test-Path -LiteralPath $tmpPristine) { Remove-Item -LiteralPath $tmpPristine -Recurse -Force -ErrorAction SilentlyContinue }
                }
                Say "$($t.Name): captured the pre-Wintage folder at $pristineDir (persistent recovery)" 'DarkGray'
            }
            Write-Utf8Atomic $recoveryMeta (@{ mode = $mode; target = $name } | ConvertTo-Json) -ValidateJson
        }
        $preDest = Save-DirPreState $dest
        # W2-004: the transaction covers snapshot -> MUTATE -> manifest commit as
        # ONE operation. The directory creation and the recursive copy used to run
        # BEFORE Invoke-TargetCommit, so a failure mid-copy (a locked file, a full
        # disk) threw past the snapshot taken one line earlier: the extension
        # directory was left half-written and the manifest never recorded it.
        Invoke-TargetCommit $name $t.Name {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item (Join-Path $t.Built '*') -Destination $dest -Recurse -Force
            # W2-004 test seam: fail AFTER the destination was mutated but before
            # the manifest commits. That is the shape the pre-state snapshot
            # exists for, and the shape that used to escape it because the copy
            # ran outside the transaction. Never set outside tests.
            if ($env:WINTAGE_TEST_FAIL_AFTER_EXT_COPY) { throw 'simulated post-copy failure (WINTAGE_TEST_FAIL_AFTER_EXT_COPY)' }
            $count = (Get-ChildItem (Join-Path $dest 'themes') -Filter '*.json').Count
            Say "$($t.Name): installed $count themes -> $dest" 'Green'
            Say "  Pick one: Ctrl+K Ctrl+T, look for 'Wintage ...'. Restart the app if it does not appear." 'DarkGray'
            Set-ManifestEntry $name $Palette $dest 'n/a' (Get-PayloadVersion)
        } { Restore-DirPreState $dest $preDest }
    }

    }
    catch {
        # A target that threw must never read as a green run. Record it, keep
        # applying the remaining siblings, and leave the exit code nonzero.
        Say "$name`: FAILED - $($_.Exception.Message)" 'Red'
        $dispatchFailures += $name
    }
    finally {
        if ($targetLock) { Exit-TargetLock $targetLock }
    }
}

if ($dispatchFailures.Count) {
    Say "Install incomplete: $($dispatchFailures.Count) target(s) failed ($($dispatchFailures -join ', '))." 'Red'
    exit 1
}

# SRC-006:R005 child outcome contract: an -ExpectedIntent-gated child whose run
# ended in pure stale skips (nothing failed, nothing mutated) reports that
# through the dedicated exit code the -Reapply parent maps to STALE_SKIPPED.
# The guard at the top of the script guarantees one explicit target per child,
# so this code has exactly one meaning.
if ($ExpectedIntent -and $staleSkips.Count) { exit $REAPPLY_STALE_EXIT }

exit 0
