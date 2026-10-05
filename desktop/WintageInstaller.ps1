# Wintage Theme Installer - a small Win95-looking GUI over the command-line tools.
#
# WinForms on purpose. The alternative (an Electron or web UI) would mean shipping a
# browser to configure a theme, and this window has to LOOK like the thing it
# installs -- 2px bevels, no antialiasing, no rounded corners, no animation. GDI+
# draws that natively; a web view fights it.
#
# It never reimplements anything: Apply shells out to the same install.ps1 /
# apply-themes.js the terminal uses, so there is exactly one code path that installs
# a theme and the GUI cannot drift away from it.
#
#   .\WintageInstaller.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
# The preview player is SoundPlayer over an ffmpeg-transcoded temp PCM WAV (the
# reliable path on machines where WPF MediaPlayer fails to decode even plain
# PCM). WPF MediaPlayer (System.Windows.Media) remains only as the last-resort
# fallback for machines without ffmpeg. It rides on Media Foundation, so it
# decodes whatever the machine has codecs for (MP3/AAC/M4A/FLAC/OGG on Win10+;
# WMA is deliberately not accepted - the installed file is played by Chromium,
# which cannot decode WMA at all). PresentationCore is part of the desktop .NET
# Framework, present on
# every WinPS 5.1 install, so this Add-Type is safe where System.Media was not.
# NOTE: System.Media.SoundPlayer is NOT Add-Typed here on purpose. The type
# resolves because System.Media.dll is part of WinPS 5.1's default-loaded
# assembly set, and `Add-Type -AssemblyName System.Media` has failed on some 5.1
# installs -- under this script's $ErrorActionPreference = 'Stop' that failure
# would abort the whole window before it opens. Keep this script WinPS-only:
# pwsh does not load System.Media by default and the type would not resolve.
[System.Windows.Forms.Application]::EnableVisualStyles() | Out-Null

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$themeDir = Join-Path $root 'themes'

. (Join-Path $here 'i18n.ps1')

# W2-004 (SRC-007:R009): the canonical owner-aware cross-runtime generation
# lock protocol is ONE shared module, not a GUI-private copy. Enter/Exit-
# BuildGenerationLockCore below are the exact functions install.ps1 runs
# (common.ps1 dot-sources the same file), so GUI publication and CLI batch
# consumption cannot drift apart.
. (Join-Path $here 'modules/generation-lock.ps1')

# W2-005 (SRC-018:R011): the GUI shares the ONE strict paths.json reader with
# the CLI writer, so a present-but-unreadable preferences file fails closed on
# both surfaces instead of being replaced by the GUI's own keys.
. (Join-Path $here 'modules/json-doc.ps1')

# T-257 / SRC-013: scenario presets. The module owns ONLY the preset contract
# (schema validation + atomic, lock-serialized storage under %APPDATA%). It
# hardcodes no token list -- the caller passes the canonical tokens read from
# tools/theme-schema.json below, so a custom snapshot is validated against the
# ONE authoritative list and cannot become a fourth drifting copy (T-187).
. (Join-Path $here 'modules/presets.ps1')

# ---- PALETTE LOADING ----
$script:packs = @{}
function Load-Packs {
    $script:packs = @{}
    $seenSlugs = @{}
    $seenLabels = @{}
    Get-ChildItem $themeDir -Filter '*.json' | ForEach-Object {
        # -Raw + ConvertFrom-Json chokes on a BOM, and packs have carried one before
        # (a PowerShell write elsewhere put it there). Reading as explicit UTF-8 and
        # stripping any leftover mark keeps one stray byte from emptying the theme
        # list with a parse error at startup.
        # \uFEFF, not a literal mark pasted into the pattern -- the literal form is
        # itself encoding-dependent and had already arrived mojibaked once (T-076,
        # same bug in install-electron.js), matching nothing and letting the BOM
        # through to ConvertFrom-Json, which throws and empties the theme list.
        $p = ([System.IO.File]::ReadAllText($_.FullName, (New-Object System.Text.UTF8Encoding($false)))) -replace '^\uFEFF', '' | ConvertFrom-Json
        # Identity rules mirror the generators' validator (tools/theme-schema.js):
        # a duplicate slug or label is a hard error, never a silently-overwritten
        # row, because this GUI resolves selection BY LABEL and the CLI lists packs
        # BY FILENAME -- both would misselect on a collision (T-187).
        if (-not $p.slug) { throw "$($_.Name): no slug in the pack - refusing to load a nameless theme." }
        if ($_.BaseName -ne $p.slug) { throw "$($_.Name): filename does not match pack.slug '$($p.slug)' - the CLI lists by filename while this GUI resolves by label; the two must agree." }
        if ($seenSlugs.ContainsKey($p.slug)) { throw "$($seenSlugs[$p.slug]) and $($_.Name): duplicate slug '$($p.slug)' - refusing to silently overwrite one pack." }
        if (-not $p.label) { throw "$($_.Name): no label." }
        if ($seenLabels.ContainsKey($p.label)) { throw "$($seenLabels[$p.label]) and $($_.Name): duplicate label '$($p.label)' - the GUI resolves selection by label, so two packs sharing one label are indistinguishable." }
        $seenSlugs[$p.slug] = $_.Name
        $seenLabels[$p.label] = $_.Name
        $script:packs[$p.slug] = $p
    }
}
Load-Packs
# goldendefault, matching install.ps1's own -Palette default. Two defaults that
# disagree means the GUI and the terminal install different themes from the same
# "just press go", which is the kind of difference nobody notices until they are
# comparing two machines.
$script:current = if ($script:packs.ContainsKey('goldendefault')) { 'goldendefault' }
                  elseif ($script:packs.ContainsKey('golden')) { 'golden' }
                  else { ($script:packs.Keys | Select-Object -First 1) }
# The custom palette is a working copy, seeded from whatever is selected, so
# "Custom" always starts from something that already looks right instead of black.
$script:custom = $null

# The 21-token schema and the WCAG text-role list are read from the single
# canonical source (tools/theme-schema.json, mirrored from theme-schema.js).
# They used to be a second hardcoded copy that drifted from the generators'
# REQUIRED_TOKENS and from check-css.js's gate -- the GUI warned about
# borderHighlight while the build gate demanded link, so the editor said FAIL
# on palettes the gate accepted. One source, no second list to drift (T-187).
$schemaJson = Join-Path $root 'tools\theme-schema.json'
if (Test-Path $schemaJson) {
    $schema = ([System.IO.File]::ReadAllText($schemaJson, (New-Object System.Text.UTF8Encoding($false)))) | ConvertFrom-Json
} else {
    throw "Canonical theme schema not found at $schemaJson - a schema-less GUI cannot trust its token list."
}
$TOKENS = @($schema.tokens)
$script:wcagRoles = @($schema.wcagRoles)

function Get-ActiveTokens {
    if ($script:current -eq '<custom>') { return $script:custom }
    $t = $script:packs[$script:current].tokens
    $h = @{}
    foreach ($k in $TOKENS) {
        $v = $t.$k
        # A pack written before a token existed (link was the 19th, added late) has no
        # value for it, and $null reaches ColorTranslator::FromHtml, which throws and
        # takes the whole window down on selection. Fall back to a token the pack is
        # guaranteed to have rather than crashing on someone's older custom.json.
        if (-not $v) {
            # Each late-added token falls back to what it REPLACED, not to a generic
            # stand-in: bevelLight took over the bevel edge from borderHighlight, so an
            # older pack keeps the look it had instead of drawing its edges in body text.
            $v = if ($k -eq 'link' -or $k -eq 'bevelLight') { $t.borderHighlight }
                 elseif ($k -eq 'dangerText') { $t.danger }
                 else { $t.textPrimary }
        }
        $h[$k] = $v
    }
    $h
}
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

# WCAG, so the custom editor can warn before something unreadable gets installed.
function Rel([System.Drawing.Color]$c) {
    $f = { param($v) $s = $v / 255.0; if ($s -le 0.03928) { $s / 12.92 } else { [Math]::Pow(($s + 0.055) / 1.055, 2.4) } }
    0.2126 * (& $f $c.R) + 0.7152 * (& $f $c.G) + 0.0722 * (& $f $c.B)
}
function Contrast($a, $b) {
    $x = Rel (C $a); $y = Rel (C $b)
    [Math]::Round((([Math]::Max($x, $y) + 0.05) / ([Math]::Min($x, $y) + 0.05)), 2)
}

# ---- WIN95 DRAWING ----
# Depth is a 2px bevel and nothing else (UI.md law 3): light on top/left, dark on
# bottom/right for raised, swapped for sunken. Drawn by hand because every native
# control style available here has either rounded corners or a gradient.
function Draw-Bevel($g, $rect, $light, $dark, [bool]$raised = $true) {
    # PERF-009: the previous implementation allocated 8 Drawing.Pen instances
    # per bevel and relied on GC/finalization to release them. Reusing two
    # Pens (top-left + bottom-right) per call and disposing them in `finally`
    # keeps the WinForms GDI handle count flat across repeated invalidations.
    $tl = if ($raised) { $light } else { $dark }
    $br = if ($raised) { $dark } else { $light }
    $penTL = $null; $penBR = $null
    try {
        $penTL = New-Object Drawing.Pen $tl
        $penBR = New-Object Drawing.Pen $br
        for ($i = 0; $i -lt 2; $i++) {
            $g.DrawLine($penTL, $rect.Left + $i, $rect.Top + $i, $rect.Right - 1 - $i, $rect.Top + $i)
            $g.DrawLine($penTL, $rect.Left + $i, $rect.Top + $i, $rect.Left + $i, $rect.Bottom - 1 - $i)
            $g.DrawLine($penBR, $rect.Left + $i, $rect.Bottom - 1 - $i, $rect.Right - 1 - $i, $rect.Bottom - 1 - $i)
            $g.DrawLine($penBR, $rect.Right - 1 - $i, $rect.Top + $i, $rect.Right - 1 - $i, $rect.Bottom - 1 - $i)
        }
    } finally {
        if ($penTL) { try { $penTL.Dispose() } catch { } }
        if ($penBR) { try { $penBR.Dispose() } catch { } }
    }
}

$FONT = New-Object Drawing.Font('Verdana', 8.25, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Point)
$FONTB = New-Object Drawing.Font('Verdana', 8.25, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Point)

# ---- FORM ----
$form = New-Object Windows.Forms.Form
$form.Text = (T 'WintageInstallerTitle')
$form.Size = New-Object Drawing.Size(880, 700)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = $FONT
$form.AutoScroll = $true
$work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($form.Width -gt $work.Width -or $form.Height -gt $work.Height) {
    $form.Size = New-Object Drawing.Size ([Math]::Min(880, $work.Width)), ([Math]::Min(700, $work.Height))
}
# R015 / PERF-004 startup instrument: the form records the real Shown event and
# self-closes when a smoke fixture arms the auto-close timer, so a live GUI
# smoke can prove the ordinary (cache-served) startup reaches a usable window
# without the recursive portable walk. Inert without the env var.
#
# The timer lives in the SCRIPT scope: a WinForms Tick callback is re-bound to
# the script scope when the pump invokes it, so a handler-local timer variable
# is null inside its own tick (the same trap the batch lifecycle documents) and
# would surface as an unhandled "call a method on a null-valued expression"
# crash dialog instead of a clean close.
$script:wintageSmokeTimer = $null
$form.Add_Shown({
    $stamp = Join-Path ([System.IO.Path]::GetTempPath()) 'wintage-form-shown.stamp'
    if ($env:WINTAGE_TEST_FORM_SHOWN_FILE) { $stamp = $env:WINTAGE_TEST_FORM_SHOWN_FILE }
    try { [System.IO.File]::WriteAllText($stamp, (Get-Date).ToUniversalTime().ToString('o')) } catch { }
    if ($env:WINTAGE_TEST_AUTOCLOSE_MS) {
        $script:wintageSmokeTimer = New-Object Windows.Forms.Timer
        $script:wintageSmokeTimer.Interval = [int]$env:WINTAGE_TEST_AUTOCLOSE_MS
        $script:wintageSmokeTimer.Add_Tick({
            if ($script:wintageSmokeTimer) { $script:wintageSmokeTimer.Stop() }
            $form.Close()
        })
        $script:wintageSmokeTimer.Start()
    }
})

# ---- TABS & PANELS ----
# T-283 / SRC-026: the tab strip is now DATA-DRIVEN (3+ tabs), not two
# hand-written if-branches. One ordered table owns each tab's key, button and
# panel; Update-TabButtons / Set-ActiveTab iterate it, so adding a tab is one
# row here rather than a new visibility hack. Exactly one panel is ever visible.
$script:activeTab = 'themes'

function New-TabButton([string]$text, [string]$x, [int]$w) {
    $b = New-Object Windows.Forms.Button
    $b.Location = "$x,8"
    $b.Size = "$w,24"
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 2
    $b.Font = $FONT
    $b.Text = $text
    return $b
}

$btnTabThemes = New-TabButton (T 'TabThemes') 12 140
$btnTabBetterDiscord = New-TabButton (T 'TabBetterDiscord') 158 180
$btnTabFonts = New-TabButton (T 'TabFonts') 344 180

$pnlThemes = New-Object Windows.Forms.Panel
$pnlThemes.Location = '0,36'
$pnlThemes.Size = '864,590'
$pnlThemes.BorderStyle = [Windows.Forms.BorderStyle]::None

$pnlBetterDiscord = New-Object Windows.Forms.Panel
$pnlBetterDiscord.Location = '0,36'
$pnlBetterDiscord.Size = '864,550'
$pnlBetterDiscord.BorderStyle = [Windows.Forms.BorderStyle]::None
$pnlBetterDiscord.Visible = $false

$pnlFonts = New-Object Windows.Forms.Panel
$pnlFonts.Location = '0,36'
$pnlFonts.Size = '864,560'
$pnlFonts.BorderStyle = [Windows.Forms.BorderStyle]::None
$pnlFonts.Visible = $false

# Ordered tab table: key -> @{ Button; Panel }. Populated after all panels exist.
$script:tabTable = $null

function Update-TabButtons {
    $t = Get-ActiveTokens
    if (-not $t) { return }
    foreach ($row in $script:tabTable) {
        $active = ($row.Key -eq $script:activeTab)
        $b = $row.Button
        if ($active) {
            # Active tab is SUNKEN (UI.md): pressed bevel + textPrimary.
            $b.BackColor = C $t.surface
            $b.ForeColor = C $t.textPrimary
            $b.FlatAppearance.BorderColor = C $t.borderDark
            $b.Font = $FONTB
        } else {
            # Inactive tab is raised.
            $b.BackColor = C $t.surfaceRaised
            $b.ForeColor = C $t.textSecondary
            $b.FlatAppearance.BorderColor = C $t.borderHighlight
            $b.Font = $FONT
        }
    }
}

function Set-ActiveTab([string]$tab) {
    $known = @($script:tabTable | Where-Object { $_.Key -eq $tab }).Count -gt 0
    if (-not $known) { return }
    $script:activeTab = $tab
    foreach ($row in $script:tabTable) {
        $row.Panel.Visible = ($row.Key -eq $tab)
    }
    Update-TabButtons
    # PERF-001: initialize the terminal-font subsystem on FIRST Fonts-tab entry
    # (not before ShowDialog), then re-probe on later entries so a font installed
    # through Windows' own dialog is reflected without a restart.
    if ($tab -eq 'fonts') {
        if (-not $script:TfInitialized -and (Get-Command Initialize-TfTab -ErrorAction SilentlyContinue)) {
            $script:TfInitialized = $true
            Initialize-TfTab
        } elseif (Get-Command Refresh-TfFonts -ErrorAction SilentlyContinue) {
            Refresh-TfFonts
        }
    }
}

$btnTabThemes.Add_Click({ Set-ActiveTab 'themes' })
$btnTabBetterDiscord.Add_Click({ Set-ActiveTab 'bd' })
$btnTabFonts.Add_Click({ Set-ActiveTab 'fonts' })


# Theme list ------------------------------------------------------------------
$lblThemes = New-Object Windows.Forms.Label
$lblThemes.Text = (T 'Palettes'); $lblThemes.Location = '12,10'; $lblThemes.Size = '200,16'; $lblThemes.Font = $FONTB
$lstThemes = New-Object Windows.Forms.ListBox
$lstThemes.Location = '12,28'; $lstThemes.Size = '200,210'
$lstThemes.BorderStyle = 'FixedSingle'
$lstThemes.DrawMode = 'OwnerDrawFixed'
$lstThemes.ItemHeight = 18
$lstThemes.IntegralHeight = $false

# Targets ---------------------------------------------------------------------
# Personal source/portable apps are a different maintenance surface from common
# installed software. Two real lists keep that distinction visible and keyboard-
# reachable; fake separator rows inside one checklist would be selectable noise.
$MY_APP_KEYS = @('codenomad', 'workbuddy')
$lblMyApps = New-Object Windows.Forms.Label
$lblMyApps.Text = (T 'MyApps'); $lblMyApps.Location = '12,248'; $lblMyApps.Size = '200,16'; $lblMyApps.Font = $FONTB
$clbMyApps = New-Object Windows.Forms.CheckedListBox
$clbMyApps.Location = '12,266'; $clbMyApps.Size = '200,78'
$clbMyApps.BorderStyle = 'FixedSingle'; $clbMyApps.CheckOnClick = $true; $clbMyApps.IntegralHeight = $false

$lblPopularApps = New-Object Windows.Forms.Label
$lblPopularApps.Text = (T 'PopularApps'); $lblPopularApps.Location = '12,352'; $lblPopularApps.Size = '200,16'; $lblPopularApps.Font = $FONTB
$clbPopularApps = New-Object Windows.Forms.CheckedListBox
$clbPopularApps.Location = '12,370'; $clbPopularApps.Size = '200,132'
$clbPopularApps.BorderStyle = 'FixedSingle'; $clbPopularApps.CheckOnClick = $true; $clbPopularApps.IntegralHeight = $false
$TARGET_LISTS = @($clbMyApps, $clbPopularApps)

# ---- REMEMBERED FOLDERS FOR THE SOURCE-TREE TARGETS ----
# Stored under %APPDATA%, deliberately NOT beside the script: the repo is a git
# checkout that gets pulled, moved and re-cloned, and a per-machine preference has
# no business in it (nor in .gitignore, where it would be one more thing to
# remember). A remembered folder that no longer exists is dropped on load rather
# than trusted, so a moved checkout asks once more instead of silently patching
# nothing.
# CORE-004 (audit/7.md): the GUI owns exactly the three path-bearing targets
# that have no reliable default discovery - zcode, notepadplusplus and cinema4d.
# codenomad/workbuddy/portable are CLI-owned (install.ps1 Save-PathPreference):
# the GUI must never write over them, which Save-CustomPaths below already
# guarantees by merging every non-owned key byte-for-byte. One canonical mapping
# drives the prompt targets, the dialog defaults and the batch argument
# forwarding, so a newly path-bearing target cannot be silently omitted.
$script:PATH_TARGETS_MAP = [ordered]@{
    zcode           = @{ Default = (Join-Path $env:LOCALAPPDATA 'Programs\ZCode\resources'); Param = '-ZCodePath' }
    notepadplusplus = @{ Default = (Join-Path $env:APPDATA 'Notepad++'); Param = '-NotepadPlusPlusPath' }
    cinema4d        = @{ Default = 'C:\Program Files\Maxon Cinema 4D 2026'; Param = '-Cinema4DPath' }
    processexplorer = @{ Default = (Join-Path $env:ProgramFiles 'Sysinternals'); Param = '-ProcessExplorerPath' }
}
$PATH_TARGETS = @($script:PATH_TARGETS_MAP.Keys)
$PATH_DEFAULTS = @{}
foreach ($k in $script:PATH_TARGETS_MAP.Keys) { $PATH_DEFAULTS[$k] = $script:PATH_TARGETS_MAP[$k].Default }
$script:wintageAppData = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
$script:pathsFile = Join-Path $script:wintageAppData 'paths.json'
$script:customPaths = @{}
$script:wintageBuildMutex = $null

# W2-004 (T-246:R009): shared generation lock. Same identity as
# install.ps1 Enter-BatchLock: hash(%APPDATA%\Wintage), same mutex name,
# so GUI custom publication and CLI batch consumption are one critical
# section across processes. Also acquires the cross-runtime file lock.
function Enter-BatchLockShared {
    $appData = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
    # W2-002 (audit/7 T-269): the marker is the owning acquisition's token and
    # only a LIVE matching holder is treated as inherited ownership; a forged
    # or stale marker acquires normally instead of bypassing serialization.
    if (Test-GenerationLockInheritance -AppData $appData -Marker $env:WINTAGE_BUILD_LOCK_HELD) { return $null }
    $mutex = $null
    $genLock = $null
    try {
        $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($appData))).Replace('-', '').Substring(0, 20)
        $name = "Local\Wintage-Build-$hash"
        $mutex = New-Object System.Threading.Mutex($false, $name)
        $got = $false
        try { $got = $mutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { $got = $true } catch { $got = $false }
        if (-not $got) { try { $mutex.Dispose() } catch { }; throw "W2-004: build/output busy - batch/config lock contended (timeout 15s) at $hash. Retry; if recurring, clear stale Wintage-Build mutex." }
        # W2-004 (SRC-007:R009): the file-lock half runs the CANONICAL
        # owner-aware protocol (shared with install.ps1 via generation-lock.ps1):
        # no age-only stealing, ownerCreated PID-reuse guard, token-minted
        # metadata, ownership-verified release.
        $genLock = Enter-BuildGenerationLockCore $appData
        $obj = New-Object PSObject
        $obj | Add-Member -MemberType NoteProperty -Name Mutex -Value $mutex
        $obj | Add-Member -MemberType NoteProperty -Name GenLock -Value $genLock
        return $obj
    } catch {
        if ($mutex) { try { $mutex.Dispose() } catch { } }
        if ($genLock) { try { Exit-BuildGenerationLockCore $genLock } catch { } }
        throw
    }
}

function Exit-BatchLock($lockObj) {
    if (-not $lockObj) { return }
    try { if ($lockObj.GenLock) { Exit-BuildGenerationLockCore $lockObj.GenLock } } catch { }
    try { if ($lockObj.Mutex) { $lockObj.Mutex.ReleaseMutex(); $lockObj.Mutex.Dispose() } } catch { }
}

function Load-CustomPaths {
    $script:customPaths = @{}
    if (-not (Test-Path $script:pathsFile)) { return }
    try {
        $saved = ([System.IO.File]::ReadAllText($script:pathsFile, (New-Object System.Text.UTF8Encoding($false)))) -replace '^\uFEFF', '' | ConvertFrom-Json
        foreach ($k in $PATH_TARGETS) {
            $v = $saved.$k
            if ($v -and (Test-Path $v)) { $script:customPaths[$k] = $v }
        }
    }
    catch {
        # A corrupt preferences file must never be the reason the installer will not
        # open. Forget it and ask again.
    }
}

function Save-CustomPaths {
    $lockStream = $null
    try {
        $dir = Split-Path $script:pathsFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        # W2-007: paths.json is read-modify-written by TWO processes -- this window
        # and install.ps1's Save-PathPreference. The atomic temp+rename below
        # prevents torn JSON but not a LOST UPDATE: if both read state S, each
        # merges its own keys into S and the second rename silently deletes the
        # other's freshly added key, while both report success. The whole
        # read -> merge -> write -> replace sequence therefore runs under the same
        # named lock file the CLI writer takes (%APPDATA%\Wintage\paths.lock).
        # Bounded retry, never an indefinite wait: a crashed holder's handle is
        # already released by the OS, so a stuck lock means a live writer.
        $lockPath = Join-Path $dir 'paths.lock'
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            try {
                $lockStream = [System.IO.File]::Open($lockPath,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None)
                break
            }
            catch [System.IO.IOException] {
                Start-Sleep -Milliseconds (10 + (Get-Random -Maximum 40))
            }
        }
        if ($null -eq $lockStream) { throw "could not acquire the paths.json lock at $lockPath after 100 attempts." }
        # paths.json has two writers. The GUI owns $PATH_TARGETS; install.ps1 owns
        # the rest of common.ps1's canonical key set (codenomad, workbuddy,
        # portable). Rebuilding the file from $PATH_TARGETS alone DELETED every
        # CLI-owned key the next time anyone picked a folder here, so a remembered
        # portable-browser root or WorkBuddy install silently disappeared on an
        # unrelated save (T-196). Read what is on disk, keep every key this surface
        # does not own byte-for-byte, and write only our own from live state -- a
        # GUI key whose folder vanished is still dropped, which is the load-time
        # contract above. The read happens AFTER the lock is held, so the merge is
        # based on the latest committed state rather than a pre-lock snapshot.
        $o = [ordered]@{}
        # W2-005 (SRC-018:R011): absent initializes; valid merges preserving
        # every key this surface does not own; present-but-unreadable FAILS
        # CLOSED rather than being replaced by the GUI's own keys.
        $document = Read-OwnedJsonDocument $script:pathsFile
        if (-not $document.Ok) { throw (Format-OwnedJsonRefusal 'paths.json' $document) }
        if ($document.Exists) {
            foreach ($prop in $document.Value.PSObject.Properties) {
                if ($prop.Name -in $PATH_TARGETS) { continue }
                $o[$prop.Name] = $prop.Value
            }
        }
        foreach ($k in $PATH_TARGETS) { if ($script:customPaths.ContainsKey($k)) { $o[$k] = $script:customPaths[$k] } }
        # W2-007 test seam: widen the read -> write window so a concurrency gate
        # can prove the lock is what serialises this update. Never set outside
        # tests. (The CLI writer carries the same seam.)
        if ($env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS) { Start-Sleep -Milliseconds ([int]$env:WINTAGE_TEST_PATHS_WRITE_DELAY_MS) }
        $json = ($o | ConvertTo-Json)
        # Atomic write, same contract as the CLI manifest: a half-written
        # paths.json must never replace a good one, so the new content lands in a
        # sibling and is moved into place only after it is fully on disk (T-191).
        $tmp = Join-Path $dir ("paths.json.tmp-" + [guid]::NewGuid().ToString('N'))
        try {
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
            Move-Item -LiteralPath $tmp -Destination $script:pathsFile -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    catch {
        $message = "could not save paths.json: $($_.Exception.Message)"
        if (Get-Command Say-Log -CommandType Function -ErrorAction SilentlyContinue) { Say-Log $message }
        else { Write-Warning $message }
        return $false
    }
    finally {
        if ($lockStream) { $lockStream.Dispose() }
    }
    return $true
}

# $true if a folder is now known for this target, $false if the user backed out.
# W2-007: a failed SAVE also returns $false. The previous form called
# Save-CustomPaths and returned $true unconditionally, so a persistence failure
# left the target checked and logged "folder set to ..." for a path that lives
# only in this session -- session and disk disagreeing with nothing on screen
# saying so. The in-memory value is rolled back to what it was, because the
# caller's contract is "a folder is now KNOWN for this target", and a value that
# will not survive the window is not known.
function Ask-CustomPath([string]$key) {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select folder for $key"
    $dlg.SelectedPath = if ($script:customPaths.ContainsKey($key)) { $script:customPaths[$key] } else { $PATH_DEFAULTS[$key] }
    if ($dlg.ShowDialog() -ne 'OK') { return $false }
    $had = $script:customPaths.ContainsKey($key)
    $previous = if ($had) { $script:customPaths[$key] } else { $null }
    $script:customPaths[$key] = $dlg.SelectedPath
    if (-not (Save-CustomPaths)) {
        if ($had) { $script:customPaths[$key] = $previous } else { $script:customPaths.Remove($key) }
        return $false
    }
    return $true
}

Load-CustomPaths

# CORE-002 (audit/7.md): selecting a preset is never an explicit path action, so
# the ItemCheck handler must not open a folder dialog while preset state is
# being restored. The flag is raised only around that restoration.
$script:suppressPathPrompt = $false
$onTargetCheck = {
    param($sender, $e)
    if ($e.NewValue -eq 'Checked' -and -not $script:suppressPathPrompt) {
        $key = ($sender.Items[$e.Index] -split '\s+')[0]
        if ($key -in $PATH_TARGETS -and -not $script:customPaths.ContainsKey($key) -and -not (Ask-CustomPath $key)) {
            $e.NewValue = 'Unchecked'
        }
    }
    # The FB sound picker belongs to a single freebuff install: it is visible
    # only while the freebuff target is the one checked target.
    Update-FbButtonsVisibility $sender $e.Index $e.NewValue
}
$clbMyApps.Add_ItemCheck($onTargetCheck)
$clbPopularApps.Add_ItemCheck($onTargetCheck)

# Right-click = change the remembered folder. Placed on MouseDown rather than a
# context menu because the row itself is the target and a one-item menu would be
# ceremony; the log line is what confirms it took.
$onTargetMouseDown = {
    param($sender, $e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Right) { return }
    $i = $sender.IndexFromPoint($e.Location)
    if ($i -lt 0) { return }
    $key = ($sender.Items[$i] -split '\s+')[0]
    if ($key -notin $PATH_TARGETS) { return }
    if (Ask-CustomPath $key) { Say-Log ("{0}: folder set to {1}" -f $key, $script:customPaths[$key]) }
}
$clbMyApps.Add_MouseDown($onTargetMouseDown)
$clbPopularApps.Add_MouseDown($onTargetMouseDown)

$btnSelectAll = New-Object Windows.Forms.Button
$btnSelectAll.Text = (T 'SelectAll'); $btnSelectAll.Location = '12,508'; $btnSelectAll.Size = '96,24'; $btnSelectAll.Font = $FONT
$btnSelectAll.FlatStyle = 'Flat'; $btnSelectAll.FlatAppearance.BorderSize = 0

$btnSelectNone = New-Object Windows.Forms.Button
$btnSelectNone.Text = (T 'SelectNone'); $btnSelectNone.Location = '116,508'; $btnSelectNone.Size = '96,24'; $btnSelectNone.Font = $FONT
$btnSelectNone.FlatStyle = 'Flat'; $btnSelectNone.FlatAppearance.BorderSize = 0

# Preview ---------------------------------------------------------------------
$lblPreview = New-Object Windows.Forms.Label
$lblPreview.Text = (T 'Preview'); $lblPreview.Location = '226,10'; $lblPreview.Size = '200,16'; $lblPreview.Font = $FONTB
$preview = New-Object Windows.Forms.Panel
$preview.Location = '226,28'; $preview.Size = '400,300'

# Swatches --------------------------------------------------------------------
$lblTokens = New-Object Windows.Forms.Label
$lblTokens.Text = (T 'Tokens')
$lblTokens.Location = '226,338'; $lblTokens.Size = '420,16'; $lblTokens.Font = $FONTB
$swatchPanel = New-Object Windows.Forms.Panel
$swatchPanel.Location = '226,356'; $swatchPanel.Size = '400,180'
$swatchPanel.AutoScroll = $true

# Right column ----------------------------------------------------------------
$lblInfo = New-Object Windows.Forms.Label
$lblInfo.Location = '640,28'; $lblInfo.Size = '212,300'; $lblInfo.Font = $FONT

$btnApply = New-Object Windows.Forms.Button
$btnApply.Text = (T 'Apply'); $btnApply.Location = '640,330'; $btnApply.Size = '212,34'; $btnApply.Font = $FONTB
$btnApply.FlatStyle = 'Flat'; $btnApply.FlatAppearance.BorderSize = 0

$btnSave = New-Object Windows.Forms.Button
$btnSave.Text = (T 'Save'); $btnSave.Location = '640,370'; $btnSave.Size = '104,26'
$btnSave.FlatStyle = 'Flat'; $btnSave.FlatAppearance.BorderSize = 0

$btnDelCustom = New-Object Windows.Forms.Button
$btnDelCustom.Text = (T 'DelCustom'); $btnDelCustom.Location = '748,370'; $btnDelCustom.Size = '104,26'
$btnDelCustom.FlatStyle = 'Flat'; $btnDelCustom.FlatAppearance.BorderSize = 0

$btnRevert = New-Object Windows.Forms.Button
$btnRevert.Text = (T 'Revert'); $btnRevert.Location = '640,402'; $btnRevert.Size = '212,26'
$btnRevert.FlatStyle = 'Flat'; $btnRevert.FlatAppearance.BorderSize = 0

$chkLogonTask = New-Object Windows.Forms.CheckBox
$chkLogonTask.Text = (T 'LogonTask')
$chkLogonTask.Location = '640,436'; $chkLogonTask.Size = '212,20'
$chkLogonTask.Font = $FONT
$chkLogonTask.FlatStyle = 'Flat'
# SRC-006:R006: UI state assignment and user intent are separate concerns.
# This guard makes every PROGRAMATIC Checked assignment (startup init, failure
# rollback) invisible to the handler; only a real user click may dispatch a
# task command. It must be initialized before the handler below is attached.
$script:suppressLogonTaskEvent = $false
# SRC-006:R006: initialize the checkbox from the REAL task state BEFORE the
# event handler exists. The old order (handler attached at construction, the
# state assignment hundreds of lines later at startup) made the assignment
# itself fire CheckedChanged, so merely OPENING the GUI re-Registered an
# existing logon task as a background side effect.
$existingTask = Get-ScheduledTask -TaskName 'Wintage Reapply at Logon' -ErrorAction SilentlyContinue
if ($existingTask) {
    $script:suppressLogonTaskEvent = $true
    $chkLogonTask.Checked = $true
    $script:suppressLogonTaskEvent = $false
}
# The toggle logic lives in one function so the regression suite can drive it
# deterministically (stubbed child invoker, no WinForms message pump).
function Invoke-LogonTaskToggle {
    param([bool]$Wanted)
    $taskArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'install.ps1'))
    if ($Wanted) {
        $taskArgs += '-RegisterLogonTask'
    } else {
        $taskArgs += '-UnregisterLogonTask'
    }
    $child = Invoke-ChildPowerShell $taskArgs
    if ($child -and $child.Output) {
        foreach ($line in @($child.Output)) { if ($null -ne $line) { Say-Log "$line" } }
    }
    if ($child.ExitCode -ne 0) {
        Say-Log "logon task: FAILED (exit $($child.ExitCode))"
        # SRC-006:R006: roll the checkbox back VISUALLY, under suppression.
        # The old code flipped Checked bare, which re-entered this handler and
        # dispatched the INVERSE task command -- a failed Register issued a
        # real Unregister that could delete a task the user already had.
        $script:suppressLogonTaskEvent = $true
        try { $chkLogonTask.Checked = -not $chkLogonTask.Checked } finally { $script:suppressLogonTaskEvent = $false }
        return $false
    }
    return $true
}
$chkLogonTask.Add_CheckedChanged({
    # SRC-006:R006: programmatic state changes must never reach the task
    # commands; suppressed means some other code path owns this assignment.
    if ($script:suppressLogonTaskEvent) { return }
    Invoke-LogonTaskToggle ([bool]$chkLogonTask.Checked) | Out-Null
})

# ---- FREEBUFF COMPLETION SOUND ----
# The GUI only stores the PREFERENCE; install.ps1 -Target freebuff reads the same
# file and hands it to patch-freebuff-ads.js --sound, so the ads and the sound are
# applied in one run. Stored under %APPDATA%, deliberately NOT in the git checkout
# -- a per-machine wav path has no business in a repo that gets pulled and
# re-cloned, exactly like the remembered source-tree folders above.
#
# Left-click picks an audio file (OpenFileDialog) and plays a preview of it,
# right-click clears it back to stock. COPY saves the file itself into the repo
# (sounds\freebuff.<ext>) and points the preference at that copy -- a picked path
# dies the moment the file is deleted; the repo copy outlives the original.
$script:fbSoundFile = Join-Path $script:wintageAppData 'freebuff-sound.txt'
$script:fbSoundPath = $null
# One script-scoped player (a SoundPlayer for PCM WAV, a WPF MediaPlayer for
# everything else), so picking a new sound stops whatever is still playing
# instead of layering previews on top of each other.
$script:fbSoundPlayer = $null
# Temp PCM WAV owned by the current preview. SoundPlayer.Play() reads from the
# file even after Load(), so the temp must outlive the player - it is deleted in
# Stop-FbSoundPreview, the single point where the player is torn down.
$script:fbPreviewTmp = $null
# Set by the MediaPlayer's async MediaFailed event so the non-WAV preview path
# can still tell "playing" from "could not decode" - Play() itself never throws.
$script:fbPreviewFailed = $false

# PERF-003: the single monotonic request identity. Bumping it invalidates every
# callback still owed by an older preview request (B supersedes A).
$script:fbPreviewGeneration = 0
$script:fbPreviewTimer = $null
$script:fbPreviewFfmpeg = $null
# A candidate is persisted ONLY once playback is verified, and that decision is
# carried by the per-request record below (OnVerified), not by a separate
# pending-path flag: the conversion watcher, the media callbacks and the
# onVerified callback all read the ONE record, so a request that never reaches
# MediaOpened/a clean conversion has no OnVerified to fire and is never saved.
$script:fbPreviewReq = $null

function Stop-FbSoundPreview {
    # Idempotent teardown of the OWNED preview operation: terminate the owned
    # conversion process (never a sibling's), stop/dispose the owned player,
    # remove the owned temp output, invalidate pending callbacks by bumping the
    # generation, stop the timeout timer. A later/stale callback checks the
    # generation before touching any control.
    $script:fbPreviewGeneration += 1
    if ($script:fbPreviewTimer) {
        try { $script:fbPreviewTimer.Stop() } catch { }
        try { $script:fbPreviewTimer.Dispose() } catch { }
        $script:fbPreviewTimer = $null
    }
    if ($script:fbPreviewFfmpeg -and -not $script:fbPreviewFfmpeg.HasExited) {
        try { $script:fbPreviewFfmpeg.Kill() } catch { }
    }
    if ($script:fbPreviewFfmpeg) {
        try { $script:fbPreviewFfmpeg.Dispose() } catch { }
        $script:fbPreviewFfmpeg = $null
    }
    if ($script:fbSoundPlayer) {
        if ($script:fbSoundPlayer -is [System.Media.SoundPlayer]) {
            try { $script:fbSoundPlayer.Stop() } catch { }
            try { $script:fbSoundPlayer.Dispose() } catch { }
        }
        else {
            try { $script:fbSoundPlayer.Stop() } catch { }
            try { $script:fbSoundPlayer.Close() } catch { }
        }
        $script:fbSoundPlayer = $null
    }
    if ($script:fbPreviewTmp) {
        Remove-Item -LiteralPath $script:fbPreviewTmp -Force -ErrorAction SilentlyContinue
        $script:fbPreviewTmp = $null
    }
    # The scoped request record keeps the timer/media callback state readable
    # from the message pump (see the batch-worker scoping note below): tick
    # handlers see ONLY the script scope, never this function's locals. Dropping
    # it here is what makes a superseded request unpersistable.
    $script:fbPreviewReq = $null
    $script:fbPreviewFailed = $false
}
function Get-FbAudioKind([string]$path) {
    # Sniffs the first bytes and returns a known audio container name, or $null
    # when the file is not a recognizable audio format. Byte-exact (-ceq) on the
    # magic, mirroring the patch script's own sniff, so GUI and installer agree
    # on what counts as playable. Kept short on purpose: only enough to say
    # "this is audio" - decoding is left to the player below.
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $head = New-Object byte[] 12
            $n = $fs.Read($head, 0, 12)
            if ($n -lt 4) { return $null }
            $ascii = [System.Text.Encoding]::ASCII.GetString($head, 0, $n)
            if ($n -ge 12 -and $ascii.Substring(0,4) -ceq 'RIFF' -and $ascii.Substring(8,4) -ceq 'WAVE') { return 'wav' }
            if ($ascii.Substring(0,3) -ceq 'ID3') { return 'mp3' }
            if ($n -ge 2 -and $head[0] -eq 0xFF -and ($head[1] -band 0xE0) -eq 0xE0) { return 'mp3' }
            if ($ascii.Substring(0,4) -ceq 'OggS') { return 'ogg' }
            if ($ascii.Substring(0,4) -ceq 'fLaC') { return 'flac' }
            if ($n -ge 8 -and $ascii.Substring(4,4) -ceq 'ftyp') { return 'm4a' }
            return $null
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }
}
# PERF-003: start the owned ffmpeg transcode WITHOUT blocking the GUI thread. Returns
# the owned Process handle; a Form-Timer-driven watcher (Start-FbConversionWatch)
# marshals completion back to the UI thread. The caller stores it in
# $script:fbPreviewFfmpeg so a superseding preview / Stop-FbSoundPreview can
# terminate it.
function Start-FbConvertAsync([string]$path, [string]$tmp) {
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ff) { return $null }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ff.Source
    $psi.Arguments = "-y -v error -i `"$path`" -acodec pcm_s16le -ar 44100 -ac 2 `"$tmp`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    return $p
}

# PERF-003: Forms.Timer-driven watcher for the async ffmpeg transcode. The GUI
# thread never waits: the tick fires on the UI message pump, checks HasExited,
# and only then Load()+Play() the produced PCM. Every branch re-checks the
# request generation first, so a superseding preview (B over A) or a Stop tears
# this request down and a stale completion never touches live state. $onVerified
# is invoked with $true only once playback is really started, $false when this
# request terminally fails (in which case the MediaPlayer fallback takes over).
function Start-FbConversionWatch([int]$generation, [string]$path, [string]$tmp, [string]$name, [scriptblock]$onVerified) {
    if ($script:fbPreviewTimer) {
        try { $script:fbPreviewTimer.Stop() } catch { }
        try { $script:fbPreviewTimer.Dispose() } catch { }
        $script:fbPreviewTimer = $null
    }
    $script:fbPreviewReq = @{
        Gen = $generation; Path = $path; Tmp = $tmp; Name = $name
        OnVerified = $onVerified; Settled = $false
    }
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({
        # Message-pump callback: only the SCRIPT scope is visible here, so all
        # request state lives in $script:fbPreviewReq / $script:fbPreview*.
        $req = $script:fbPreviewReq
        if ($null -eq $req -or $req.Settled -or $req.Gen -ne $script:fbPreviewGeneration) {
            # Superseded, settled, or stopped: this request owns nothing.
            if ($script:fbPreviewTimer) {
                try { $script:fbPreviewTimer.Stop() } catch { }
                try { $script:fbPreviewTimer.Dispose() } catch { }
                $script:fbPreviewTimer = $null
            }
            return
        }
        $p = $script:fbPreviewFfmpeg
        if ($null -ne $p -and -not $p.HasExited) { return }
        $req.Settled = $true
        if ($script:fbPreviewTimer) {
            try { $script:fbPreviewTimer.Stop() } catch { }
            try { $script:fbPreviewTimer.Dispose() } catch { }
            $script:fbPreviewTimer = $null
        }
        $ok = $false
        if ($null -ne $p) {
            $ok = ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $req.Tmp))
            try { $p.Dispose() } catch { }
            if ($script:fbPreviewFfmpeg -eq $p) { $script:fbPreviewFfmpeg = $null }
        }
        if ($ok) {
            try {
                $pl = New-Object System.Media.SoundPlayer $req.Tmp
                $pl.Load()
                $script:fbPreviewTmp = $req.Tmp
                $script:fbSoundPlayer = $pl
                $pl.Play()
                Say-Log "preview: $($req.Name)"
                if ($req.OnVerified) { & $req.OnVerified $true }
                $script:fbPreviewReq = $null
                return
            }
            catch { try { $pl.Dispose() } catch { } }
        }
        # Conversion failed: clean the failed owned temp, then fall back.
        Remove-Item -LiteralPath $req.Tmp -Force -ErrorAction SilentlyContinue
        if ($script:fbPreviewTmp -eq $req.Tmp) { $script:fbPreviewTmp = $null }
        Start-FbMediaPreview $req.Path $req.Name $req.OnVerified
    })
    $script:fbPreviewTimer = $timer
    $timer.Start()
}

# PERF-003: event-driven WPF MediaPlayer fallback. Open() is asynchronous and
# reports decode success/failure through MediaOpened/MediaFailed; a one-shot
# Forms.Timer bounds a player that never answers. No DoEvents, no sleeps -- the
# GUI message queue keeps running throughout. $onVerified fires exactly once per
# request and only while the request still owns the current generation.
function Start-FbMediaPreview([string]$path, [string]$name, [scriptblock]$onVerified) {
    $script:fbPreviewGeneration += 1
    if ($script:fbPreviewTimer) {
        try { $script:fbPreviewTimer.Stop() } catch { }
        try { $script:fbPreviewTimer.Dispose() } catch { }
        $script:fbPreviewTimer = $null
    }
    $script:fbPreviewReq = @{
        Gen = $script:fbPreviewGeneration; Path = $path; Tmp = $null; Name = $name
        OnVerified = $onVerified; Settled = $false
    }
    $script:fbPreviewFailed = $false
    $mp = New-Object System.Windows.Media.MediaPlayer
    $script:fbSoundPlayer = $mp
    $mp.Add_MediaOpened({
        $req = $script:fbPreviewReq
        if ($null -eq $req -or $req.Settled -or $req.Gen -ne $script:fbPreviewGeneration) { return }
        $req.Settled = $true
        if ($script:fbPreviewTimer) {
            try { $script:fbPreviewTimer.Stop() } catch { }
            try { $script:fbPreviewTimer.Dispose() } catch { }
            $script:fbPreviewTimer = $null
        }
        try { $script:fbSoundPlayer.Play() } catch { }
        Say-Log "preview: $($req.Name)"
        if ($req.OnVerified) { & $req.OnVerified $true }
        $script:fbPreviewReq = $null
    })
    $mp.Add_MediaFailed({
        $req = $script:fbPreviewReq
        if ($null -eq $req -or $req.Settled -or $req.Gen -ne $script:fbPreviewGeneration) { return }
        $req.Settled = $true
        if ($script:fbPreviewTimer) {
            try { $script:fbPreviewTimer.Stop() } catch { }
            try { $script:fbPreviewTimer.Dispose() } catch { }
            $script:fbPreviewTimer = $null
        }
        $script:fbPreviewFailed = $true
        if ($script:fbSoundPlayer) { try { $script:fbSoundPlayer.Close() } catch { }; $script:fbSoundPlayer = $null }
        Say-Log "preview failed: $($req.Name) could not be decoded"
        if ($req.OnVerified) { & $req.OnVerified $false }
        $script:fbPreviewReq = $null
    })
    try { $mp.Open((New-Object System.Uri $path)) }
    catch {
        $script:fbSoundPlayer = $null
        Say-Log "preview failed: $($_.Exception.Message)"
        if ($onVerified) { & $onVerified $false }
        $script:fbPreviewReq = $null
        return
    }
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 4000
    $timer.Add_Tick({
        if ($script:fbPreviewTimer) {
            try { $script:fbPreviewTimer.Stop() } catch { }
            try { $script:fbPreviewTimer.Dispose() } catch { }
            $script:fbPreviewTimer = $null
        }
        $req = $script:fbPreviewReq
        if ($null -eq $req -or $req.Settled -or $req.Gen -ne $script:fbPreviewGeneration) { return }
        $req.Settled = $true
        # Timeout: terminate the owned attempt, never guess that it played.
        $script:fbPreviewFailed = $true
        if ($script:fbSoundPlayer) { try { $script:fbSoundPlayer.Close() } catch { }; $script:fbSoundPlayer = $null }
        Say-Log "preview failed: $($req.Name) could not be decoded"
        if ($req.OnVerified) { & $req.OnVerified $false }
        $script:fbPreviewReq = $null
    })
    $script:fbPreviewTimer = $timer
    $timer.Start()
}

function Play-FbSoundPreview([string]$path, [scriptblock]$onVerified = $null) {
    # $true  - request ACCEPTED; completion is asynchronous and $onVerified is
    #          invoked with $true only after playback is verified
    # $false - candidate rejected synchronously; nothing was started and the
    #          caller must not persist it
    # The caller persists the selection from the $onVerified($true) callback, so
    # an unverified or superseded candidate can never be saved.
    Stop-FbSoundPreview
    if (-not $path -or -not (Test-Path $path)) { return $false }
    $name = [System.IO.Path]::GetFileName($path)
    $kind = Get-FbAudioKind $path
    if (-not $kind) {
        Say-Log "preview skipped: $name is not a recognized audio file (WAV/MP3/OGG/FLAC/M4A/AAC)"
        return $false
    }
    # Primary path: async ffmpeg transcode to PCM WAV (reliable for ADPCM WAV and
    # every compressed container even where MediaPlayer cannot decode). No
    # synchronous conversion runs on the GUI thread.
    $script:fbPreviewGeneration += 1
    $gen = $script:fbPreviewGeneration
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ff) {
        $tmp = Join-Path $env:TEMP ("fbpreview_{0}.wav" -f ([guid]::NewGuid().ToString('N')))
        $proc = $null
        try { $proc = Start-FbConvertAsync $path $tmp } catch { $proc = $null }
        if ($proc) {
            $script:fbPreviewFfmpeg = $proc
            $script:fbPreviewTmp = $tmp
            Start-FbConversionWatch $gen $path $tmp $name $onVerified
            return $true
        }
    }
    # No usable ffmpeg: go straight to the event-driven MediaPlayer fallback.
    Start-FbMediaPreview $path $name $onVerified
    return $true
}
function Load-FbSound {
    $script:fbSoundPath = $null
    if (-not (Test-Path $script:fbSoundFile)) { return }
    try {
        $p = (Read-Utf8 $script:fbSoundFile).Trim()
        if ($p -and (Test-Path $p)) { $script:fbSoundPath = $p }
    } catch {
        $message = "could not read freebuff-sound.txt: $($_.Exception.Message)"
        if (Get-Command Say-Log -CommandType Function -ErrorAction SilentlyContinue) { Say-Log $message }
        else { Write-Warning $message }
    }
}
function Save-FbSound {
    try {
        $dir = Split-Path $script:fbSoundFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if ($script:fbSoundPath) {
            [System.IO.File]::WriteAllText($script:fbSoundFile, $script:fbSoundPath, (New-Object System.Text.UTF8Encoding $false))
        }
        elseif (Test-Path $script:fbSoundFile) { Remove-Item $script:fbSoundFile -Force }
    }
    catch {
        $message = "could not save freebuff-sound.txt: $($_.Exception.Message)"
        if (Get-Command Say-Log -CommandType Function -ErrorAction SilentlyContinue) { Say-Log $message }
        else { Write-Warning $message }
    }
}
function Update-FbSoundButton {
    if ($script:fbSoundPath) {
        $btnFbSound.Text = (T 'FbSoundOn')
        $btnFbSoundTip.SetToolTip($btnFbSound, "FreeBuff completion sound:`n$($script:fbSoundPath)`nLeft-click to change, right-click to clear. COPY stores it inside the repo so it survives deleting the original.")
        $btnFbSoundCopy.Enabled = $true
        $btnFbSoundCopyTip.SetToolTip($btnFbSoundCopy, 'Save a copy inside the repo (sounds\freebuff.<ext>) so the sound outlives the original file.')
    }
    else {
        $btnFbSound.Text = (T 'FbSound')
        $btnFbSoundTip.SetToolTip($btnFbSound, 'FreeBuff completion sound: stock.' + [Environment]::NewLine + 'Left-click to pick an audio file, right-click to clear.')
        $btnFbSoundCopy.Enabled = $false
        $btnFbSoundCopyTip.SetToolTip($btnFbSoundCopy, 'Pick a .wav first - COPY stores it inside the repo.')
    }
}
Load-FbSound

$btnFbSound = New-Object Windows.Forms.Button
$btnFbSound.Text = (T 'FbSound'); $btnFbSound.Location = '640,462'; $btnFbSound.Size = '140,24'; $btnFbSound.Font = $FONT
$btnFbSound.FlatStyle = 'Flat'; $btnFbSound.FlatAppearance.BorderSize = 0

$btnFbSound.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Title = 'Pick the FreeBuff "finished" sound'
        $dlg.Filter = 'Audio files (*.wav;*.mp3;*.ogg;*.flac;*.m4a;*.aac)|*.wav;*.mp3;*.ogg;*.flac;*.m4a;*.aac|All files (*.*)|*.*'
        if ($script:fbSoundPath) { $dlg.InitialDirectory = Split-Path $script:fbSoundPath -Parent }
        if ($dlg.ShowDialog() -ne 'OK') { return }
        # A pick that fails the playability gate is NOT saved: "sound set" after
        # "preview skipped" would be contradictory, and the patch would refuse it
        # anyway. The old preference (if any) stays intact.
        # An asynchronous preview cannot report "playable" before decoding has
        # actually succeeded, so the selection is committed from the verified
        # completion callback - never from the $true that merely means "request
        # accepted". A failed conversion + failed fallback, or a preview that a
        # later pick supersedes, leaves the previous preference intact.
        $candidate = $dlg.FileName
        $accepted = Play-FbSoundPreview $candidate {
            param($verified)
            if (-not $verified) { return }
            $script:fbSoundPath = $candidate
            Save-FbSound
            Update-FbSoundButton
            Say-Log "FreeBuff sound set: $candidate  (applies on the next Apply for freebuff)"
        }
        if (-not $accepted) { return }
    })

$btnFbSound.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [Windows.Forms.MouseButtons]::Right) { return }
        $script:fbSoundPath = $null
        Stop-FbSoundPreview
        Save-FbSound
        Update-FbSoundButton
        Say-Log 'FreeBuff sound cleared - the stock chime will be restored on the next Apply.'
    })

# COPY: drops a durable copy of the chosen audio inside the repo
# (sounds/freebuff.<ext>) and repoints the preference at it. The preference alone is just a path - it
# dies with the file it names; the repo copy outlives the original. Enabled only
# while a custom sound is set; the copy is idempotent (re-copying overwrites).
$btnFbSoundCopy = New-Object Windows.Forms.Button
$btnFbSoundCopy.Text = (T 'FbSoundCopy'); $btnFbSoundCopy.Location = '784,462'; $btnFbSoundCopy.Size = '68,24'; $btnFbSoundCopy.Font = $FONT
$btnFbSoundCopy.FlatStyle = 'Flat'; $btnFbSoundCopy.FlatAppearance.BorderSize = 0
$btnFbSoundCopy.Enabled = $false

$btnFbSoundCopy.Add_Click({
        if (-not $script:fbSoundPath) {
            Say-Log 'FreeBuff sound: nothing to copy yet - pick a .wav first.'
            return
        }
        if (-not (Test-Path $script:fbSoundPath)) {
            Say-Log "FreeBuff sound copy: the source is gone - $($script:fbSoundPath)  (pick it again, or COPY before deleting it)"
            return
        }
        try {
            $destDir = Join-Path $script:root 'sounds'
            $ext = [System.IO.Path]::GetExtension($script:fbSoundPath)
            if (-not $ext) { $ext = '.wav' }
            $dest = Join-Path $destDir ('freebuff' + $ext.ToLower())
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
            # Copying a file onto itself throws; skip when the choice is already
            # the repo copy. Compare canonical paths, not Test-Path.
            $srcFull = [System.IO.Path]::GetFullPath($script:fbSoundPath)
            $dstFull = [System.IO.Path]::GetFullPath($dest)
            if ($srcFull -ieq $dstFull) {
                Say-Log "FreeBuff sound is already the repo copy: $dest"
            }
            else {
                Copy-Item $script:fbSoundPath $dest -Force
                $script:fbSoundPath = $dest
                Save-FbSound
                Update-FbSoundButton
                Say-Log "FreeBuff sound copied into the repo: $dest`n  (preference now points at the copy - deleting the original is safe)"
            }
        }
        catch {
            Say-Log "FreeBuff sound copy FAILED: $($_.Exception.Message)"
        }
    })

$btnFbSoundTip = New-Object Windows.Forms.ToolTip
$btnFbSoundCopyTip = New-Object Windows.Forms.ToolTip
Update-FbSoundButton

$log = New-Object Windows.Forms.TextBox
$log.Location = '640,494'; $log.Size = '212,56'
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true
$log.BorderStyle = 'FixedSingle'

$status = New-Object Windows.Forms.Label
$status.Location = '12,630'; $status.Size = '840,24'

# ---- SCENARIO PRESETS (T-257 / SRC-013) ----
# A preset is desired INSTALLER UI STATE (palette + checked target keys). It is
# staged here and executed ONLY by the existing Apply/Revert buttons -- selecting
# a preset never launches install.ps1 and never mutates an application.
$lblPreset = New-Object Windows.Forms.Label
$lblPreset.Text = (T 'PresetLabel'); $lblPreset.Location = '12,548'; $lblPreset.Size = '120,16'; $lblPreset.Font = $FONTB
$cmbPreset = New-Object Windows.Forms.ComboBox
$cmbPreset.Location = '12,566'; $cmbPreset.Size = '200,21'
$cmbPreset.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$cmbPreset.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$btnPresetSave = New-Object Windows.Forms.Button
$btnPresetSave.Text = (T 'PresetSave'); $btnPresetSave.Location = '220,565'; $btnPresetSave.Size = '56,24'; $btnPresetSave.Font = $FONT
$btnPresetSave.FlatStyle = 'Flat'; $btnPresetSave.FlatAppearance.BorderSize = 0
$btnPresetUpdate = New-Object Windows.Forms.Button
$btnPresetUpdate.Text = (T 'PresetUpdate'); $btnPresetUpdate.Location = '280,565'; $btnPresetUpdate.Size = '56,24'; $btnPresetUpdate.Font = $FONT
$btnPresetUpdate.FlatStyle = 'Flat'; $btnPresetUpdate.FlatAppearance.BorderSize = 0
$btnPresetRename = New-Object Windows.Forms.Button
$btnPresetRename.Text = (T 'PresetRename'); $btnPresetRename.Location = '340,565'; $btnPresetRename.Size = '56,24'; $btnPresetRename.Font = $FONT
$btnPresetRename.FlatStyle = 'Flat'; $btnPresetRename.FlatAppearance.BorderSize = 0
$btnPresetDelete = New-Object Windows.Forms.Button
$btnPresetDelete.Text = (T 'PresetDelete'); $btnPresetDelete.Location = '400,565'; $btnPresetDelete.Size = '56,24'; $btnPresetDelete.Font = $FONT
$btnPresetDelete.FlatStyle = 'Flat'; $btnPresetDelete.FlatAppearance.BorderSize = 0
$lblPresetState = New-Object Windows.Forms.Label
$lblPresetState.Location = '462,569'; $lblPresetState.Size = '390,18'; $lblPresetState.Font = $FONT

# ---- BETTERDISCORD TAB CONTROLS ----
# Navigation page only (T-413): Wintage ships the BetterDiscord THEME; the
# standalone BetterDiscord plugins are maintained in a separate repository and
# are never copied, enabled or state-recorded by this installer.
$lblBdTitle = New-Object Windows.Forms.Label
$lblBdTitle.Text = (T 'BdPlugins'); $lblBdTitle.Location = '12,10'; $lblBdTitle.Size = '400,18'; $lblBdTitle.Font = $FONTB

$lblBdDesc = New-Object Windows.Forms.Label
$lblBdDesc.Text = (T 'BdRepoDesc'); $lblBdDesc.Location = '12,44'; $lblBdDesc.Size = '820,18'; $lblBdDesc.Font = $FONT

$btnBdOpenRepo = New-Object Windows.Forms.Button
$btnBdOpenRepo.Text = (T 'BdRepoOpen'); $btnBdOpenRepo.Location = '12,76'; $btnBdOpenRepo.Size = '260,30'; $btnBdOpenRepo.Font = $FONTB
$btnBdOpenRepo.FlatStyle = 'Flat'; $btnBdOpenRepo.FlatAppearance.BorderSize = 0
$btnBdOpenRepo.Add_Click({ Start-Process 'https://github.com/vacterro/BetterDiscord_vac34_plugins' })

# ---- TERMINAL FONTS TAB CONTROLS (T-283 / SRC-026) ----
# A small terminal typography laboratory: searchable catalog (left), large live
# private-font preview (center), controls (right), status log (bottom). Browsing
# NEVER registers a font or touches terminal settings -- only explicit buttons do.
. (Join-Path $here 'modules/terminal-fonts.ps1')

$lblTfTitle = New-Object Windows.Forms.Label
$lblTfTitle.Text = (T 'TabFonts'); $lblTfTitle.Location = '12,8'; $lblTfTitle.Size = '300,16'; $lblTfTitle.Font = $FONTB

$lblTfSearch = New-Object Windows.Forms.Label
$lblTfSearch.Text = (T 'TfSearch'); $lblTfSearch.Location = '12,30'; $lblTfSearch.Size = '260,16'; $lblTfSearch.Font = $FONT

$txtTfSearch = New-Object Windows.Forms.TextBox
$txtTfSearch.Location = '12,48'; $txtTfSearch.Size = '260,20'; $txtTfSearch.Font = $FONT
$txtTfSearch.BorderStyle = 'FixedSingle'

$lstTfFonts = New-Object Windows.Forms.ListBox
$lstTfFonts.Location = '12,74'; $lstTfFonts.Size = '300,300'; $lstTfFonts.Font = $FONT
$lstTfFonts.BorderStyle = 'FixedSingle'; $lstTfFonts.IntegralHeight = $false
$lstTfFonts.DrawMode = 'OwnerDrawFixed'; $lstTfFonts.ItemHeight = 18

$lblTfMetrics = New-Object Windows.Forms.Label
$lblTfMetrics.Text = ''; $lblTfMetrics.Location = '12,380'; $lblTfMetrics.Size = '300,120'; $lblTfMetrics.Font = $FONT

# Preview panel (center)
$lblTfPreview = New-Object Windows.Forms.Label
$lblTfPreview.Text = (T 'TfPreview'); $lblTfPreview.Location = '320,8'; $lblTfPreview.Size = '300,16'; $lblTfPreview.Font = $FONTB

$pnlTfPreview = New-Object Windows.Forms.Panel
$pnlTfPreview.Location = '320,30'; $pnlTfPreview.Size = '330,470'
$pnlTfPreview.BorderStyle = [Windows.Forms.BorderStyle]::None

# Controls (right)
$lblTfControls = New-Object Windows.Forms.Label
$lblTfControls.Text = (T 'TfControls'); $lblTfControls.Location = '660,8'; $lblTfControls.Size = '200,16'; $lblTfControls.Font = $FONTB

$lblTfFamily = New-Object Windows.Forms.Label
$lblTfFamily.Text = (T 'TfFamily'); $lblTfFamily.Location = '660,32'; $lblTfFamily.Size = '190,16'; $lblTfFamily.Font = $FONT

$lblTfFamilyValue = New-Object Windows.Forms.Label
$lblTfFamilyValue.Text = '-'; $lblTfFamilyValue.Location = '660,50'; $lblTfFamilyValue.Size = '200,32'; $lblTfFamilyValue.Font = $FONTB

$lblTfSize = New-Object Windows.Forms.Label
$lblTfSize.Text = (T 'TfSize'); $lblTfSize.Location = '660,90'; $lblTfSize.Size = '190,16'; $lblTfSize.Font = $FONT

$numTfSize = New-Object Windows.Forms.NumericUpDown
$numTfSize.Location = '660,108'; $numTfSize.Size = '70,20'; $numTfSize.Font = $FONT
$numTfSize.Minimum = 7; $numTfSize.Maximum = 24; $numTfSize.Value = 12
$numTfSize.BorderStyle = 'FixedSingle'

$lblTfRendering = New-Object Windows.Forms.Label
$lblTfRendering.Text = (T 'TfRendering'); $lblTfRendering.Location = '660,136'; $lblTfRendering.Size = '190,16'; $lblTfRendering.Font = $FONT

$cmbTfRendering = New-Object Windows.Forms.ComboBox
$cmbTfRendering.Location = '660,154'; $cmbTfRendering.Size = '104,20'; $cmbTfRendering.Font = $FONT
$cmbTfRendering.DropDownStyle = 'DropDownList'
[void]$cmbTfRendering.Items.AddRange(@('aliased', 'grayscale', 'cleartype'))
$cmbTfRendering.SelectedIndex = 0

$btnTfInstall = New-Object Windows.Forms.Button
$btnTfInstall.Text = (T 'TfInstall'); $btnTfInstall.Location = '660,186'; $btnTfInstall.Size = '200,26'; $btnTfInstall.Font = $FONT
$btnTfInstall.FlatStyle = 'Flat'; $btnTfInstall.FlatAppearance.BorderSize = 2

$btnTfApplyTerminal = New-Object Windows.Forms.Button
$btnTfApplyTerminal.Text = (T 'TfApplyTerminal'); $btnTfApplyTerminal.Location = '660,218'; $btnTfApplyTerminal.Size = '200,26'; $btnTfApplyTerminal.Font = $FONT
$btnTfApplyTerminal.FlatStyle = 'Flat'; $btnTfApplyTerminal.FlatAppearance.BorderSize = 2

$btnTfApplyConhost = New-Object Windows.Forms.Button
$btnTfApplyConhost.Text = (T 'TfApplyConhost'); $btnTfApplyConhost.Location = '660,250'; $btnTfApplyConhost.Size = '200,26'; $btnTfApplyConhost.Font = $FONT
$btnTfApplyConhost.FlatStyle = 'Flat'; $btnTfApplyConhost.FlatAppearance.BorderSize = 2

$btnTfApplyBoth = New-Object Windows.Forms.Button
$btnTfApplyBoth.Text = (T 'TfApplyBoth'); $btnTfApplyBoth.Location = '660,282'; $btnTfApplyBoth.Size = '200,26'; $btnTfApplyBoth.Font = $FONT
$btnTfApplyBoth.FlatStyle = 'Flat'; $btnTfApplyBoth.FlatAppearance.BorderSize = 2

$btnTfRestore = New-Object Windows.Forms.Button
$btnTfRestore.Text = (T 'TfRestore'); $btnTfRestore.Location = '660,314'; $btnTfRestore.Size = '200,26'; $btnTfRestore.Font = $FONT
$btnTfRestore.FlatStyle = 'Flat'; $btnTfRestore.FlatAppearance.BorderSize = 2

$btnTfSource = New-Object Windows.Forms.Button
$btnTfSource.Text = (T 'TfSource'); $btnTfSource.Location = '660,346'; $btnTfSource.Size = '96,24'; $btnTfSource.Font = $FONT
$btnTfSource.FlatStyle = 'Flat'; $btnTfSource.FlatAppearance.BorderSize = 2

$btnTfLicense = New-Object Windows.Forms.Button
$btnTfLicense.Text = (T 'TfLicense'); $btnTfLicense.Location = '764,346'; $btnTfLicense.Size = '96,24'; $btnTfLicense.Font = $FONT
$btnTfLicense.FlatStyle = 'Flat'; $btnTfLicense.FlatAppearance.BorderSize = 2

$btnTfRefresh = New-Object Windows.Forms.Button
# Laid out to the RIGHT of the rendering combo, not on top of it: Refresh used
# to sit at 660,158 with size 96,24 over a 660,154 size 140,20 combo, and being
# later in Controls.AddRange it won every click in the left 96 px of the combo.
# The combo now ends at x=764 and this button runs 770..860, inside the 864-wide
# panel, with no overlap.
$btnTfRefresh.Text = (T 'TfRefresh'); $btnTfRefresh.Location = '770,152'; $btnTfRefresh.Size = '90,24'; $btnTfRefresh.Font = $FONT
$btnTfRefresh.FlatStyle = 'Flat'; $btnTfRefresh.FlatAppearance.BorderSize = 2

$lblTfState = New-Object Windows.Forms.Label
$lblTfState.Text = ''; $lblTfState.Location = '660,378'; $lblTfState.Size = '200,120'; $lblTfState.Font = $FONT

$lblTfLog = New-Object Windows.Forms.Label
$lblTfLog.Text = (T 'TfLog'); $lblTfLog.Location = '12,504'; $lblTfLog.Size = '200,16'; $lblTfLog.Font = $FONTB

$txtTfLog = New-Object Windows.Forms.TextBox
$txtTfLog.Location = '12,522'; $txtTfLog.Size = '848,40'; $txtTfLog.Font = $FONT
$txtTfLog.Multiline = $true; $txtTfLog.ReadOnly = $true; $txtTfLog.ScrollBars = 'Vertical'
$txtTfLog.BorderStyle = 'FixedSingle'


# PERF-004 (SRC-028:R014): ONE bounded retention policy for every GUI log. A
# verbose run used to grow any TextBox without limit (memory scaled with total
# historical output) and paid one ScrollToCaret per appended child line. Every
# log writer now goes through Add-BoundedLogText, which appends the supplied
# text, trims the buffer to a hard character cap when it is exceeded, and
# scrolls ONCE per call. Caps are script-scope so a suite can override them;
# the function carries its own default so an AST-extracted copy still works.
# PERF-004 (SRC-028:R014): ONE bounded retention policy for every GUI log.
# Character-based retention with line-based hysteresis:
#   - hard trigger: LogCharCap (trim once it is crossed)
#   - low-water:    retain LogLowWater chars after trimming (newest wins)
#   - LogMaxChunk:  an incoming chunk larger than the low-water window is
#                   truncated to its newest suffix BEFORE insertion, so a single
#                   huge write never constructs an unbounded TextBox history.
$script:LogCharCap  = 200000      # hard character ceiling per log
$script:LogLowWater = 150000      # retained after trim (newest window)
$script:LogMaxChunk = 50000       # max incoming text bytes retained per call
function Add-BoundedLogText([System.Windows.Forms.TextBox]$box, [string]$text) {
    if ($null -eq $box -or $box.IsDisposed) { return }
    if ([string]::IsNullOrEmpty($text)) { return }
    # D. Large-input safety: never feed more than the retained window into the
    #    editor; the newest suffix of this chunk is what matters.
    if ($text.Length -gt $LogMaxChunk) {
        $text = $text.Substring($text.Length - $LogMaxChunk)
    }
    $box.AppendText($text)
    # A. Hard retention bound + B. hysteresis: only trim once past the hard cap,
    #   and trim back to the low-water mark (not to the cap), so a burst of small
    #   writes does not re-trim every tick.
    if ($box.TextLength -gt $LogCharCap) {
        $keep = $box.Text.Substring($box.TextLength - $LogLowWater)
        # Drop any partial first line so the buffer never starts mid-line; the
        # newest line (the terminal error/status line) is always retained.
        $nl = $keep.IndexOf("`n")
        if ($nl -ge 0) { $keep = $keep.Substring($nl + 1) }
        $box.Text = $keep
    }
    $box.SelectionStart = $box.Text.Length
    $box.ScrollToCaret()
}

# ---- TERMINAL FONTS TAB LOGIC (T-283 / SRC-026) ----
function Say-TfLog([string]$msg) {
    if (-not $txtTfLog) { return }
    $line = (Get-Date -Format 'HH:mm:ss') + ' ' + $msg
    $sep = if ($txtTfLog.Text) { [Environment]::NewLine } else { '' }
    Add-BoundedLogText $txtTfLog ($sep + $line)
}

# The visible row for a catalog entry: name + install state + capability.
function Format-TfRow($entry, $cap) {
    $installState = if ($cap.Installed) { 'INSTALLED' } elseif ($entry.bundled) { 'BUNDLED' } else { 'SYSTEM' }
    $wt = if ($cap.Terminal) { 'WT OK' } else { 'WT --' }
    $con = if ($cap.Conhost) { 'CON OK' } elseif ($cap.Installed -or $cap.Preview) { 'CON --' } else { 'CON ?' }
    '{0,-22} {1,-9} {2,-6} {3}' -f $entry.displayName, $installState, $wt, $con
}

# Build the list once; filtering rebuilds from this cache, never re-reads files.
$script:TfRows = @()
function Load-TfFonts {
    $lstTfFonts.Items.Clear()
    $script:TfRows = @()
    foreach ($entry in Get-TfEntries) {
        $cap = Get-TfCapability $entry
        $row = [pscustomobject]@{ Entry = $entry; Cap = $cap }
        $script:TfRows += $row
    }
    Apply-TfFilter ''
}

$script:TfVisibleRows = @()
function Apply-TfFilter([string]$needle) {
    $lstTfFonts.BeginUpdate()
    try {
        $lstTfFonts.Items.Clear()
        $script:TfVisibleRows = @()
        $n = ($needle + '').Trim().ToLowerInvariant()
        foreach ($row in $script:TfRows) {
            $label = Format-TfRow $row.Entry $row.Cap
            if (-not $n -or $label.ToLowerInvariant().Contains($n)) {
                [void]$lstTfFonts.Items.Add($label)
                $script:TfVisibleRows += $row
            }
        }
    } finally { $lstTfFonts.EndUpdate() }
}

function Get-TfSelectedRow {
    $idx = $lstTfFonts.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $script:TfVisibleRows.Count) { return $null }
    return $script:TfVisibleRows[$idx]
}

function Set-TfControlsEnabled($row) {
    $cap = if ($row) { $row.Cap } else { $null }
    $resolvable = $script:TfPreferenceResolved
    $btnTfInstall.Enabled = [bool]($row -and $row.Entry.bundled -and -not $cap.Installed)
    $btnTfApplyTerminal.Enabled = [bool]($row -and $cap.Terminal -and $resolvable)
    $btnTfApplyConhost.Enabled = [bool]($row -and $cap.Conhost -and $resolvable)
    $btnTfApplyBoth.Enabled = [bool]($row -and $cap.Terminal -and $cap.Conhost -and $resolvable)
    $btnTfRestore.Enabled = $true
    $btnTfRefresh.Enabled = $true
    $btnTfSource.Enabled = [bool]($row -and $row.Entry.source)
    $btnTfLicense.Enabled = [bool]($row -and $row.Entry.licenseFile)
}

$pnlTfPreview.Add_Paint({
        param($s, $e)
        $t = Get-ActiveTokens
        if (-not $t) { return }
        $g = $e.Graphics
        $g.TextRenderingHint = Get-TfRenderingHint $script:TfRendering
        $w = $pnlTfPreview.Width; $h = $pnlTfPreview.Height
        $bg = New-Object Drawing.SolidBrush (C $t.background)
        $fgPri = New-Object Drawing.SolidBrush (C $t.textPrimary)
        $fgSec = New-Object Drawing.SolidBrush (C $t.textSecondary)
        $fgAcc = New-Object Drawing.SolidBrush (C $t.accentTeal)
        $font = $null
        try {
            $g.FillRectangle($bg, 0, 0, $w, $h)
            $row = Get-TfSelectedRow
            $fam = $null
            if ($row) { $fam = Get-TfPreviewFamily $row.Entry }
            if (-not $fam) {
                $g.DrawString('(no previewable face selected)', $FONT, $fgSec, 8, 8)
                return
            }
            $font = New-Object Drawing.Font($fam, [int]$script:TfSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
            $sample = @(Get-TfPreviewSample)
            $y = 6
            $lineH = [Math]::Max(12, [int]($g.MeasureString('Ag', $font).Height))
            foreach ($line in $sample) {
                if ($y + $lineH -gt $h) { break }
                # A couple of sample lines are coloured to show the palette, the
                # rest primary -- a terminal's real mix, not one flat colour.
                $brush = $fgPri
                if ($line -like '*git status*' -or $line -like '*phase:*') { $brush = $fgAcc }
                elseif ($line -like '*chrome.exe*' -or $line -like '*qbittorrent*') { $brush = $fgSec }
                $g.DrawString($line, $font, $brush, 8, $y)
                $y += $lineH
            }
        } finally {
            if ($font) { $font.Dispose() }
            $bg.Dispose(); $fgPri.Dispose(); $fgSec.Dispose(); $fgAcc.Dispose()
        }
    })

function Update-TfMetrics($row) {
    if (-not $row) { $lblTfMetrics.Text = ''; $lblTfState.Text = ''; return }
    $m = Get-TfMetrics $row.Entry ([int]$script:TfSize) $row.Cap
    $cap = $m.Capability
    $lblTfMetrics.Text = @(
        "family:    $($m.Family)",
        "size:      $($m.Size) pt",
        "cell width: $($m.CellWidth)",
        "line height: $($m.LineHeight)",
        "monospace: $($m.Monospace)"
    ) -join [Environment]::NewLine
    $wtState = if ($cap.Terminal) { 'READY' } else { 'NOT READY' }
    $conState = if ($cap.Conhost) { 'READY' } elseif ($cap.Installed -or $cap.Preview) { if ($cap.Installed) { 'UNSUPPORTED' } else { 'UNKNOWN' } } else { 'NOT READY' }
    $lblTfState.Text = @(
        "installed: $(if ($cap.Installed) { 'yes' } else { 'no' })",
        "Windows Terminal: $wtState",
        "Console Host: $conState"
    ) -join [Environment]::NewLine
}

function Update-TfSelection {
    $row = Get-TfSelectedRow
    Set-TfControlsEnabled $row
    if (-not $row) { $lblTfFamilyValue.Text = '-'; $pnlTfPreview.Invalidate(); Update-TfMetrics $null; return }
    $lblTfFamilyValue.Text = $row.Entry.family
    Update-TfMetrics $row
    $pnlTfPreview.Invalidate()
}

# Persist the chosen slug/size/mode to the canonical preference (no target
# mutation). Returns the written preference or $null on failure.
function Save-TfPreference($row) {
    if (-not $row) { return $null }
    try {
        $pref = Set-TfPreference $row.Entry.slug $row.Entry.family ([int]$script:TfSize) $script:TfRendering
        Say-TfLog "preference saved: $($pref.family) $($pref.size)pt $($pref.renderingMode)"
        return $pref
    } catch {
        Say-TfLog "preference NOT saved: $($_.Exception.Message)"
        return $null
    }
}

# Load the persisted preference into the size/rendering controls AND the
# selected catalog row. Selection is resolved by stable fontSlug only -- never a
# formatted display label, never the row-0 fallback.
$script:TfPreferenceResolved = $true   # whether the visible selection matches the preference
function Select-TfPreferenceRow([string]$slug) {
    if (-not $slug) { return $false }
    for ($i = 0; $i -lt $lstTfFonts.Items.Count; $i++) {
        # TfVisibleRows, NOT TfRows: $i is an index into the ListBox, which holds
        # only the rows that survived Apply-TfFilter. Reading the unfiltered
        # catalog here made a filtered list resolve the wrong row -- selecting
        # one font while the metrics, preview and Apply button describe another.
        $row = $script:TfVisibleRows[$i]
        if ($row -and $row.Entry.slug -eq $slug) {
            $lstTfFonts.SelectedIndex = $i
            return $true
        }
    }
    return $false
}

function Load-TfPreferenceIntoUi {
    $script:TfPreferenceResolved = $true
    try {
        $pref = Get-TfPreference
        if ($pref.size -ge 7 -and $pref.size -le 24) { $numTfSize.Value = [int]$pref.size; $script:TfSize = [int]$pref.size }
        $idx = @('aliased', 'grayscale', 'cleartype').IndexOf([string]$pref.renderingMode)
        if ($idx -ge 0) { $cmbTfRendering.SelectedIndex = $idx; $script:TfRendering = [string]$pref.renderingMode }
        # Restore the persisted family by stable slug. The catalog rows are built
        # from the same Load-TfFonts() pass, so they exist before this runs.
        if (-not (Select-TfPreferenceRow ([string]$pref.fontSlug))) {
            # Saved slug not in the catalog: do NOT silently select row 0. Mark
            # the selection unresolved so Apply stays disabled until the user
            # deliberately picks a font.
            $script:TfPreferenceResolved = $false
            Say-TfLog "saved preference slug '$($pref.fontSlug)' is not in the catalog; select a font before applying."
            if ($lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
            Update-TfSelection
            return
        }
    } catch {
        $script:TfPreferenceResolved = $false
        Say-TfLog "preference unreadable: $($_.Exception.Message)"
        if ($lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
        Update-TfSelection
    }
}

$lstTfFonts.Add_SelectedIndexChanged({ Update-TfSelection })
$txtTfSearch.Add_TextChanged({
    $prevSlug = $null
    $row = Get-TfSelectedRow
    if ($row) { $prevSlug = $row.Entry.slug }
    Apply-TfFilter $txtTfSearch.Text
    if ($prevSlug -and (Select-TfPreferenceRow $prevSlug)) { }
    elseif ($lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
})
$numTfSize.Add_ValueChanged({
    $script:TfSize = [int]$numTfSize.Value
    $row = Get-TfSelectedRow
    Update-TfMetrics $row
    $pnlTfPreview.Invalidate()
})
$cmbTfRendering.Add_SelectedIndexChanged({
    $script:TfRendering = [string]$cmbTfRendering.SelectedItem
    $pnlTfPreview.Invalidate()
})

$btnTfInstall.Add_Click({
    $row = Get-TfSelectedRow
    if (-not $row -or -not $row.Entry.bundled) { return }
    $path = Join-Path $root ('fonts\terminal\' + ($row.Entry.file -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $path)) { Say-TfLog "bundled file missing: $path"; return }
    # SAFETY: install is a deliberate operator action, opens the Windows-owned
    # font installer UI (ShellExecute on the .ttf -> Install). Wintage never
    # silently registers a font. After Windows' own confirmation the user
    # re-probes with Refresh.
    try {
        Say-TfLog "opening the Windows font installer for $($row.Entry.family)..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $path
        $psi.UseShellExecute = $true
        [void][System.Diagnostics.Process]::Start($psi)
        Say-TfLog "confirm Install in the Windows dialog, then press Refresh to re-probe."
    } catch { Say-TfLog "install could not be launched: $($_.Exception.Message)" }
})

$btnTfRefresh.Add_Click({
    # Explicit refresh: clear the installed-family probe cache, re-enumerate,
    # rebuild capability states, preserve the current selected Slug and search
    # text, leave button enablement/metrics/preview consistent. Deterministic --
    # never polls Windows waiting for an install to complete.
    $prevSlug = $null
    $row = Get-TfSelectedRow
    if ($row) { $prevSlug = $row.Entry.slug }
    $searchText = $txtTfSearch.Text
    $script:TfInstalledNames = $null   # force a fresh probe
    Load-TfFonts
    Apply-TfFilter $searchText
    $restored = $false
    if ($prevSlug) { $restored = Select-TfPreferenceRow $prevSlug }
    if (-not $restored -and $lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
    Update-TfSelection
    Say-TfLog 'font state re-probed.'
})

function Invoke-TfApply([bool]$terminal, [bool]$conhost) {
    $row = Get-TfSelectedRow
    if (-not $row) { return }
    if (-not (Save-TfPreference $row)) { return }   # persist BEFORE mutation dispatch
    $targets = @()
    if ($terminal) { $targets += 'terminal' }
    if ($conhost) { $targets += 'conhost' }
    if (-not $targets.Count) { return }
    # A main Apply/Revert batch owns the single $script:batchState holder; never
    # start a second worker on top of it. The tf buttons are disabled while that
    # batch is active (btnApply path), so this is a belt-and-braces refuse.
    if ($script:batchState -and -not $script:batchState.Cleared) {
        Say-TfLog 'apply busy: a batch is already running - wait for it to finish.'
        return
    }
    # PERF-002: dispatch the whole selected set through ONE async worker using
    # Start-BatchJob (the bounded asynchronous mechanism main Apply already uses).
    # Apply Both launches ONE child process with -Selected terminal,conhost,
    # never two serial -Target children. The Forms.Timer heartbeat keeps the
    # window repainting while the child runs; CORE-002 truthful result model
    # classifies the outcome in the completion callback.
    $selected = $targets -join ','
    $script:TfSelectedTargets = $targets
    # '<custom>' is a GUI-internal identity, not a palette slug: install.ps1
    # joins themes\$PaletteSlug.json, so forwarding it verbatim resolves
    # themes/<custom>.json and every Fonts-tab Apply fails for a user who has
    # edited a custom palette. Persist the swatches first, exactly as the main
    # Apply path does at its own normalization, and forward the real slug.
    $paletteSlug = if ($script:current -eq '<custom>') { Save-Custom; 'custom' } else { $script:current }
    $innerArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'install.ps1'), '-Selected', $selected, '-Palette', $paletteSlug)
    Say-TfLog "applying $($row.Entry.family) ($($script:TfSize)pt, $($script:TfRendering)) to: $($targets -join ', ')..."
    # Overlapping font mutation is impossible: the three Apply buttons are
    # disabled for the whole batch (Disable-TfApplyUi) and re-enabled on
    # completion. Preference persistence above already happened pre-dispatch.
    Disable-TfApplyUi
    try {
        Start-BatchJob $innerArgs {
            param($child)
            # Streaming batches pass $script:batchState (with ExitCode + BatchResults)
            # rather than a legacy st.Result object. $child may be either shape.
            Enable-TfApplyUi
            $st = $child
            if ($st -is [pscustomobject] -and -not $st.ExitCode -and -not $st.Process -and $st.Result) {
                # Legacy: child is the job Result wrapper; no streaming results.
                $code = $st.Result.ExitCode
                $failedNames = @(Get-BatchFailures $st.Result)
                if ($code -ne 0 -and -not $failedNames.Count) { $failedNames = @($script:TfSelectedTargets) }
                if (-not $failedNames.Count) {
                    Say-TfLog 'apply done. (SUCCESS)'
                } elseif ($failedNames.Count -lt @($script:TfSelectedTargets).Count) {
                    Say-TfLog "apply PARTIAL: failed targets: $($failedNames -join ', '). Successful targets completed."
                } else {
                    Say-TfLog "apply FAILED: $($failedNames -join ', ')"
                }
            } else {
                # Streaming path: classify from authoritative machine-result records.
                $classification = Classify-BatchResult $st
                Say-TfLog $classification.Message
            }
            Update-TfSelection
        }
    } catch {
        Enable-TfApplyUi
        Say-TfLog "apply FAILED: $($_.Exception.Message)"
    }
}

# PERF-002: disable the three terminal-font Apply mutation buttons while a batch
# is active so no overlapping font mutation can start.
function Disable-TfApplyUi {
    $btnTfApplyTerminal.Enabled = $false
    $btnTfApplyConhost.Enabled = $false
    $btnTfApplyBoth.Enabled = $false
    $btnTfInstall.Enabled = $false
    $btnTfRestore.Enabled = $false
}
function Enable-TfApplyUi {
    $btnTfApplyTerminal.Enabled = $true
    $btnTfApplyConhost.Enabled = $true
    $btnTfApplyBoth.Enabled = $true
    $btnTfInstall.Enabled = $true
    $btnTfRestore.Enabled = $true
    Update-TfSelection   # re-evaluate capability-gated enablement
}

$btnTfApplyTerminal.Add_Click({ Invoke-TfApply $true $false })
$btnTfApplyConhost.Add_Click({ Invoke-TfApply $false $true })
$btnTfApplyBoth.Add_Click({ Invoke-TfApply $true $true })

$btnTfRestore.Add_Click({
    # RESTORE DEFAULT: reset the PREFERENCE to the Wintage default and preview it
    # immediately. It does NOT destructively revert terminal state until an
    # explicit Apply, so "preference" and "live target" stay separate operations.
    try {
        $slug = 'terminus-ttf'; $family = 'Terminus (TTF) for Windows'
        $pref = Set-TfPreference $slug $family 12 'aliased'
        $numTfSize.Value = 12; $cmbTfRendering.SelectedIndex = 0; $script:TfSize = 12; $script:TfRendering = 'aliased'
        # Clear any active search filter so the default row is actually visible,
        # and select by stable slug -- not by a formatted display substring that
        # a filter or a label change would break.
        if ($txtTfSearch.Text) { $txtTfSearch.Text = ''; Apply-TfFilter '' }
        if (-not (Select-TfPreferenceRow $slug)) {
            if ($lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
        }
        Say-TfLog "preference restored to the Wintage default ($family 12pt aliased). Press Apply to write it to a target."
    } catch { Say-TfLog "restore failed: $($_.Exception.Message)" }
    Update-TfSelection
})

$btnTfSource.Add_Click({
    $row = Get-TfSelectedRow
    if ($row -and $row.Entry.source) { Start-Process $row.Entry.source }
})
$btnTfLicense.Add_Click({
    $row = Get-TfSelectedRow
    if ($row -and $row.Entry.licenseFile) {
        $lp = Join-Path $root ('fonts\terminal\' + ($row.Entry.licenseFile -replace '/', '\'))
        if (Test-Path -LiteralPath $lp) { Start-Process $lp } else { Say-TfLog "license file missing: $lp" }
    }
})

function Initialize-TfTab {
    Load-TfFonts
    Load-TfPreferenceIntoUi
    Update-TfSelection
}

# Re-probe installed/capability state on tab re-entry. The operator-driven
# re-probe after a Windows install is the visible btnTfRefresh button.
function Refresh-TfFonts {
    $prevSlug = $null
    $row = Get-TfSelectedRow
    if ($row) { $prevSlug = $row.Entry.slug }
    $searchText = $txtTfSearch.Text
    $script:TfInstalledNames = $null   # force a fresh probe
    Load-TfFonts
    Apply-TfFilter $searchText
    $restored = $false
    if ($prevSlug) { $restored = Select-TfPreferenceRow $prevSlug }
    if (-not $restored -and $lstTfFonts.Items.Count -gt 0) { $lstTfFonts.SelectedIndex = 0 }
    Update-TfSelection
    Say-TfLog 'font state re-probed.'
}


# ---- LANGUAGE ----
# English by default (i18n.ps1), the machine's saved pick preselected. A switch
# re-strings every translatable control live -- no relaunch, no second code path.
$lblLanguage = New-Object Windows.Forms.Label
$lblLanguage.Text = (T 'LanguageLabel'); $lblLanguage.Location = '630,12'; $lblLanguage.Size = '78,16'; $lblLanguage.Font = $FONTB
$cmbLanguage = New-Object Windows.Forms.ComboBox
$cmbLanguage.Location = '712,9'; $cmbLanguage.Size = '140,21'
$cmbLanguage.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLanguage.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$cmbLanguage.DrawMode = [Windows.Forms.DrawMode]::OwnerDrawFixed
$cmbLanguage.ItemHeight = 16
foreach ($l in (Get-I18nLocales)) { [void]$cmbLanguage.Items.Add($l) }
$script:currentLocale = if ($cmbLanguage.Items -contains $script:SavedLocale) { $script:SavedLocale } else { 'en' }
$cmbLanguage.SelectedItem = $script:currentLocale

$cmbLanguage.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $t = Get-ActiveTokens
    if (-not $t) { return }
    $g = $e.Graphics
    $isSel = ($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
    $bgCol = if ($isSel) { C $t.surfaceRaised } else { C $t.compareBack }
    $textCol = C $t.textPrimary
    $bBrush = New-Object Drawing.SolidBrush $bgCol
    $tBrush = New-Object Drawing.SolidBrush $textCol
    try {
        $g.FillRectangle($bBrush, $e.Bounds)
        $text = $cmbLanguage.Items[$e.Index]
        $g.DrawString($text, $FONT, $tBrush, $e.Bounds.Left + 2, $e.Bounds.Top + 1)
        if ($isSel) {
            $pen = New-Object Drawing.Pen (C $t.borderHighlight)
            $g.DrawRectangle($pen, $e.Bounds.Left, $e.Bounds.Top, $e.Bounds.Width - 1, $e.Bounds.Height - 1)
            $pen.Dispose()
        }
    } finally {
        $bBrush.Dispose(); $tBrush.Dispose()
    }
})

function Update-GuiStrings {
    $form.Text = (T 'WintageInstallerTitle')
    $btnTabThemes.Text = (T 'TabThemes')
    $btnTabBetterDiscord.Text = (T 'TabBetterDiscord')
    $lblThemes.Text = (T 'Palettes'); $lblMyApps.Text = (T 'MyApps'); $lblPopularApps.Text = (T 'PopularApps')
    $lblPreview.Text = (T 'Preview'); $lblTokens.Text = (T 'Tokens'); $lblLanguage.Text = (T 'LanguageLabel')
    $btnSelectAll.Text = (T 'SelectAll'); $btnSelectNone.Text = (T 'SelectNone')
    $btnApply.Text = (T 'Apply'); $btnSave.Text = (T 'Save'); $btnDelCustom.Text = (T 'DelCustom'); $btnRevert.Text = (T 'Revert')
    $chkLogonTask.Text = (T 'LogonTask'); $btnFbSoundCopy.Text = (T 'FbSoundCopy')
    $status.Text = (T 'StatusHint')
    $lblBdTitle.Text = (T 'BdPlugins')
    $lblBdDesc.Text = (T 'BdRepoDesc')
    $btnBdOpenRepo.Text = (T 'BdRepoOpen')
    $btnTabFonts.Text = (T 'TabFonts')
    $lblTfTitle.Text = (T 'TabFonts')
    $lblTfSearch.Text = (T 'TfSearch')
    $lblTfPreview.Text = (T 'TfPreview')
    $lblTfControls.Text = (T 'TfControls')
    $lblTfFamily.Text = (T 'TfFamily')
    $lblTfSize.Text = (T 'TfSize')
    $lblTfRendering.Text = (T 'TfRendering')
    $lblTfLog.Text = (T 'TfLog')
    $btnTfInstall.Text = (T 'TfInstall')
    $btnTfApplyTerminal.Text = (T 'TfApplyTerminal')
    $btnTfApplyConhost.Text = (T 'TfApplyConhost')
    $btnTfApplyBoth.Text = (T 'TfApplyBoth')
    $btnTfRestore.Text = (T 'TfRestore')
    $btnTfSource.Text = (T 'TfSource')
    $btnTfLicense.Text = (T 'TfLicense')
    $btnTfRefresh.Text = (T 'TfRefresh')
    Update-FbSoundButton
}

$cmbLanguage.Add_SelectedIndexChanged({
    $script:currentLocale = [string]$cmbLanguage.SelectedItem
    Set-I18nLocale $script:currentLocale
    Update-GuiStrings
})

$pnlThemes.Controls.AddRange(@($lblThemes, $lstThemes, $lblMyApps, $clbMyApps, $lblPopularApps, $clbPopularApps, $btnSelectAll, $btnSelectNone, $lblPreview, $preview,
        $lblTokens, $swatchPanel, $lblInfo, $btnApply, $btnSave, $btnDelCustom, $btnRevert, $chkLogonTask, $btnFbSound, $btnFbSoundCopy, $log,
        $lblPreset, $cmbPreset, $btnPresetSave, $btnPresetUpdate, $btnPresetRename, $btnPresetDelete, $lblPresetState))

$pnlBetterDiscord.Controls.AddRange(@($lblBdTitle, $lblBdDesc, $btnBdOpenRepo))

$pnlFonts.Controls.AddRange(@($lblTfTitle, $lblTfSearch, $txtTfSearch, $lstTfFonts, $lblTfMetrics,
        $lblTfPreview, $pnlTfPreview, $lblTfControls, $lblTfFamily, $lblTfFamilyValue, $lblTfSize, $numTfSize,
        $lblTfRendering, $cmbTfRendering, $btnTfInstall, $btnTfApplyTerminal, $btnTfApplyConhost, $btnTfApplyBoth,
        $btnTfRestore, $btnTfSource, $btnTfLicense, $btnTfRefresh, $lblTfState, $lblTfLog, $txtTfLog))

# The ordered tab table (key -> button + panel). Exactly one panel is visible;
# Update-TabButtons/Set-ActiveTab iterate this single source.
$script:tabTable = @(
    [pscustomobject]@{ Key = 'themes'; Button = $btnTabThemes; Panel = $pnlThemes },
    [pscustomobject]@{ Key = 'bd'; Button = $btnTabBetterDiscord; Panel = $pnlBetterDiscord },
    [pscustomobject]@{ Key = 'fonts'; Button = $btnTabFonts; Panel = $pnlFonts }
)

$form.Controls.AddRange(@($btnTabThemes, $btnTabBetterDiscord, $btnTabFonts, $lblLanguage, $cmbLanguage, $pnlThemes, $pnlBetterDiscord, $pnlFonts, $status))
$lstThemes.TabIndex = 0; $clbMyApps.TabIndex = 1; $clbPopularApps.TabIndex = 2
$btnSelectAll.TabIndex = 3; $btnSelectNone.TabIndex = 4; $btnApply.TabIndex = 5
$btnSave.TabIndex = 6; $btnDelCustom.TabIndex = 7; $btnRevert.TabIndex = 8; $btnFbSound.TabIndex = 9; $btnFbSoundCopy.TabIndex = 10; $log.TabIndex = 11

# ---- TARGET DISCOVERY ----
# Read from install.ps1's own listing rather than duplicated here: one source of
# truth for what exists on this machine, and a target added there shows up here
# without a second edit.
$script:targets = @()
function Load-Targets {
    foreach ($list in $TARGET_LISTS) { $list.Items.Clear() }
    $script:targets = @()
    # EAP=Stop would turn the child's stderr into a terminating error here, so
    # the target list is read with the same Continue discipline as Apply.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install.ps1') 2>&1
    $ErrorActionPreference = $prev
    foreach ($line in $out) {
        if ($line -match '^\s{2}(\S+)\s{2,}(.+?)\s{2,}(not installed|themed|found, not themed|fused shut|listing failed)\s{2,}(.+)$') {
            $t = [pscustomobject]@{ Key = $Matches[1]; Name = $Matches[2].Trim(); State = $Matches[3]; Palette = $Matches[4].Trim() }
            if ($t.Key -eq 'target') { continue }
            $list = if ($t.Key -in $MY_APP_KEYS) { $clbMyApps } else { $clbPopularApps }
            $label = '{0,-16} {1}' -f $t.Key, $t.State
            [void]$list.Items.Add($label)
            $i = $list.Items.Count - 1
            $t | Add-Member -NotePropertyName List -NotePropertyValue $list
            $t | Add-Member -NotePropertyName ItemIndex -NotePropertyValue $i
            $script:targets += $t
            # Everything that CAN be themed starts ticked -- the overwhelmingly common
            # intent is "put this palette on all of it", and unticking two rows is less
            # work than ticking eleven. An app that is absent or fused shut is never
            # ticked, because Apply would only print a refusal for it. A listing that
            # FAILED is likewise not ticked: we do not know what is there (T-189).
            #
            # The three source-tree targets are ticked only when their folder is already
            # remembered: ticking them otherwise would fire the folder dialog from
            # startup, three times, before the window is even usable.
            $selectable = $t.State -ne 'not installed' -and $t.State -ne 'fused shut' -and $t.State -ne 'listing failed'
            if ($selectable -and $t.Key -in $PATH_TARGETS) { $selectable = $script:customPaths.ContainsKey($t.Key) }
            if ($selectable) { $list.SetItemChecked($i, $true) }
        }
    }
}

function Get-CheckedTargetItems {
    $items = @()
    foreach ($list in $TARGET_LISTS) {
        foreach ($i in $list.CheckedIndices) { $items += $list.Items[$i] }
    }
    $items
}

# CORE-002: ONE selectability rule shared by startup defaults and preset
# loading. "present in discovery output" is not "usable": not installed, fused
# shut, listing failed and a path-backed target without a remembered folder are
# all unavailable, with the machine-readable reason the UI reports.
function Get-TargetSelectability([string]$key) {
    $entry = @($script:targets | Where-Object { $_.Key -eq $key })[0]
    if (-not $entry) { return [pscustomobject]@{ Selectable = $false; Reason = 'not found on this machine' } }
    if ($entry.State -eq 'not installed') { return [pscustomobject]@{ Selectable = $false; Reason = 'not installed' } }
    if ($entry.State -eq 'fused shut') { return [pscustomobject]@{ Selectable = $false; Reason = 'fused shut' } }
    if ($entry.State -eq 'listing failed') { return [pscustomobject]@{ Selectable = $false; Reason = 'listing failed' } }
    if ($key -in $PATH_TARGETS -and -not $script:customPaths.ContainsKey($key)) {
        return [pscustomobject]@{ Selectable = $false; Reason = 'no remembered folder' }
    }
    return [pscustomobject]@{ Selectable = $true; Reason = '' }
}

# CORE-002: resolve a preset into requested / selectable / unavailable targets
# plus the palette-resolution state. Pure read-only projection; Apply-PresetUiState
# is the only consumer allowed to mutate the UI from it.
function Resolve-PresetUiState($preset) {
    $requested = @($preset.targets)
    $selectable = @(); $unavailable = @()
    foreach ($k in $requested) {
        $r = Get-TargetSelectability ([string]$k)
        if ($r.Selectable) { $selectable += [string]$k }
        else { $unavailable += [pscustomobject]@{ Key = [string]$k; Reason = $r.Reason } }
    }
    $palette = [pscustomobject]@{ Resolved = $false; Kind = ''; Slug = ''; Tokens = $null; Reason = '' }
    if ($preset.palette.type -eq 'pack') {
        $slug = [string]$preset.palette.slug
        if ($script:packs.ContainsKey($slug)) {
            $palette.Resolved = $true; $palette.Kind = 'pack'; $palette.Slug = $slug
        } else {
            $palette.Reason = "palette pack '$slug' is not installed on this machine"
        }
    } else {
        # CORE-006 repair: the local was named `$tokens -- case-insensitively the
        # SAME name as the canonical `$TOKENS list -- so this assignment shadowed
        # the list and the loop below iterated the empty dictionary instead,
        # yielding a junk-entry snapshot (a real snapshot load staged empty
        # tokens and crashed Refresh-Swatches on FromHtml('')). Keep any local
        # token dictionary name distinct from `$TOKENS.
        $tokenSnapshot = [ordered]@{}
        foreach ($k in $TOKENS) { $tokenSnapshot[$k] = [string]$preset.palette.tokens.$k }
        $palette.Resolved = $true; $palette.Kind = 'snapshot'; $palette.Tokens = $tokenSnapshot
    }
    return [pscustomobject]@{
        Requested   = $requested
        Selectable  = @($selectable)
        Unavailable = @($unavailable)
        Palette     = $palette
    }
}

function Update-FbButtonsVisibility([object]$sender = $null, [int]$index = -1, [string]$newValue = '') {
    # The FB SOUND / COPY buttons are part of the freebuff install path. They
    # appear only while the freebuff target is the ONE checked target - with
    # several apps checked, a freebuff-only sound picker would look like it
    # applies to all of them. When hidden, the log moves up into their row.
    $keys = @()
    foreach ($list in $TARGET_LISTS) {
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            $isChecked = $list.GetItemChecked($i)
            if ($list -eq $sender -and $i -eq $index) { $isChecked = ($newValue -eq 'Checked') }
            if ($isChecked) { $keys += (($list.Items[$i]) -split '\s+')[0] }
        }
    }
    $show = ($keys.Count -eq 1) -and ($keys[0] -eq 'freebuff')
    $btnFbSound.Visible = $show
    $btnFbSoundCopy.Visible = $show
    $log.Location = if ($show) { '640,462' } else { '640,434' }
}

# ---- RENDERING ----
$lstThemes.Add_DrawItem({
        param($s, $e)
        $e.DrawBackground()
        if ($e.Index -lt 0) { return }
        $text = $lstThemes.Items[$e.Index]
        $slug = if ($text -eq 'Custom') { '<custom>' } else { ($script:packs.Values | Where-Object { $_.label -eq $text } | Select-Object -First 1).slug }
        $g = $e.Graphics
        $g.TextRenderingHint = 'SingleBitPerPixelGridFit'
        # PERF-009: cache brushes per row so the 4 chip fills + 1 text draw
        # allocate at most 5 SolidBrush instances, all disposed before the
        # draw returns. Without this every theme row leaked 5 GDI handles
        # and the inventory grew linearly with the repaint count.
        $disposable = New-Object 'System.Collections.Generic.List[System.IDisposable]'
        try {
            # A colour chip per row: picking a theme by name alone means opening every
            # one to find out what it looks like.
            if ($slug -and $slug -ne '<custom>') {
                $t = $script:packs[$slug].tokens
                $x = $e.Bounds.Right - 46
                foreach ($k in @('background', 'surfaceRaised', 'borderHighlight', 'textPrimary')) {
                    $b = New-Object Drawing.SolidBrush (C $t.$k)
                    [void]$disposable.Add($b)
                    $g.FillRectangle($b, $x, $e.Bounds.Top + 4, 10, 10)
                    $x += 11
                }
            }
            $tb = New-Object Drawing.SolidBrush $e.ForeColor
            [void]$disposable.Add($tb)
            $g.DrawString($text, $FONT, $tb, $e.Bounds.Left + 2, $e.Bounds.Top + 2)
        } finally {
            foreach ($d in $disposable) { try { $d.Dispose() } catch { } }
        }
    })

$preview.Add_Paint({
        param($s, $e)
        $t = Get-ActiveTokens
        if (-not $t) { return }
        $g = $e.Graphics
        $g.TextRenderingHint = 'SingleBitPerPixelGridFit'
        $w = $preview.Width; $h = $preview.Height
        # PERF-009: cache SolidBrush instances per paint and dispose them on
        # exit so repeated previews do not accumulate native GDI handles. A
        # small dictionary keyed by hex colour avoids allocating a new brush
        # for every FillRectangle / DrawString call inside the same paint.
        $brushes = @{}
        $disposable = New-Object 'System.Collections.Generic.List[System.IDisposable]'
        function _b($k) {
            if (-not $brushes.ContainsKey($k)) {
                $br = New-Object Drawing.SolidBrush (C $t.$k)
                $brushes[$k] = $br
                [void]$disposable.Add($br)
            }
            return $brushes[$k]
        }
        try {
            $g.FillRectangle((_b 'background'), 0, 0, $w, $h)

            # Title bar
            $bar = New-Object Drawing.Rectangle 8, 8, ($w - 16), 22
            $g.FillRectangle((_b 'surface'), $bar)
            Draw-Bevel $g $bar (C $t.borderHighlight) (C $t.borderDark) $true
            $g.DrawString('Wintage', $FONTB, (_b 'textPrimary'), 14, 12)

            # Window body
            $body = New-Object Drawing.Rectangle 8, 30, ($w - 16), ($h - 38)
            $g.FillRectangle((_b 'backgroundSoft'), $body)
            Draw-Bevel $g $body (C $t.borderHighlight) (C $t.borderDark) $false

            $g.DrawString('Primary text on backgroundSoft', $FONT, (_b 'textPrimary'), 18, 40)
            $g.DrawString('Secondary text', $FONT, (_b 'textSecondary'), 18, 58)
            $g.DrawString('Muted / disabled', $FONT, (_b 'textMuted'), 18, 76)
            $g.DrawString('A hyperlink', $FONT, (_b 'link'), 18, 94)

            # Buttons: raised, pressed, disabled
            $b1 = New-Object Drawing.Rectangle 18, 118, 84, 24
            $g.FillRectangle((_b 'surfaceRaised'), $b1)
            Draw-Bevel $g $b1 (C $t.borderHighlight) (C $t.borderDark) $true
            $g.DrawString('OK', $FONT, (_b 'textPrimary'), 48, 124)

            $b2 = New-Object Drawing.Rectangle 110, 118, 84, 24
            $g.FillRectangle((_b 'surface'), $b2)
            Draw-Bevel $g $b2 (C $t.borderHighlight) (C $t.borderDark) $false
            $g.DrawString('Pressed', $FONT, (_b 'textPrimary'), 122, 124)

            $b3 = New-Object Drawing.Rectangle 202, 118, 84, 24
            $g.FillRectangle((_b 'surfaceRaised'), $b3)
            Draw-Bevel $g $b3 (C $t.borderHighlight) (C $t.borderDark) $true
            $g.DrawString('Disabled', $FONT, (_b 'textMuted'), 210, 124)

            # Sunken input with a selection run
            $inp = New-Object Drawing.Rectangle 18, 152, 268, 22
            $g.FillRectangle((_b 'compareBack'), $inp)
            Draw-Bevel $g $inp (C $t.borderHighlight) (C $t.borderDark) $false
            $g.FillRectangle((_b 'selection'), 24, 156, 96, 14)
            $g.DrawString('selected text', $FONT, (_b 'textPrimary'), 24, 155)

            # Scrollbar
            $track = New-Object Drawing.Rectangle 294, 152, 16, 96
            $g.FillRectangle((_b 'backgroundSoft'), $track)
            Draw-Bevel $g $track (C $t.borderHighlight) (C $t.borderDark) $false
            $thumb = New-Object Drawing.Rectangle 294, 168, 16, 40
            $g.FillRectangle((_b 'surfaceRaised'), $thumb)
            Draw-Bevel $g $thumb (C $t.borderHighlight) (C $t.borderDark) $true

            # Semantic swatches - backgrounds only, never text (they fail AA as text)
            $x = 18
            foreach ($k in @('success', 'warning', 'danger')) {
                $r = New-Object Drawing.Rectangle $x, 186, 78, 20
                $g.FillRectangle((_b $k), $r)
                Draw-Bevel $g $r (C $t.borderHighlight) (C $t.borderDark) $true
                $g.DrawString($k, $FONT, (_b 'textPrimary'), ($x + 6), 189)
                $x += 86
            }

            # Surface ladder, so the three steps are visible as steps
            $x = 18
            foreach ($k in @('background', 'backgroundSoft', 'surface', 'surfaceRaised', 'surfaceAlt')) {
                $r = New-Object Drawing.Rectangle $x, 216, 52, 26
                $g.FillRectangle((_b $k), $r)
                Draw-Bevel $g $r (C $t.borderMuted) (C $t.borderDark) $true
                $x += 54
            }
        } finally {
            foreach ($d in $disposable) { try { $d.Dispose() } catch { } }
        }
    })

function Refresh-Swatches {
    # PERF-009: dispose removed swatch controls so they do not pile up as
    # orphaned native handles. WinForms.Controls.Clear() only detaches the
    # references; the underlying control objects survive until GC finalises
    # their handles.
    foreach ($c in @($swatchPanel.Controls)) {
        try { $c.Dispose() } catch { }
    }
    $swatchPanel.Controls.Clear()
    $t = Get-ActiveTokens
    $y = 0; $col = 0
    foreach ($k in $TOKENS) {
        $p = New-Object Windows.Forms.Panel
        $p.Size = '18,18'
        $p.Location = New-Object Drawing.Point (($col * 190) + 2), ($y + 2)
        $p.BackColor = C $t.$k
        $p.BorderStyle = 'FixedSingle'
        $p.Tag = $k
        $p.Cursor = 'Hand'
        $p.Add_Click({
                $key = $this.Tag
                $dlg = New-Object Windows.Forms.ColorDialog
                try {
                    $dlg.FullOpen = $true
                    $dlg.Color = $this.BackColor
                    if ($dlg.ShowDialog() -eq 'OK') {
                        # Editing any swatch forks the palette into Custom rather than
                        # mutating a shipped pack -- a theme the user did not author
                        # must never change under them.
                        if ($script:current -ne '<custom>') {
                            $src = Get-ActiveTokens
                            $script:custom = @{}
                            foreach ($kk in $TOKENS) { $script:custom[$kk] = $src[$kk] }
                            $script:current = '<custom>'
                            $lstThemes.SelectedItem = 'Custom'
                        }
                        $hex = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
                        $script:custom[$key] = $hex
                        Refresh-Swatches
                        $preview.Invalidate()
                        Update-Info
                    }
                } finally {
                    # PERF-009: deterministic disposal of the ColorDialog so the
                    # per-click native handle does not accumulate during a long
                    # swatch-editing session.
                    try { $dlg.Dispose() } catch { }
                }
            })
        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = $k
        $lbl.Location = New-Object Drawing.Point (($col * 190) + 24), ($y + 4)
        $lbl.Size = '160,16'
        $swatchPanel.Controls.AddRange(@($p, $lbl))
        $y += 20
        if ($y -gt 160) { $y = 0; $col++ }
    }
}

function Update-Info {
    $t = Get-ActiveTokens
    if (-not $t) { return }
    $bg = $t.backgroundSoft
    $rows = @()
    # Same text-role list the build gate enforces (tools/theme-schema.json
    # wcagRoles): textPrimary, textSecondary, link. borderHighlight is a
    # decorative bevel edge, not a text role, and warning on it produced false
    # FAILs for every light palette (T-187).
    foreach ($k in $script:wcagRoles) {
        $c = Contrast $t.$k $bg
        $mark = if ($c -ge 4.5) { 'PASS' } else { 'FAIL' }
        $rows += ('{0,-16} {1,5}:1  {2}' -f $k, $c, $mark)
    }
    $name = if ($script:current -eq '<custom>') { 'Custom' } else { $script:packs[$script:current].label }
    # The contrast block is the whole reason the custom editor is safe to hand over:
    # it says, before Apply, whether the palette is readable. The gate would reject a
    # failing one anyway, but finding out here beats finding out from a build error.
    $lblInfo.Text = "$name`r`n`r`nWCAG AA vs backgroundSoft`r`n" + ($rows -join "`r`n") +
    "`r`n`r`nA palette that FAILs is refused by the`r`nbuild gate, so fix it here first." +
    "`r`n`r`nApply runs the same install.ps1 the`r`nterminal does - no second code path."
}

# W2-004 (T-246:R009): batch-active UI guards. Save/Delete-Custom and token
# edits mutate the Custom generation; while a batch is running they must be
# disabled as a UI guard, NOT relied upon as the concurrency fix (other processes
# remain possible -- the lock handles that). Guards are keyed on $script:batchActive
# so the tick-completion path and any early return both restore them.
function Disable-BatchUi {
    $script:batchActive = $true
    $btnApply.Enabled = $false; $btnRevert.Enabled = $false
    $btnSave.Enabled = $false; $btnDelCustom.Enabled = $false
    $lstThemes.Enabled = $false
    $clbMyApps.Enabled = $false; $clbPopularApps.Enabled = $false
    $btnSelectAll.Enabled = $false; $btnSelectNone.Enabled = $false
    $cmbLanguage.Enabled = $false
}

function Enable-BatchUi {
    $script:batchActive = $false
    $btnApply.Enabled = $true; $btnRevert.Enabled = $true
    $btnSave.Enabled = $true; $btnDelCustom.Enabled = $true
    $lstThemes.Enabled = $true
    $clbMyApps.Enabled = $true; $clbPopularApps.Enabled = $true
    $btnSelectAll.Enabled = $true; $btnSelectNone.Enabled = $true
    $cmbLanguage.Enabled = $true
}

# ---- ACTIONS ----

# R014: the main GUI log is explicitly bounded -- all three surfaces use the
# single retention primitive above (Add-BoundedLogText), not a raw AppendText.
function Say-Log($msg) {
    if ($null -eq $msg) { return }
    if ($log -and -not $log.IsDisposed) {
        Add-BoundedLogText $log ("$msg`r`n")
    }
}

# Run a child powershell and return { Output; ExitCode } WITHOUT letting EAP=Stop
# turn the child's stderr into a terminating error mid-loop (the PS 5.1
# NativeCommandError trap this file already documents for ffmpeg). The child's
# own exit code is the only honest success signal.
function Invoke-ChildPowerShell([string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Output = @($out); ExitCode = $code }
}

# PERF-004 (SRC-028:R014): bounded producer-consumer between the child process
# output callbacks and the UI timer. The child can produce output far faster than
# WinForms renders it, so a plain ConcurrentQueue merely moves the memory leak
# from TextBox to RAM. This queue has an explicit maximum; oldest ordinary
# records are dropped when it overflows -- terminal/failure metadata never is.
$script:BatchQueueMax = 2000
$script:BatchQueueLines = 0
$script:BatchQueueGate = New-Object object
$script:BatchDroppedLines = 0
# M4: per-tick render budget -- bounds GUI work per tick so one noisy child
# cannot freeze the message pump.
$script:BatchDrainLineBudget = 200
$script:BatchDrainCharBudget = 8000
# A single DataReceived record is materialized by Process before our callback
# sees it. Bound what we retain from that record, and keep it smaller than the
# render budget so one queue item can never defeat a UI tick's character cap.
$script:BatchQueueRecordCharMax = [Math]::Max(1, $script:BatchDrainCharBudget - 2)
# Machine-readable result records (R010 / CORE-002). Emits one authoritative
# per-target terminal record: `wintage-result: { "target": "...", "status": "...", "code": N }`.
# Results are owned by a separate bounded accumulator; output pressure cannot
# evict them. Hashtable keys are case-insensitive and duplicates keep latest.
$script:BatchResults = @{}
$script:BatchResultSeenTarget = @{}
$script:BatchResultMalformed = $false
$script:BatchResultMalformedReason = $null
function New-BatchQueueItem([string]$kind, [string]$text) {
    return [pscustomobject]@{ Kind = $kind; Text = $text; Time = (Get-Date).Ticks }
}

# Run a node helper the same way (stderr must not throw), returning its exit code.
function Invoke-NodeTool([string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & node @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($out) {
        foreach ($line in @($out)) { if ($null -ne $line) { Say-Log "$line" } }
    }
    $code
}

# PERF-005 + PERF-004 (T-240 / SRC-028:R014): ONE async batch worker per
# Apply/Revert via System.Diagnostics.Process with redirected stdout/stderr
# (not Start-Job), as the streaming primitive that satisfies R014:
#   - stdout/stderr callbacks enqueue bounded records into the producer queue;
#   - the UI timer drains a bounded character/line budget per tick and appends
#     ONE chunk to the log (bounded work per tick, never ScrollToCaret per line);
#   - overflow drops oldest ordinary history with one observable notice.
# Machine-readable wintage-result JSON records travel in the same stream but are
# parsed into BatchResults and suppressed from the human log.
function Start-BatchJob([string[]]$argsList, [scriptblock]$onDone) {
    if ($script:batchState -and -not $script:batchState.Cleared) {
        throw 'A batch is already active; refusing to replace its process and output queue.'
    }

    # Derive the result domain from the selected invocation. Result records are
    # stored separately from human output and keyed by target in the .NET bridge.
    $expectedTargets = @()
    for ($i = 0; $i -lt ($argsList.Count - 1); $i++) {
        if ($argsList[$i] -eq '-Selected') {
            $expectedTargets = @(([string]$argsList[$i + 1] -split ',') | Where-Object { $_ })
            break
        }
    }
    if (-not $expectedTargets.Count) { $expectedTargets = @($script:TfSelectedTargets) }
    $script:TfSelectedTargets = @($expectedTargets)

    # Process.DataReceived handlers run on .NET I/O threads. PowerShell script
    # block event delegates are not safe on those threads in Windows PowerShell
    # 5.1, so this tiny managed bridge owns callbacks and hands bounded records
    # to the UI timer. It never calls back into PowerShell from a worker thread.
    if (-not ('WintageBatchOutputBridge' -as [type])) {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $bridgeSource = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Web.Script.Serialization;

public sealed class WintageBatchOutputRecord {
    public string Kind { get; private set; }
    public string Text { get; private set; }
    public WintageBatchOutputRecord(string kind, string text) { Kind = kind; Text = text; }
}

public sealed class WintageBatchOutputBridge {
    private readonly object gate = new object();
    private readonly Queue<WintageBatchOutputRecord> output = new Queue<WintageBatchOutputRecord>();
    private readonly HashSet<string> expected;
    private readonly Dictionary<string, string> results = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> dirtyResults = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    private readonly int maxLines;
    private readonly int recordMax;
    private readonly int resultMax;
    private int dropped;
    private int callbacks;
    private int maxQueue;
    private int maxRecord;
    private long received;
    private bool stdoutEof;
    private bool stderrEof;
    private bool malformed;
    private string malformedReason;
    private DataReceivedEventHandler stdoutHandler;
    private DataReceivedEventHandler stderrHandler;

    public WintageBatchOutputBridge(string[] targets, int maxLines, int recordMax, int resultMax) {
        expected = new HashSet<string>(targets ?? new string[0], StringComparer.OrdinalIgnoreCase);
        this.maxLines = Math.Max(1, maxLines);
        this.recordMax = Math.Max(1, recordMax);
        this.resultMax = Math.Max(256, resultMax);
        stdoutHandler = delegate(object sender, DataReceivedEventArgs e) { Receive(false, e); };
        stderrHandler = delegate(object sender, DataReceivedEventArgs e) { Receive(true, e); };
    }

    public void Attach(Process process) {
        process.OutputDataReceived += stdoutHandler;
        process.ErrorDataReceived += stderrHandler;
    }

    public void Detach(Process process) {
        if (process == null) return;
        try { process.OutputDataReceived -= stdoutHandler; } catch { }
        try { process.ErrorDataReceived -= stderrHandler; } catch { }
    }

    private void Receive(bool isError, DataReceivedEventArgs args) {
        ReceiveLine(isError, args == null ? null : args.Data);
    }

    private void ReceiveLine(bool isError, string data) {
        Interlocked.Increment(ref callbacks);
        try {
            if (data == null) {
                lock (gate) {
                    if (isError) stderrEof = true;
                    else stdoutEof = true;
                }
                return;
            }
            string line = data;
            if (!isError && line.StartsWith("wintage-result:", StringComparison.OrdinalIgnoreCase)) {
                StoreResult(line);
                return;
            }
            Interlocked.Increment(ref received);
            int keptLength = line.Length;
            if (keptLength > recordMax) {
                const string marker = "[oversized output line truncated] ";
                int suffixLength = Math.Max(0, recordMax - marker.Length);
                line = marker + line.Substring(line.Length - suffixLength);
                keptLength = line.Length;
            }
            lock (gate) {
                if (output.Count >= maxLines) {
                    output.Dequeue();
                    dropped++;
                }
                output.Enqueue(new WintageBatchOutputRecord(isError ? "err" : "out", line));
                if (output.Count > maxQueue) maxQueue = output.Count;
                if (keptLength > maxRecord) maxRecord = keptLength;
            }
        } catch (Exception ex) {
            lock (gate) {
                malformed = true;
                malformedReason = "output bridge callback failed: " + ex.Message;
            }
        } finally {
            Interlocked.Decrement(ref callbacks);
        }
    }

    public bool StartFallbackReader(Process process, bool isError) {
        if (process == null) return false;
        try {
            return ThreadPool.QueueUserWorkItem(delegate(object unused) {
                try {
                    StreamReader reader = isError ? process.StandardError : process.StandardOutput;
                    string line;
                    while ((line = reader.ReadLine()) != null) ReceiveLine(isError, line);
                    ReceiveLine(isError, null);
                } catch (Exception ex) {
                    MarkMalformed("fallback output reader failed: " + ex.Message);
                    ReceiveLine(isError, null);
                }
            });
        } catch (Exception ex) {
            MarkMalformed("fallback output reader could not start: " + ex.Message);
            return false;
        }
    }

    private void StoreResult(string line) {
        if (line.Length > resultMax) {
            MarkMalformed("machine result exceeds the allowed record size");
            return;
        }
        try {
            string json = line.Substring("wintage-result:".Length).Trim();
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = resultMax;
            object parsed = serializer.DeserializeObject(json);
            Dictionary<string, object> fields = parsed as Dictionary<string, object>;
            object targetValue;
            if (fields == null || !fields.TryGetValue("target", out targetValue) || !(targetValue is string)) {
                MarkMalformed("machine result has no string target");
                return;
            }
            string target = (string)targetValue;
            if (!expected.Contains(target)) {
                MarkMalformed("machine result target is not selected: " + target);
                return;
            }
            lock (gate) {
                results[target] = line;
                dirtyResults[target] = line;
            }
        } catch (Exception ex) {
            MarkMalformed("malformed machine result: " + ex.Message);
        }
    }

    private void MarkMalformed(string reason) {
        lock (gate) {
            malformed = true;
            malformedReason = reason;
        }
    }

    public WintageBatchOutputRecord[] TakeOutputRecords(int lineBudget, int charBudget) {
        lineBudget = Math.Max(1, lineBudget);
        charBudget = Math.Max(1, charBudget);
        List<WintageBatchOutputRecord> taken = new List<WintageBatchOutputRecord>();
        int chars = 0;
        lock (gate) {
            if (dropped > 0 && taken.Count < lineBudget) {
                string notice = "[older batch output truncated: " + dropped.ToString() + " lines]";
                taken.Add(new WintageBatchOutputRecord("out", notice));
                chars = notice.Length;
                dropped = 0;
            }
            while (taken.Count < lineBudget && output.Count > 0) {
                WintageBatchOutputRecord record = output.Peek();
                string text = record.Text ?? "";
                int separator = taken.Count > 0 ? 2 : 0;
                if (taken.Count > 0 && chars + separator + text.Length > charBudget) break;
                if (text.Length > charBudget) text = text.Substring(text.Length - charBudget);
                output.Dequeue();
                taken.Add(new WintageBatchOutputRecord(record.Kind, text));
                chars += separator + text.Length;
            }
        }
        return taken.ToArray();
    }

    public string[] TakeResultRecords() {
        lock (gate) {
            string[] records = new string[dirtyResults.Count];
            dirtyResults.Values.CopyTo(records, 0);
            dirtyResults.Clear();
            return records;
        }
    }

    public bool StdoutEof { get { lock (gate) { return stdoutEof; } } }
    public bool StderrEof { get { lock (gate) { return stderrEof; } } }
    public bool Malformed { get { lock (gate) { return malformed; } } }
    public string MalformedReason { get { lock (gate) { return malformedReason; } } }
    public int CallbacksInFlight { get { return Interlocked.CompareExchange(ref callbacks, 0, 0); } }
    public int OutputQueueCount { get { lock (gate) { return output.Count; } } }
    public int PendingResultCount { get { lock (gate) { return dirtyResults.Count; } } }
    public int ResultCount { get { lock (gate) { return results.Count; } } }
    public int MaxOutputQueueObserved { get { lock (gate) { return maxQueue; } } }
    public int MaxRecordObserved { get { lock (gate) { return maxRecord; } } }
    public int DroppedLines { get { lock (gate) { return dropped; } } }
    public long ReceivedOrdinaryLines { get { return Interlocked.Read(ref received); } }
}
"@
        Add-Type -TypeDefinition $bridgeSource -ReferencedAssemblies 'System.Web.Extensions' -ErrorAction Stop
    }

    if ($null -eq $script:BatchOutputQueue) {
        $script:BatchOutputQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    }
    if ($null -eq $script:BatchQueueGate) { $script:BatchQueueGate = New-Object object }
    [System.Threading.Monitor]::Enter($script:BatchQueueGate)
    try {
        # ConcurrentQueue<T>.Clear() is unavailable on the .NET Framework used
        # by Windows PowerShell 5.1; replace the queue at the batch boundary.
        $script:BatchOutputQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
        $script:BatchQueueLines = 0
        $script:BatchDroppedLines = 0
    } finally {
        [System.Threading.Monitor]::Exit($script:BatchQueueGate)
    }
    $script:BatchResults = @{}
    $script:BatchResultSeenTarget = @{}
    $script:BatchResultMalformed = $false
    $script:BatchResultMalformedReason = $null

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = ($argsList | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true

    $script:batchExitCode = $null
    $script:batchCompleted = $false
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 120

    $bridge = [WintageBatchOutputBridge]::new([string[]]$expectedTargets, [int]$script:BatchQueueMax, [int]$script:BatchQueueRecordCharMax, 65536)
    $st = @{
        Process               = $proc
        ProcessId             = $null
        Timer                 = $timer
        OutputBridge          = $bridge
        Done                  = $false
        Consumed              = $false
        CleanedUp             = $false
        Finalized             = $false
        Cleared               = $false
        ProcessDisposed       = $false
        TimerDisposed         = $false
        OnDone                = $onDone
        Queue                 = $script:BatchOutputQueue
        ExpectedTargets       = @($expectedTargets)
        ResultsByTarget       = $script:BatchResults
        StdoutEof             = $false
        StderrEof             = $false
        ResultChannelSettled  = $false
        CallbacksInFlight     = 0
        ResultMalformed       = $false
        ResultMalformedReason = $null
        HasExited             = $false
        ExitCode              = $null
    }
    $script:batchState = $st

    # C# callbacks are attached before Start and both Begin*ReadLine calls.
    $bridge.Attach($proc)
    Disable-BatchUi
    $timer.Add_Tick({
        $st = $script:batchState
        if ($null -eq $st) { return }
        $bridge = $st.OutputBridge

        # E-891 anti-crash contract: NOTHING in the per-tick transport work may
        # escape to Timer.OnTick as an unhandled WinForms exception. Result
        # parsing, ordinary enqueue and the bounded drain are all contained; a
        # transient failure is recorded and the next tick retries -- it never
        # kills the message pump or wedges the finalization barrier below.
        try {
            foreach ($line in @($bridge.TakeResultRecords())) {
                try {
                    $payloadText = ([string]$line).Substring('wintage-result:'.Length).Trim()
                    if (-not $payloadText) { throw 'empty result payload' }
                    $payload = $payloadText | ConvertFrom-Json -ErrorAction Stop
                    Add-BatchMachineResultFromPayload $payload $st
                } catch {
                    Set-BatchResultMalformed $_.Exception.Message $st
                }
            }
            if ($bridge.Malformed) {
                Set-BatchResultMalformed $bridge.MalformedReason $st
            }
            foreach ($record in @($bridge.TakeOutputRecords($script:BatchDrainLineBudget, $script:BatchDrainCharBudget))) {
                Enqueue-BatchItem (New-BatchQueueItem ([string]$record.Kind) ([string]$record.Text))
            }
            $script:BatchDroppedLines = [int]$bridge.DroppedLines
            $drained = Drain-BatchQueue $st.Queue
            if ($drained) { Say-Log $drained }
        } catch {
            try { Say-Log ('BATCH OUTPUT DRAIN FAILED: ' + $_.Exception.Message) } catch { }
            return
        }

        $st.StdoutEof = [bool]$bridge.StdoutEof
        $st.StderrEof = [bool]$bridge.StderrEof
        $st.CallbacksInFlight = [int]$bridge.CallbacksInFlight
        $st.ResultChannelSettled = $st.StdoutEof -and $st.CallbacksInFlight -eq 0 -and $bridge.PendingResultCount -eq 0
        if (-not $st.StdoutEof -or -not $st.StderrEof -or -not $st.ResultChannelSettled) { return }

        $processExited = $false
        try { $processExited = [bool]$st.Process.HasExited } catch { }
        if (-not $processExited) { return }
        if ($st.CallbacksInFlight -ne 0 -or $bridge.OutputQueueCount -ne 0 -or $bridge.PendingResultCount -ne 0) { return }
        if ($st.Queue -and -not $st.Queue.IsEmpty) { return }
        if ($script:BatchQueueLines -ne 0) { return }
        if (-not $st.HasExited) {
            $st.HasExited = $true
            try { $st.ExitCode = [int]$st.Process.ExitCode } catch { $st.ExitCode = 1 }
            $script:batchExitCode = $st.ExitCode
            $script:batchCompleted = $true
        }
        $st.Consumed = $true
        Complete-BatchWorker $st
    })
    # Start the UI pump before the child. The click handler owns this thread, so
    # no tick can run until Start-BatchJob returns with the process state bound.
    try {
        $timer.Start()
        if (-not [bool]$proc.Start()) { throw 'Process.Start returned false.' }
    } catch {
        try { $timer.Stop(); $timer.Dispose(); $st.TimerDisposed = $true } catch { }
        try { $bridge.Detach($proc) } catch { }
        try { $proc.Dispose(); $st.ProcessDisposed = $true } catch { }
        $st.Cleared = $true
        $script:batchState = $null
        try { Enable-BatchUi } catch { }
        throw
    }
    $st.ProcessId = [int]$proc.Id
    try {
        $proc.BeginOutputReadLine()
    } catch {
        if (-not $bridge.StartFallbackReader($proc, $false)) {
            Set-BatchResultMalformed ('stdout reader could not start: ' + $_.Exception.Message) $st
        }
    }
    try {
        $proc.BeginErrorReadLine()
    } catch {
        if (-not $bridge.StartFallbackReader($proc, $true)) {
            Set-BatchResultMalformed ('stderr reader could not start: ' + $_.Exception.Message) $st
        }
    }
    try { Say-Log 'batch worker started - the window stays responsive while it runs.' } catch { }
}

# PERF-003 (SRC-028:R014 / M3): bounded enqueue. Drops oldest ORDINARY records
# (never result/status items) when the queue exceeds BatchQueueMax, and emits
# one observable truncation notice instead of N per-line messages.
function Enqueue-BatchItem($item) {
    $q = $script:BatchOutputQueue
    if ($null -eq $q) { $q = New-Object System.Collections.Concurrent.ConcurrentQueue[object]; $script:BatchOutputQueue = $q }
    if ($null -eq $script:BatchQueueGate) { $script:BatchQueueGate = New-Object object }
    if ($null -eq $item) { return }

    # Compatibility seam: a result record accidentally sent to this function
    # still transfers to the result owner and never occupies the output queue.
    if ($item.Kind -eq 'result') {
        Add-BatchMachineResultFromPayload $item.Payload
        return
    }

    $text = [string]$item.Text
    $recordMax = [Math]::Max(1, [int]$script:BatchQueueRecordCharMax)
    if ($text.Length -gt $recordMax) {
        $marker = '[oversized output line truncated] '
        $suffixLength = [Math]::Max(0, $recordMax - $marker.Length)
        $text = $marker + $text.Substring($text.Length - $suffixLength)
        $item.Text = $text
    }

    $dropped = 0
    [System.Threading.Monitor]::Enter($script:BatchQueueGate)
    try {
        $max = [Math]::Max(1, [int]$script:BatchQueueMax)
        while ($script:BatchQueueLines -ge $max) {
            $discarded = $null
            if (-not $q.TryDequeue([ref]$discarded)) { break }
            if ($discarded -and $discarded.Kind -eq 'result') {
                # Older/injected queue entries are promoted before removal; a
                # result can never decrement ordinary occupancy or disappear.
                Add-BatchMachineResultFromPayload $discarded.Payload
            } else {
                $script:BatchQueueLines--
                $dropped++
            }
        }
        $null = $q.Enqueue($item)
        $script:BatchQueueLines++
        if ($dropped -gt 0) { $script:BatchDroppedLines += $dropped }
    } finally {
        [System.Threading.Monitor]::Exit($script:BatchQueueGate)
    }
}

# M004 / M4: drain up to a bounded line/character budget per tick, joining the
# drained records into ONE chunk so the log writer is called once per tick
# (never once per source line), with at most one scroll. Returns the joined
# text (possibly empty) to append via Say-Log.
function Drain-BatchQueue([System.Collections.Concurrent.ConcurrentQueue[object]]$q) {
    if ($null -eq $q) { return '' }
    $sb = New-Object System.Text.StringBuilder 4096
    $lineBudget = [Math]::Max(1, [int]$script:BatchDrainLineBudget)
    $charBudget = [Math]::Max(1, [int]$script:BatchDrainCharBudget)
    $collected = 0
    [System.Threading.Monitor]::Enter($script:BatchQueueGate)
    try {
        if ($script:BatchDroppedLines -gt 0 -and $collected -lt $lineBudget) {
            $notice = "[older batch output truncated: $($script:BatchDroppedLines) lines]"
            $script:BatchDroppedLines = 0
            $null = $sb.Append($notice)
            $collected++
        }
        while ($collected -lt $lineBudget) {
            $rec = $null
            if (-not $q.TryPeek([ref]$rec)) { break }
            if ($null -eq $rec) {
                $discardNull = $null
                if ($q.TryDequeue([ref]$discardNull) -and $script:BatchQueueLines -gt 0) { $script:BatchQueueLines-- }
                continue
            }
            if ($rec.Kind -eq 'result') {
                $resultRecord = $null
                if ($q.TryDequeue([ref]$resultRecord)) { Add-BatchMachineResultFromPayload $resultRecord.Payload }
                continue
            }
            $lineText = [string]$rec.Text
            $separatorLength = if ($sb.Length -gt 0) { 2 } else { 0 }
            if ($sb.Length -gt 0 -and ($sb.Length + $separatorLength + $lineText.Length) -gt $charBudget) { break }
            if ($lineText.Length -gt $charBudget) {
                # Defensive for a queue entry injected without Enqueue-BatchItem.
                $lineText = $lineText.Substring($lineText.Length - $charBudget)
            }
            $dequeued = $null
            if (-not $q.TryDequeue([ref]$dequeued)) { break }
            $script:BatchQueueLines--
            if ($sb.Length -gt 0) { $null = $sb.Append("`r`n") }
            $null = $sb.Append($lineText)
            $collected++
        }
    } finally {
        [System.Threading.Monitor]::Exit($script:BatchQueueGate)
    }
    return $sb.ToString()
}

# M6/M10: accumulate authoritative per-target result records. A duplicate target
# keeps the LATEST (B supersedes A within the same run). Used for CORE-002 truth
# classification at completion.
function Set-BatchResultMalformed([string]$reason, $batchState = $script:batchState) {
    $script:BatchResultMalformed = $true
    $script:BatchResultMalformedReason = $reason
    if ($batchState) {
        $batchState.ResultMalformed = $true
        $batchState.ResultMalformedReason = $reason
    }
}

function Add-BatchMachineResult([string]$target, [string]$status, [int]$code, $batchState = $script:batchState) {
    if (-not $target -or -not $status) { Set-BatchResultMalformed 'result target/status missing' $batchState; return }
    $expected = if ($batchState) { @($batchState.ExpectedTargets) } else { @($script:TfSelectedTargets) }
    if (-not $expected.Count -or $expected -notcontains $target) {
        Set-BatchResultMalformed "unexpected result target '$target'" $batchState
        return
    }
    $status = $status.ToUpperInvariant()
    if ($status -notin @('SUCCESS', 'FAILED') -or ($status -eq 'SUCCESS' -and $code -ne 0) -or ($status -eq 'FAILED' -and $code -eq 0)) {
        Set-BatchResultMalformed "invalid result status/code for '$target'" $batchState
        return
    }
    $entry = [pscustomobject]@{ target = $target; status = $status; code = [int]$code }
    # Map overwrite is intentional: the established contract lets the latest
    # duplicate record for a selected target supersede its earlier record.
    $script:BatchResults[$target] = $entry
    $script:BatchResultSeenTarget[$target] = $true
    if ($batchState -and $batchState.ResultsByTarget -ne $script:BatchResults) { $batchState.ResultsByTarget[$target] = $entry }
}

function Add-BatchMachineResultFromPayload($payload, $batchState = $script:batchState) {
    if ($null -eq $payload) { Set-BatchResultMalformed 'result payload missing' $batchState; return }
    $targetProperty = $payload.PSObject.Properties['target']
    $statusProperty = $payload.PSObject.Properties['status']
    $codeProperty = $payload.PSObject.Properties['code']
    if (-not $targetProperty -or -not $statusProperty -or -not $codeProperty) {
        Set-BatchResultMalformed 'result payload must contain target, status and code' $batchState
        return
    }
    $code = $codeProperty.Value
    if ($code -isnot [byte] -and $code -isnot [int16] -and $code -isnot [int32] -and $code -isnot [int64]) {
        Set-BatchResultMalformed 'result code must be an integer' $batchState
        return
    }
    if ($code -lt [int]::MinValue -or $code -gt [int]::MaxValue) {
        Set-BatchResultMalformed 'result code is outside the Int32 range' $batchState
        return
    }
    Add-BatchMachineResult ([string]$targetProperty.Value) ([string]$statusProperty.Value) ([int]$code) $batchState
}

# Classify a run from the collected machine result records (M7: authoritative
# per-target classification). Missing or malformed records fail closed; ordinary
# output can never impersonate the machine result contract.
# $Selected defaults to the Fonts-tab selection so the Tf handler keeps its
# existing call shape; the main Apply/Revert handlers pass their own checked set.
# Every returned verdict carries FailedNames so a caller never has to re-derive
# the failure list from the log prose -- that re-derivation is what made a
# 12-target run with one failure report all 12 as failed.
function Classify-BatchResult($st, [string[]]$Selected) {
    $exitCode = if ($null -ne $st.ExitCode) { [int]$st.ExitCode } else { 1 }
    $selected = if ($null -ne $Selected) { @($Selected) } else { @($script:TfSelectedTargets) }
    $records = @($script:BatchResults.Values)
    if ($st.ResultMalformed -or $script:BatchResultMalformed) {
        $reason = if ($st.ResultMalformedReason) { $st.ResultMalformedReason } else { $script:BatchResultMalformedReason }
        return [pscustomobject]@{ Kind = 'FAILED'; FailedNames = @($selected); Message = "apply FAILED: malformed machine result record ($reason)" }
    }
    $missing = @($selected | Where-Object { -not $script:BatchResultSeenTarget.ContainsKey($_) })
    if (-not $records.Count -or $missing.Count) {
        $names = if ($missing.Count) { $missing -join ', ' } else { $selected -join ', ' }
        return [pscustomobject]@{ Kind = 'FAILED'; FailedNames = @($selected); Message = "apply FAILED: missing result record for target(s): $names" }
    }
    $selectedRecords = @($selected | ForEach-Object { $script:BatchResults[$_] })
    $failed = @($selectedRecords | Where-Object { [int]$_.code -ne 0 -or $_.status -ne 'SUCCESS' })
    $failedNames = @($failed | ForEach-Object { $_.target })
    if ($failed.Count -eq 0 -and $exitCode -eq 0) {
        return [pscustomobject]@{ Kind = 'SUCCESS'; FailedNames = @(); Message = 'apply done. (SUCCESS)' }
    } elseif ($failed.Count -eq 0) {
        return [pscustomobject]@{ Kind = 'FAILED'; FailedNames = @($selected); Message = "apply FAILED: child process exit code $exitCode" }
    } elseif ($failed.Count -lt $selectedRecords.Count) {
        $detail = @($failed | ForEach-Object { "$($_.target)=$($_.code)" })
        return [pscustomobject]@{ Kind = 'PARTIAL'; FailedNames = $failedNames; Message = "apply PARTIAL: failed targets: $($detail -join ', '). Successful targets completed." }
    } else {
        $detail = @($failed | ForEach-Object { "$($_.target)=$($_.code)" })
        return [pscustomobject]@{ Kind = 'FAILED'; FailedNames = $failedNames; Message = "apply FAILED: $($detail -join ', ')" }
    }
}

# R014 (SRC-028) + W2-005: ONE terminal-finalization path per batch, streaming
# variant. Done once, drain once, Process+Timer disposal once, OnDone once,
# state cleared once, UI restored once. Process-sourced batches never call
# Receive-Job -- the UI timer already drained the streaming queue into the log
# and collected machine-result records incrementally.
function Complete-BatchWorker($st) {
    if ($null -eq $st -or $st.Done -or -not $st.Consumed) { return }
    if ($st.Process) {
        $processExited = $false
        try { $processExited = [bool]$st.Process.HasExited } catch { }
        if (-not $processExited -or -not $st.StdoutEof -or -not $st.StderrEof -or -not $st.ResultChannelSettled -or $st.CallbacksInFlight -ne 0) { return }
        if ($st.OutputBridge -and ($st.OutputBridge.OutputQueueCount -ne 0 -or $st.OutputBridge.PendingResultCount -ne 0)) { return }
        if ($st.Queue -and -not $st.Queue.IsEmpty) { return }
        if ($script:BatchQueueLines -ne 0) { return }
    }
    $st.Done = $true
    try {
        # The terminal tick arrives only after both streams reached EOF and the
        # bounded queue drained. Never cancel an async read to manufacture EOF.
        if (-not $st.CleanedUp) {
            if ($st.Timer -and -not $st.TimerDisposed) {
                try { $st.Timer.Stop() } catch { }
                try { $st.Timer.Dispose() } catch { }
                $st.TimerDisposed = $true
            }
            if ($st.Process) {
                try { if ($st.OutputBridge) { $st.OutputBridge.Detach($st.Process); $st.BridgeDetached = $true } } catch { }
                if (-not $st.ProcessDisposed) {
                    try { $st.Process.Dispose() } catch { }
                    $st.ProcessDisposed = $true
                }
            } elseif ($st.Job) {
                # Legacy Job path: one final Receive-Job (never replays line by
                # line into the log -- the streaming queue already did).
                try {
                    $result = Receive-Job $st.Job
                    if ($result -is [array]) {
                        $customObj = $result | Where-Object { $_ -and ($_.PSObject.Properties['Output']) } | Select-Object -Last 1
                        if ($customObj) { $result = $customObj }
                        else { $result = [pscustomobject]@{ Output = @($result); ExitCode = 0 } }
                    }
                    if (-not $result) { $result = [pscustomobject]@{ Output = @(); ExitCode = 1 } }
                    $st.Result = $result
                } catch {
                    Say-Log ('BATCH FAILED: ' + $_.Exception.Message)
                    $st.Result = [pscustomobject]@{ Output = @(); ExitCode = 1 }
                }
                try { Remove-Job $st.Job -Force -ErrorAction SilentlyContinue } catch { }
            }
            $st.CleanedUp = $true
        }
        if (-not $st.Finalized) {
            $st.Finalized = $true
            try {
                # Normalize completion argument: streaming batches already have
                # ExitCode + BatchResults; legacy batches carry st.Result.
                $completionHandler = $st.OnDone
                if ($completionHandler) {
                    if ($st.Result) { & $completionHandler $st.Result }
                    else { & $completionHandler $st }
                }
            } catch {
                Say-Log ('BATCH COMPLETION HANDLER FAILED: ' + $_.Exception.Message)
            }
        }
    } finally {
        # W2-004 (T-246:R009): re-enable all generation-mutating and selection
        # controls once the batch worker has fully completed.
        try { Enable-BatchUi } catch { }
        if (-not $st.Cleared) {
            $st.Cleared = $true
            $script:batchState = $null
        }
    }
}

# W2-005 (SRC-007:R010): the authoritative FormClosing contract. A close is
# answered ONLY from the lifecycle state, never from button Enabled flags.
#   - no active batch            -> close normally;
#   - batch active (not Cleared) -> cancel the close, keep the worker alive
#     (no Stop-Job, no child kill, no early timer dispose), tell the user;
#   - batch terminal and consumed-> close normally. Rapid repeated close
#     attempts while active hit the same guard: no duplicate cleanup, no
#     duplicate completion callback, no timer corruption, no worker kill.
# Destructive mid-target cancellation is deliberately NOT implemented here:
# there is no safe cooperative-cancellation contract yet (non-goal).
function Test-BatchCloseSafe {
    $st = $script:batchState
    if ($null -eq $st) { return $true }
    return [bool]$st.Cleared
}

$form.Add_FormClosing({
    param($sender, $e)
    if (Test-BatchCloseSafe) { return }
    $e.Cancel = $true
    Say-Log 'An Apply/Revert batch is still running - the window stays open until it completes. Closing is refused so the running operation keeps its owner.'
})

# W2-004 (T-246:R009): shared generation lock -- the pending shape is
# wired here too, not only inside Invoke-CustomMutation. A Save-Custom that
# tried to publish while the batch holder keeps the lock must receive a
# structured contention, not an unsolicited background throw after the batch
# releases. Implemented through -ErrorAction Stop so the caller's `catch`
# sees it as a bearing the `W2-004:` prefix.
function Enter-BatchLockWithSeam { return Enter-BatchLockShared }

# Build the single -Selected argument list for a batch Apply/Revert from the
# checked rows, carrying the same per-target path overrides the serial loop did.
function Get-BatchArgs([string[]]$keys, [string]$slug, [switch]$isRevert) {
    $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here 'install.ps1'), "-Selected", ($keys -join ','))
    if (-not $isRevert) { $argsList += @("-Palette", $slug) }
    else { $argsList += "-Revert" }
    # CORE-004: every GUI-owned path-bearing target is forwarded from the same
    # canonical map, so adding one cannot be forgotten in this argument list.
    foreach ($k in $script:PATH_TARGETS_MAP.Keys) {
        if ($keys -contains $k -and $script:customPaths.ContainsKey($k)) {
            $argsList += @($script:PATH_TARGETS_MAP[$k].Param, $script:customPaths[$k])
        }
    }
    $argsList
}

# Parse the failed target names out of a batch worker result: per-target
# "$name: FAILED" lines plus the "Install incomplete: N target(s) failed (a, b)"
# summary. Returns the de-duplicated key list.
function Get-BatchFailures($result) {
    $failed = @()
    if (-not $result -or -not $result.Output) { return $failed }
    foreach ($line in @($result.Output)) {
        if ($null -eq $line) { continue }
        $s = "$line"
        $m = [regex]::Match($s, '^(\S+)\s*:\s*FAILED')
        if ($m.Success) { $failed += $m.Groups[1].Value }
        $m2 = [regex]::Match($s, 'failed \((.*?)\)\.?\s*$')
        if ($m2.Success) { $failed += @($m2.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    }
    @($failed | Sort-Object -Unique)
}

# T-192 P1#26: Save/Delete-Custom are ONE transaction. The pack is mutated, then
# the generators run; if EITHER generator fails, the previous custom.json is
# restored and the generated outputs are regenerated from it - source and
# generated state can never diverge, and a failed save never leaves a broken
# half-generated theme behind.
# W2-004 (T-246:R009): the whole Save/Delete runs under the shared
# Wintage-Build mutex, so a batch Apply's check+dispatch window cannot see
# generation B between target 1 and target 2. The lock covers publication,
# not each file.
function Invoke-CustomMutation([scriptblock]$mutate, [string]$label) {
    $file = Join-Path $themeDir 'custom.json'
    $hadOld = Test-Path $file
    $oldBytes = if ($hadOld) { [System.IO.File]::ReadAllBytes($file) } else { $null }
    $batchLock = $null
    $prevBuildLockHeld = $env:WINTAGE_BUILD_LOCK_HELD
    try {
        $batchLock = Enter-BatchLockShared
        # W2-004 (T-246:R009) reentrancy: this GUI process already HOLDS the
        # generation lock; its child node build-desktop.js must not deadlock trying
        # to re-acquire it. W2-002 (audit/7 T-269): the marker carries THIS
        # acquisition's token, so a child can prove the live holder before
        # skipping; it no longer makes the env var a serialization bypass.
        if ($batchLock) { $env:WINTAGE_BUILD_LOCK_HELD = [string]$batchLock.GenLock.Token }
        try {
            & $mutate
            $code1 = Invoke-NodeTool @((Join-Path $root 'tools/apply-themes.js'))
            if ($code1 -ne 0) { throw 'apply-themes.js failed - theme packs are stale.' }
            $code2 = Invoke-NodeTool @((Join-Path $root 'tools/build-desktop.js'))
            if ($code2 -ne 0) { throw 'build-desktop.js failed - desktop/out is stale.' }
            Load-Packs
        } catch {
            if ($hadOld) { [System.IO.File]::WriteAllBytes($file, $oldBytes) }
            elseif (Test-Path $file) { Remove-Item $file -Force }
            try {
                $null = Invoke-NodeTool @((Join-Path $root 'tools/apply-themes.js'))
                $null = Invoke-NodeTool @((Join-Path $root 'tools/build-desktop.js'))
                Load-Packs
                Say-Log "$label FAILED - the previous custom theme was restored and the generated outputs regenerated."
            } catch {
                Say-Log "$label FAILED and the rollback regeneration ALSO failed: $($_.Exception.Message) - run apply-themes.js/build-desktop.js by hand."
            }
            throw "$label FAILED: $($_.Exception.Message) - nothing was installed."
        }
    } finally {
        # W2-002 (audit/7 T-269): restore the PRIOR marker state, never an
        # unconditional remove - an outer genuine holder's marker must survive
        # this nested GUI mutation.
        if ($null -eq $prevBuildLockHeld) { Remove-Item Env:WINTAGE_BUILD_LOCK_HELD -ErrorAction SilentlyContinue -WhatIf:$false }
        else { $env:WINTAGE_BUILD_LOCK_HELD = $prevBuildLockHeld }
        if ($batchLock) { Exit-BatchLock $batchLock }
    }
}

function Save-Custom {
    $t = Get-ActiveTokens
    $pack = [ordered]@{ slug = 'custom'; label = 'Custom'; order = 99; source = 'built in the Wintage Theme Installer'; tokens = [ordered]@{} }
    foreach ($k in $TOKENS) { $pack.tokens[$k] = $t.$k }
    $file = Join-Path $themeDir 'custom.json'
    $json = ($pack | ConvertTo-Json -Depth 5)
    Invoke-CustomMutation {
        [System.IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding $false))
        Say-Log "saved themes/custom.json"
    } 'Save-Custom'
}

function Delete-Custom {
    $file = Join-Path $themeDir 'custom.json'
    if (Test-Path $file) {
        Invoke-CustomMutation {
            Remove-Item $file -Force
            Say-Log "deleted themes/custom.json"
        } 'Delete-Custom'
        $script:current = 'goldendefault'
        $lstThemes.SelectedItem = $script:packs[$script:current].label
    } else {
        Say-Log "no custom theme to delete"
    }
}

$btnSave.Add_Click({
        try { Save-Custom } catch { Say-Log ("SAVE FAILED: " + $_.Exception.Message) }
    })

$btnDelCustom.Add_Click({
        try { Delete-Custom } catch { Say-Log ("DELETE FAILED: " + $_.Exception.Message) }
    })

$btnApply.Add_Click({
        $btnApply.Enabled = $false
        $btnRevert.Enabled = $false
        try {
            $slug = if ($script:current -eq '<custom>') { Save-Custom; 'custom' } else { $script:current }
            $checked = @(Get-CheckedTargetItems)
            if (-not $checked) { Say-Log 'nothing selected'; $btnApply.Enabled = $true; $btnRevert.Enabled = $true; return }
            $keys = @($checked | ForEach-Object { ($_ -split '\s+')[0] })
            # PERF-005 (T-240): ONE async batch worker for the whole checked set.
            # The completion block runs on the UI thread via the Forms.Timer.
            $doneSlug = $slug
            Start-BatchJob (Get-BatchArgs $keys $slug) {
                param($child)
                try {
                    # $child is the batch STATE on the streaming path (it carries
                    # ExitCode and ResultsByTarget, and has no Output property),
                    # and a {Output;ExitCode} wrapper only on the legacy Job path.
                    # Reading $child.Output unconditionally made Get-BatchFailures
                    # return empty, so the `= @($keys)` fallback below reported
                    # every target as failed whenever the child exited non-zero.
                    $failed = @()
                    if ($child -is [pscustomobject] -and -not $child.ExitCode -and -not $child.Process -and $child.Result) {
                        # Legacy: no machine records, only the streamed log prose.
                        $failed = @(Get-BatchFailures $child.Result)
                        if ($child.Result.ExitCode -ne 0 -and -not $failed.Count) { $failed = @($keys) }
                    } else {
                        $verdict = Classify-BatchResult $child $keys
                        if ($verdict.Kind -ne 'SUCCESS') { Say-Log $verdict.Message }
                        $failed = @($verdict.FailedNames)
                    }
                    Load-Targets
                    Update-FbButtonsVisibility
                    if ($failed.Count) {
                        $status.Text = "Applied '$doneSlug' with $($failed.Count) failure(s): $($failed -join ', '). See the log - nothing more was installed for those targets."
                        $status.ForeColor = [System.Drawing.Color]::Firebrick
                    } else {
                        # A later success must visibly reset the failure colour (T-189).
                        $status.Text = "Applied '$doneSlug'. Restart any app that was themed."
                        $tokensNow = Get-ActiveTokens
                        if ($tokensNow) { $status.ForeColor = C $tokensNow.textPrimary }
                    }
                }
                catch { Say-Log ('APPLY FAILED: ' + $_.Exception.Message); $status.Text = 'Apply failed - see the log.' }
                finally { $btnApply.Enabled = $true; $btnRevert.Enabled = $true }
            }
        }
        catch { Say-Log ('APPLY FAILED: ' + $_.Exception.Message); $status.Text = 'Apply failed - see the log.'; $btnApply.Enabled = $true; $btnRevert.Enabled = $true }
    })

$btnSelectAll.Add_Click({
        foreach ($target in $script:targets) {
            $state = $target.State
            if ($state -eq 'not installed' -or $state -eq 'fused shut') { continue }
            $target.List.SetItemChecked($target.ItemIndex, $true)
        }
        Update-FbButtonsVisibility
    })
$btnSelectNone.Add_Click({
        foreach ($list in $TARGET_LISTS) {
            for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $false) }
        }
        Update-FbButtonsVisibility
    })

$btnRevert.Add_Click({
        $btnApply.Enabled = $false
        $btnRevert.Enabled = $false
        try {
            $checkedNow = @(Get-CheckedTargetItems)
            if (-not $checkedNow) { Say-Log 'nothing selected'; $btnApply.Enabled = $true; $btnRevert.Enabled = $true; return }
            $keys = @($checkedNow | ForEach-Object { ($_ -split '\s+')[0] })
            # PERF-005 (T-240): ONE async batch worker for the whole checked set.
            Start-BatchJob (Get-BatchArgs $keys '' -isRevert) {
                param($child)
                try {
                    # Same shape split as the Apply handler: state on the streaming
                    # path, {Output;ExitCode} only on the legacy Job path.
                    $failed = @()
                    if ($child -is [pscustomobject] -and -not $child.ExitCode -and -not $child.Process -and $child.Result) {
                        $failed = @(Get-BatchFailures $child.Result)
                        if ($child.Result.ExitCode -ne 0 -and -not $failed.Count) { $failed = @($keys) }
                    } else {
                        $verdict = Classify-BatchResult $child $keys
                        if ($verdict.Kind -ne 'SUCCESS') { Say-Log $verdict.Message }
                        $failed = @($verdict.FailedNames)
                    }
                    Load-Targets
                    if ($failed.Count) {
                        $status.Text = "Revert incomplete: $($failed.Count) target(s) failed ($($failed -join ', ')). See the log."
                        $status.ForeColor = [System.Drawing.Color]::Firebrick
                    } else {
                        # A later success must visibly reset the failure colour (T-189).
                        $status.Text = 'Revert done - the marked targets are back to their pre-Wintage state.'
                        $tokensNow = Get-ActiveTokens
                        if ($tokensNow) { $status.ForeColor = C $tokensNow.textPrimary }
                    }
                }
                catch { Say-Log ('REVERT FAILED: ' + $_.Exception.Message); $status.Text = 'Revert failed - see the log.' }
                finally { $btnApply.Enabled = $true; $btnRevert.Enabled = $true }
            }
        }
        catch { Say-Log ('REVERT FAILED: ' + $_.Exception.Message); $status.Text = 'Revert failed - see the log.'; $btnApply.Enabled = $true; $btnRevert.Enabled = $true }
    })

$lstThemes.Add_SelectedIndexChanged({
        $sel = $lstThemes.SelectedItem
        if (-not $sel) { return }
        if ($sel -eq 'Custom') {
            if (-not $script:custom) {
                $src = Get-ActiveTokens
                $script:custom = @{}
                foreach ($k in $TOKENS) { $script:custom[$k] = $src[$k] }
            }
            $script:current = '<custom>'
        }
        else {
            $script:current = ($script:packs.Values | Where-Object { $_.label -eq $sel } | Select-Object -First 1).slug
        }
        Refresh-Swatches; Update-Info; $preview.Invalidate()
    })

# ---- SKIN THE INSTALLER ITSELF ----
# The window wears the palette it is about to install. It is the fastest possible
# preview and it also keeps the tool honest: a palette that makes this window
# unreadable is one you can see is unreadable.
function Skin-Self {
    $t = Get-ActiveTokens
    if (-not $t) { return }
    $form.BackColor = C $t.background
    $form.ForeColor = C $t.textPrimary

    $pnlThemes.BackColor = C $t.background
    $pnlThemes.ForeColor = C $t.textPrimary
    $pnlBetterDiscord.BackColor = C $t.background
    $pnlBetterDiscord.ForeColor = C $t.textPrimary
    $pnlFonts.BackColor = C $t.background
    $pnlFonts.ForeColor = C $t.textPrimary

    Update-TabButtons

    foreach ($c in @($lblThemes, $lblMyApps, $lblPopularApps, $lblPreview, $lblTokens, $lblInfo, $lblLanguage, $status,
                    $chkLogonTask, $lblBdTitle, $lblBdDesc,
                    $lblTfTitle, $lblTfSearch, $lblTfPreview, $lblTfControls, $lblTfFamily, $lblTfFamilyValue,
                    $lblTfSize, $lblTfRendering, $lblTfState, $lblTfLog, $lblTfMetrics,
                    $lblPreset, $lblPresetState)) {
        $c.BackColor = C $t.background; $c.ForeColor = C $t.textPrimary
    }
    foreach ($c in @($lstThemes, $clbMyApps, $clbPopularApps, $log, $cmbLanguage, $cmbPreset,
                    $txtTfSearch, $lstTfFonts, $txtTfLog, $cmbTfRendering, $numTfSize)) {
        $c.BackColor = C $t.compareBack; $c.ForeColor = C $t.textPrimary
    }
    $pnlTfPreview.BackColor = C $t.background
    foreach ($b in @($btnApply, $btnSave, $btnDelCustom, $btnRevert, $btnFbSound, $btnSelectAll, $btnSelectNone,
                    $btnBdOpenRepo,
                    $btnTfInstall, $btnTfApplyTerminal, $btnTfApplyConhost, $btnTfApplyBoth, $btnTfRestore, $btnTfSource, $btnTfLicense, $btnTfRefresh,
                    $btnPresetSave, $btnPresetUpdate, $btnPresetRename, $btnPresetDelete)) {
        $b.BackColor = C $t.surfaceRaised; $b.ForeColor = C $t.textPrimary
        $b.FlatAppearance.BorderColor = C $t.borderHighlight
        $b.FlatAppearance.BorderSize = 2
    }
    $swatchPanel.BackColor = C $t.backgroundSoft
    $cmbLanguage.Invalidate()
}

Load-Targets
# PERF-001: terminal-font initialization is LAZY. Do NOT call Initialize-TfTab
# before ShowDialog — that eagerly loads all 20 bundled font files into private
# GDI+ collections and runs fixed-pitch probes before first paint. Set-ActiveTab
# initializes the subsystem on first Fonts-tab activation instead.
$script:TfInitialized = $false
Update-FbButtonsVisibility

# ---- SCENARIO PRESET LOGIC (T-257 / SRC-013) ----
# All preset state is GUI-local; none of these functions ever launches
# install.ps1. Loading a preset only restores desired UI state.
$script:presets = @()
$script:presetsInvalid = @()
$script:activePresetId = $null
$script:presetBaseline = $null   # palette slug + checked keys captured at load, for the modified marker

# CORE-001 (audit/7.md): ONE canonical preset identity. A ComboBox entry carries
# the stable preset id, never the display name, so two valid presets with equal
# names stay individually selectable and a visible selection always resolves to
# exactly one preset. Activate-Preset is the only routine that makes a preset
# active; Update/Rename/Delete derive their target from the visible selection.
function New-PresetComboItem($preset) {
    $item = [pscustomobject]@{ Id = [string]$preset.id; Name = [string]$preset.name }
    $item | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Name } -Force
    return $item
}

function Select-PresetComboItem([string]$id) {
    for ($i = 0; $i -lt $cmbPreset.Items.Count; $i++) {
        $item = $cmbPreset.Items[$i]
        if ($null -eq $item) { continue }
        $prop = $item.PSObject.Properties['Id']
        if ($prop -and [string]$prop.Value -eq $id) { $cmbPreset.SelectedIndex = $i; return $true }
    }
    return $false
}

function Get-SelectedPreset {
    $item = $cmbPreset.SelectedItem
    if ($null -eq $item) { return $null }
    $prop = $item.PSObject.Properties['Id']
    if (-not $prop) { return $null }
    $id = [string]$prop.Value
    if (-not $id) { return $null }
    return @($script:presets | Where-Object { $_.id -eq $id })[0]
}

function Activate-Preset([string]$id) {
    $p = @($script:presets | Where-Object { $_.id -eq $id })[0]
    if (-not $p) {
        $script:activePresetId = $null
        $script:presetBaseline = $null
        $cmbPreset.SelectedIndex = -1
        Update-PresetState
        return $false
    }
    [void](Select-PresetComboItem $p.id)
    Apply-PresetUiState $p
    return $true
}

function Get-CheckedTargetKeys {
    $keys = @()
    foreach ($list in $TARGET_LISTS) {
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            if ($list.GetItemChecked($i)) { $keys += (($list.Items[$i] -split '\s+')[0]) }
        }
    }
    return @($keys | Sort-Object -Unique)
}

# CORE-006 (audit/7.md): the normalized staged-state snapshot the modified
# marker compares against the preset baseline. Normalization is the point: the
# palette identity, a COMPLETE canonical token snapshot whenever the working
# palette is Custom (so a single swatch edit is visible even though the theme
# list selection does not move), and SORTED target keys (equivalent sets in a
# different order are the same state, never a false 'modified').
# PendingItem/PendingIndex/PendingValue let an ItemCheck caller pass the row
# being changed: ItemCheck fires BEFORE the check state commits, so re-reading
# GetItemChecked would report the PRE-click state on the first click.
function Get-PresetDirtyState {
    param([object]$PendingItem = $null, [int]$PendingIndex = -1, [string]$PendingValue = '')
    $keys = @()
    foreach ($list in $TARGET_LISTS) {
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            $checked = if ($list -eq $PendingItem -and $i -eq $PendingIndex) { $PendingValue -eq 'Checked' } else { $list.GetItemChecked($i) }
            if ($checked) { $keys += (($list.Items[$i] -split '\s+')[0]) }
        }
    }
    $tokensSnapshot = $null
    if ($script:current -eq '<custom>') {
        $active = Get-ActiveTokens
        $tokensSnapshot = [ordered]@{}
        foreach ($k in $TOKENS) { $tokensSnapshot[$k] = [string]$active[$k] }
    }
    return [pscustomobject]@{
        Palette = [string]$script:current
        Tokens  = $tokensSnapshot
        Targets = @($keys | Sort-Object -Unique)
    }
}

function Test-PresetStateDirty($baseline, $staged) {
    if (-not $baseline) { return $false }
    if ([string]$baseline.Palette -ne [string]$staged.Palette) { return $true }
    # Custom tokens participate whenever EITHER side carries a snapshot: a pack
    # baseline forked to Custom is a deviation even if every value happens to
    # match, and a snapshot baseline with one edited token must read modified
    # while the theme list still shows 'Custom'.
    if ($baseline.Tokens -or $staged.Tokens) {
        if (-not $baseline.Tokens -or -not $staged.Tokens) { return $true }
        # OrderedDictionary: enumerate .Keys explicitly -- PSObject.Properties
        # does not surface dict entries on every host/PS version this ships for.
        $a = @($baseline.Tokens.Keys | Sort-Object | ForEach-Object { "$_=$([string]$baseline.Tokens[$_])" })
        $b = @($staged.Tokens.Keys | Sort-Object | ForEach-Object { "$_=$([string]$staged.Tokens[$_])" })
        if ((@($a) -join "`n") -ne (@($b) -join "`n")) { return $true }
    }
    if (((@($baseline.Targets) | Sort-Object -Unique) -join ',') -ne ((@($staged.Targets) | Sort-Object -Unique) -join ',')) { return $true }
    return $false
}

function Get-UiPalette {
    # The live palette identity: a pack slug, or a complete custom snapshot when
    # the working palette is Custom (audit/6.md: a custom preset must capture the
    # canonical token set, not depend on themes/custom.json staying put).
    if ($script:current -eq '<custom>') {
        $active = Get-ActiveTokens
        # Same `$tokens/$TOKENS case-insensitive shadowing repair as
        # Resolve-PresetUiState (CORE-006).
        $tokensSnapshot = [ordered]@{}
        foreach ($k in $TOKENS) { $tokensSnapshot[$k] = $active[$k] }
        return [pscustomobject]@{ Type = 'snapshot'; Tokens = $tokensSnapshot }
    }
    return [pscustomobject]@{ Type = 'pack'; Slug = $script:current }
}

function Apply-PresetUiState($preset) {
    # Restore palette + checked targets. UI STATE ONLY: no Apply, no child process.
    # CORE-002: the resolution is explicit; only selectable targets are checked,
    # an unresolvable palette stays unresolved (never baselined as "current"),
    # and preset loading never opens a folder dialog.
    $res = Resolve-PresetUiState $preset
    if ($res.Palette.Resolved) {
        if ($res.Palette.Kind -eq 'pack') {
            $script:current = $res.Palette.Slug
            $lstThemes.SelectedItem = $script:packs[$res.Palette.Slug].label
        } else {
            # Snapshot: populate the Custom working palette and select Custom.
            $script:custom = $res.Palette.Tokens
            $script:current = '<custom>'
            $lstThemes.SelectedItem = 'Custom'
        }
    }
    $selectable = @($res.Selectable)
    $prevSuppress = $script:suppressPathPrompt
    $script:suppressPathPrompt = $true
    try {
        foreach ($list in $TARGET_LISTS) {
            for ($i = 0; $i -lt $list.Items.Count; $i++) {
                $key = (($list.Items[$i]) -split '\s+')[0]
                $list.SetItemChecked($i, ($selectable -contains $key))
            }
        }
    } finally { $script:suppressPathPrompt = $prevSuppress }
    Refresh-Swatches; Update-Info; Update-FbButtonsVisibility
    $script:activePresetId = $preset.id
    # A baseline exists only for a resolved palette; otherwise the current
    # palette was NOT established by this preset and capturing it would turn a
    # missing pack into a silent fallback (audit/7.md CORE-002).
    # CORE-006: the baseline IS a normalized staged-state snapshot (captured
    # through the same Get-PresetDirtyState the marker compares with), so a
    # snapshot preset carries its full token set and a later single-token edit
    # is detectable. Unresolved palette -> no baseline, unchanged from CORE-002.
    $script:presetBaseline = if ($res.Palette.Resolved) { Get-PresetDirtyState } else { $null }
    Update-PresetState
    $unavailText = @($res.Unavailable | ForEach-Object { "$($_.Key) ($($_.Reason))" })
    if (-not $res.Palette.Resolved) {
        Say-Log "preset '$($preset.name)': $($res.Palette.Reason) - palette left unchanged."
    }
    if ($unavailText.Count) {
        Say-Log "preset '$($preset.name)' loaded; unavailable on this machine (kept in the preset): $($unavailText -join ', ')"
    }
    if ($res.Palette.Resolved -and $unavailText.Count -eq 0) {
        Say-Log "preset '$($preset.name)' loaded into the UI - press Apply to install it."
    }
}

function Update-PresetState {
    # The modified marker: shows when the staged state differs from the loaded
    # preset. Purely informational; no mutation. CORE-006: the comparison is a
    # normalized staged-state snapshot (palette identity, custom tokens, sorted
    # targets) against the same-shaped baseline captured at load/Save As/Update,
    # and an ItemCheck caller forwards the PENDING NewValue because ItemCheck
    # fires before the check state commits.
    param([object]$PendingItem = $null, [int]$PendingIndex = -1, [string]$PendingValue = '')
    if (-not $script:activePresetId) { $lblPresetState.Text = ''; return }
    $owner = @($script:presets | Where-Object { $_.id -eq $script:activePresetId })[0]
    if (-not $owner) { $lblPresetState.Text = ''; return }
    $dirty = Test-PresetStateDirty $script:presetBaseline (Get-PresetDirtyState -PendingItem $PendingItem -PendingIndex $PendingIndex -PendingValue $PendingValue)
    $lblPresetState.Text = if ($dirty) { (T 'PresetModified') } else { '' }
    if ($script:presetsInvalid.Count) { $lblPresetState.Text += "  ($($script:presetsInvalid.Count) invalid preset file(s) ignored)" }
}

function Refresh-Presets {
    $res = Get-Presets $TOKENS
    $script:presets = @($res.Presets)
    $script:presetsInvalid = @($res.Invalid)
    $cmbPreset.Items.Clear()
    foreach ($p in $script:presets) { [void]$cmbPreset.Items.Add((New-PresetComboItem $p)) }
    if ($script:activePresetId) {
        # Identity is the preset id, so a rebuilt collection restores the SAME
        # preset even when another preset carries an equal display name.
        if (-not (Select-PresetComboItem $script:activePresetId)) {
            $script:activePresetId = $null
            $script:presetBaseline = $null
        }
    }
    foreach ($bad in $script:presetsInvalid) { Say-Log "ignoring invalid preset file: $bad" }
    Update-PresetState
}

function Save-CurrentAsPreset([string]$name, [switch]$Overwrite) {
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'a preset needs a name' }
    $id = New-PresetId $name
    if (-not $id) { throw "name '$name' cannot produce a safe preset id" }
    $ui = Get-UiPalette
    $preset = if ($ui.Type -eq 'pack') {
        New-PresetObject -Id $id -Name $name -PaletteType pack -PaletteSlug $ui.Slug -Targets (Get-CheckedTargetKeys)
    } else {
        New-PresetObject -Id $id -Name $name -PaletteType snapshot -Tokens $ui.Tokens -Targets (Get-CheckedTargetKeys)
    }
    Save-Preset $preset $TOKENS -Overwrite:$Overwrite | Out-Null
    Refresh-Presets
    # Save As/Update must leave the SAVED preset both visibly and internally
    # active; Refresh-Presets alone restored the PREVIOUS selection (audit/7.md
    # CORE-001), leaving the ComboBox on A while activePresetId named B.
    if (-not (Activate-Preset $id)) { throw "saved preset '$id' did not survive validation" }
    # CORE-006: the just-saved state IS the preset; recapture the baseline so
    # the modified marker does not report the saved state as a deviation.
    $script:presetBaseline = Get-PresetDirtyState
    Say-Log "preset saved: $name"
}

function Prompt-PresetName([string]$initial) {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = (T 'PresetSave')
    $dlg.Size = New-Object Drawing.Size(320, 150)
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'; $dlg.Font = $FONT
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = (T 'PresetNamePrompt'); $lbl.Location = '12,12'; $lbl.Size = '280,18'
    $tb = New-Object Windows.Forms.TextBox; $tb.Location = '12,34'; $tb.Size = '280,22'; $tb.Text = $initial
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'OK'; $ok.Location = '132,72'; $ok.Size = '76,26'; $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.Location = '216,72'; $cancel.Size = '76,26'; $cancel.DialogResult = 'Cancel'
    $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $cancel
    if ($dlg.ShowDialog($form) -eq 'OK') { return $tb.Text } else { return $null }
}

$btnPresetSave.Add_Click({
    try {
        $name = Prompt-PresetName ''
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $id = New-PresetId $name
        if (-not $id) { Say-Log "preset name '$name' cannot produce a safe id."; return }
        $exists = @($script:presets | Where-Object { $_.id -eq $id }).Count -gt 0
        if ($exists) {
            $ans = [Windows.Forms.MessageBox]::Show((T 'PresetOverwriteAsk'), (T 'PresetSave'), 'YesNo', 'Question')
            if ($ans -ne 'Yes') { return }
        }
        Save-CurrentAsPreset $name -Overwrite:$exists
    } catch { Say-Log "preset save FAILED: $($_.Exception.Message)" }
})
$btnPresetUpdate.Add_Click({
    try {
        # The visible selection is the ONLY target identity (CORE-001); a
        # disagreement between the ComboBox and internal state must fail
        # closed, never silently update a different preset.
        $p = Get-SelectedPreset
        if (-not $p) { Say-Log 'no preset selected to update.'; return }
        Save-CurrentAsPreset $p.name -Overwrite
    } catch { Say-Log "preset update FAILED: $($_.Exception.Message)" }
})
$btnPresetRename.Add_Click({
    try {
        $p = Get-SelectedPreset
        if (-not $p) { Say-Log 'no preset selected to rename.'; return }
        $name = Prompt-PresetName $p.name
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $newId = Rename-Preset $p.id $name $TOKENS
        Refresh-Presets
        if (-not (Activate-Preset $newId)) { throw "renamed preset '$newId' did not survive validation" }
        Say-Log "preset renamed to: $name"
    } catch { Say-Log "preset rename FAILED: $($_.Exception.Message)" }
})
$btnPresetDelete.Add_Click({
    try {
        $p = Get-SelectedPreset
        if (-not $p) { Say-Log 'no preset selected to delete.'; return }
        $name = $p.name
        $ans = [Windows.Forms.MessageBox]::Show((T 'PresetDeleteAsk'), (T 'PresetDelete'), 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        Remove-Preset $p.id
        $script:activePresetId = $null; $script:presetBaseline = $null
        Refresh-Presets
        $cmbPreset.SelectedIndex = -1
        Update-PresetState
        Say-Log "preset deleted: $name (no installed app was changed)"
    } catch { Say-Log "preset delete FAILED: $($_.Exception.Message)" }
})
$cmbPreset.Add_SelectedIndexChanged({
    try {
        $p = Get-SelectedPreset
        if (-not $p) { return }
        # Switching to a DIFFERENT preset is a load; re-selecting the active
        # one (Refresh-Presets set the item) must not re-load and clobber edits.
        if ($p.id -ne $script:activePresetId) { [void](Activate-Preset $p.id) }
    } catch { Say-Log "preset load FAILED: $($_.Exception.Message)" }
})
# Any palette or target change updates the modified marker. CORE-006: an
# ItemCheck event fires BEFORE the box commits the new check state, so the
# handler forwards the pending row + NewValue instead of letting the marker
# re-read the stale pre-click state.
$lstThemes.Add_SelectedIndexChanged({ Update-PresetState })
foreach ($list in $TARGET_LISTS) {
    $list.Add_ItemCheck({ param($sender, $e)
        Update-PresetState -PendingItem $sender -PendingIndex $e.Index -PendingValue $e.NewValue
    })
}

Refresh-Presets
# The startup palette also owns the first row. Selecting Golden Default while
# leaving Dark Golden above it looked like a stale default even though Apply used
# the right value.
foreach ($p in ($script:packs.Values | Sort-Object @{ Expression = { if ($_.slug -eq $script:current) { 0 } else { 1 } } }, { $_.order }, { $_.slug })) {
    [void]$lstThemes.Items.Add($p.label)
}
[void]$lstThemes.Items.Add('Custom')
$lstThemes.SelectedItem = $script:packs[$script:current].label
Refresh-Swatches
Update-Info
Skin-Self
$lstThemes.Add_SelectedIndexChanged({ Skin-Self })
Update-GuiStrings

if ($PATH_TARGETS.Count -gt 0) {
    $tip = New-Object Windows.Forms.ToolTip
    $tip.SetToolTip($clbMyApps, "Right-click a target to change its folder." + [Environment]::NewLine + "Asked once, then remembered in $($script:pathsFile).")
}

# A preview's temp PCM WAV is deleted on teardown; closing the window is the
# last teardown of the session, so sweep it there too. T-283: the private-font
# collections the terminal-fonts preview loaded are disposed on close too, so no
# undisposed GDI+ font resources survive the window.
$form.Add_FormClosed({ Stop-FbSoundPreview; Clear-TfPreviewResources })

# SRC-006:R006: the checkbox state was already initialized from the real task
# state BEFORE its event handler was attached (see the checkbox construction);
# assigning it here instead would re-introduce the open-the-GUI-registers bug.

[void]$form.ShowDialog()
