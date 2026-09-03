# Per-target Invoke-* implementations for install.ps1 (T-169 split). Functions here
# run in the calling script's scope, so they see install.ps1's data tables, parameters
# and helpers at call time. Dot-sourced by install.ps1 before the target tables are built.

# ─── Target-health contract (T-189) ──────────────────────────────────────────
# -Reapply must decide whether a recorded target needs work from TARGET health,
# not just the Wintage payload version: an application update (new app version, a
# moved install, a replaced archive) leaves payloadVersion unchanged while the
# theme is gone. These helpers probe the cheap signals and return one verdict.

# The console scrollback floor Wintage owns (T-193). A console profile whose
# screen-buffer height is at or below its window height has ZERO scrollback and
# therefore no scrollbar (the "terminal cuts my history" bug). conhost rewrites
# ScreenBufferSize back into the registry whenever the window is resized, so a
# once-applied 9001 floor can silently collapse back to the window height after
# the fact. Both the apply (Invoke-Conhost) and the Reapply health probe
# (Test-TargetNeedsReapply) share this single floor value, so a drifted buffer
# is detected and re-asserted instead of being left scrollbar-less.
$CONSOLE_SCROLLBACK_HEIGHT = 9001

# ─── The non-antialiased face (UI.md law 1) ──────────────────────────────────
# Law 1 asks for Verdana with NO antialiasing. Neither a Qt stylesheet nor a GDI
# settings value can switch smoothing off, so the only lever left is the FACE:
# Verdana_m1 is a copy of Verdana whose EBDT/EBLC tables carry pre-rendered 1bpp
# bitmap strikes at 3-30 ppem, and a renderer uses those in preference to
# smoothing the outline. The repo ships that .ttf for the browser theme.
#
# WINTAGE NAMES THAT FACE AND NEVER MANAGES IT. This is a deliberate limit, and
# it is the whole design note:
#
# A font FAMILY is resolved by (family, style). Register Regular+Bold+Italic and
# every consumer resolves correctly; deregister ONE member and every consumer
# asking for that family re-points at a surviving member. On a machine that
# routes `MS Shell Dlg 2` (the Windows dialog-font alias) at this family through
# HKLM\FontSubstitutes - a legitimate user configuration - removing Regular
# turns the ENTIRE desktop italic, including window titles the DWM has already
# cached. That is a machine-wide, hard-to-notice, hard-to-undo consequence of a
# theme installer's Revert, and it happened twice while this target was being
# built. No refcount fixes it: the blast radius is wrong, not the bookkeeping.
#
# So: the installer PROBES for the face and names whichever face it can actually
# guarantee. Installing the font stays a deliberate user action (double-click the
# .ttf -> Install), exactly like it already is for the browser theme.
$WINTAGE_FONT_SRC = Join-Path $root 'Verdana_m1.ttf'
$WINTAGE_FONT_FACE = 'Verdana_m1'
$WINTAGE_FONT_FALLBACK = 'Verdana'

# Does a NEW process on this machine resolve the face? GDI+ family enumeration is
# the same question the themed applications will ask, and it sees HKLM fonts,
# HKCU fonts and the per-user Fonts folder alike - which a single registry probe
# does not. The registry fallback exists only for hosts without System.Drawing.
function Test-WintageFontInstalled {
    if ($null -ne $script:WintageFontPresent) { return $script:WintageFontPresent }
    $found = $null
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $found = [bool](@([System.Drawing.FontFamily]::Families | Where-Object { $_.Name -eq $WINTAGE_FONT_FACE }).Count)
    } catch {
        foreach ($hive in @('HKCU:', 'HKLM:')) {
            $key = "$hive\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
            $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($props -and @($props.PSObject.Properties.Name | Where-Object { $_ -like "$WINTAGE_FONT_FACE*" }).Count) { $found = $true; break }
        }
        if ($null -eq $found) { $found = $false }
    }
    $script:WintageFontPresent = $found
    return $found
}

# The face a target should NAME. A stylesheet can carry a fallback chain
# ("Verdana_m1, Verdana"), but a single settings value (MPC-HC's OSDFont) cannot:
# naming an absent face there does not fall back to Verdana, it falls back to
# whatever GDI substitutes. So the answer is what the machine can honour today,
# and health computes it through this same function - one rule, no drift.
function Get-WintageFontFace {
    if (Test-WintageFontInstalled) { return $WINTAGE_FONT_FACE }
    return $WINTAGE_FONT_FALLBACK
}

# Said once per run by any target whose text quality depends on the face, when
# the face is absent. It states the consequence and the one-step fix rather than
# doing anything to the machine.
function Say-WintageFontAdvice([string]$label) {
    if (Test-WintageFontInstalled) { return }
    if ($script:WintageFontAdviceSaid) { return }
    $script:WintageFontAdviceSaid = $true
    Say "$label`: text will be ANTIALIASED - UI.md law 1 wants it sharp, and no stylesheet or setting can switch smoothing off." 'Yellow'
    if (Test-Path $WINTAGE_FONT_SRC) {
        Say "  Install the face once by hand and re-apply: right-click $WINTAGE_FONT_SRC -> Install (no admin needed)." 'Yellow'
    } else {
        Say "  The shipped face is missing from this checkout ($WINTAGE_FONT_SRC), so it cannot be named." 'Yellow'
    }
    Say '  Wintage deliberately does NOT install or remove fonts: a font family is resolved by (family, style),' 'DarkGray'
    Say '  so deregistering one member re-points every consumer - including MS Shell Dlg 2 where it is aliased -' 'DarkGray'
    Say '  at a surviving member, which turns the whole desktop italic. That is not a theme installer decision.' 'DarkGray'
}

# The currently-resolved install path for a target, or $null when it cannot be
# resolved/validated. Existence of the path/marker IS the theming evidence for
# the simple targets; the Electron targets get a full --status-json health read.
function Get-TargetCurrentPath([string]$key) {
    switch ($key) {
        'windows'   { if (Test-Path $WINDOWS_THEME_MARKER) { $WINDOWS_THEMES_DIR } else { $null }; break }
        'browsers'  { $marker = Join-Path $BrowserStageRoot '.wintage-palette'; if (Test-Path $marker) { $BrowserStageRoot } else { $null }; break }
        'mpchc'     { if (Test-Path $MPC_KEY) { $MPC_KEY } else { $null }; break }
        'terminal'  { $p = @(Get-WindowsTerminalSettingsPaths); if ($p.Count) { $p[0] } else { $null }; break }
        'conhost'   { if (Test-Path $CONHOST_KEY) { $CONHOST_KEY } else { $null }; break }
        'obs'       { if (Test-Path $OBS_CONFIG) { $OBS_CONFIG } else { $null }; break }
        'qbittorrent' { if (Test-Path $QBT_INI) { $QBT_INI } else { $null }; break }
        'discord'   { $css = Join-Path (Join-Path $env:APPDATA 'BetterDiscord\themes') 'wintage.theme.css'; if (Test-Path $css) { $css } else { $null }; break }
        # W2-004: Total Commander health re-resolves through the SAME resolver
        # Apply uses (RedirectSection included), but the manifest-recorded
        # effective INI wins when it still exists - an unattended Reapply must
        # never classify its own recorded redirected path as "moved".
        'totalcmd'  { $m = Read-ManifestQuiet; $ini = $null; if ($m -and $m.ContainsKey('totalcmd') -and $m['totalcmd'].path -and (Test-Path $m['totalcmd'].path)) { $ini = $m['totalcmd'].path } else { $ini = Resolve-TotalCmdIni 1 }; if ($ini -and (Test-Path $ini)) { $ini } else { $null }; break }
        'totalcmd2' { $m = Read-ManifestQuiet; $ini = $null; if ($m -and $m.ContainsKey('totalcmd2') -and $m['totalcmd2'].path -and (Test-Path $m['totalcmd2'].path)) { $ini = $m['totalcmd2'].path } else { $ini = Resolve-TotalCmdIni 2 }; if ($ini -and (Test-Path $ini)) { $ini } else { $null }; break }
        'obsidian'  { $null; break }   # handled specially by Test-TargetNeedsReapply (recorded SET, never a joined fake path)
        'saipenview' { $css = if ($SaipenviewPath) { Join-Path $SaipenviewPath 'saipenview\ui\static\style.css' } else { $null }; if ($css -and (Test-Path $css)) { $css } else { $null }; break }
        'smartvac'  { $py = if ($SmartVacPath) { Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py' } else { $null }; if ($py -and (Test-Path $py)) { $py } else { $null }; break }
        'wildrift'  { $py = if ($WildRiftPath) { Join-Path $WildRiftPath 'theme.py' } else { $null }; if ($py -and (Test-Path $py)) { $py } else { $null }; break }
        default {
            if ($ELECTRON.ContainsKey($key)) {
                $e = $ELECTRON[$key]
                if (Test-ElectronApp $e.Resources) { return $e.Resources }
            }
            $null
        }
    }
}

# Machine-readable Electron health read (install-electron.js --status-json). One
# source of state truth; PowerShell never re-infers Electron layout.
function Get-ElectronStatus([string]$key) {
    if (-not $ELECTRON.ContainsKey($key) -or -not $node) { return $null }
    $e = $ELECTRON[$key]
    $args = @((Join-Path $root 'tools/install-electron.js'), '--resources', $e.Resources, '--status-json')
    if ($e.InPlace) { $args += '--in-place' }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = (& node $args 2>$null | Out-String).Trim()
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0 -or -not $out) { return $null }
    try { return ($out | ConvertFrom-Json) } catch { return $null }
}

# FreeBuff patch args are built ONCE and used identically for dry-run, apply and
# health (T-190). A configured-but-missing sound file FAILS CLOSED - it is never
# silently dropped into "no custom sound". Format validation is the patch
# script's own preflight (isAudio).
function Get-FreeBuffPatchArgs {
    $soundPref = Join-Path $env:APPDATA 'Wintage\freebuff-sound.txt'
    if (-not (Test-Path $soundPref)) { return @() }
    $wav = (Read-Utf8 $soundPref).Trim()
    if (-not $wav) { return @() }
    if (-not (Test-Path $wav)) { throw "FreeBuff: the configured completion sound is missing: $wav - refusing to run the ad/sound patch without it." }
    return @('--sound', $wav)
}

# FreeBuff patch health (patch-freebuff-ads.js --status-json), optionally against
# the configured desired sound so a missing/wrong sound is detected.
function Get-FreeBuffHealth([switch]$DesiredSound) {
    if (-not $node) { return $null }
    $args = @((Join-Path $root 'desktop\patch-freebuff-ads.js'), '--status-json')
    if ($DesiredSound) {
        try {
            $fb = Get-FreeBuffPatchArgs
            if ($fb.Count) { $args += $fb }
        } catch {
            # A configured-but-missing sound means the desired state cannot be
            # satisfied - report it as unhealthy rather than throwing from a probe.
            return [pscustomobject]@{ renderer = 'unknown'; orchestrator = 'unknown'; sound = @{ requested = $true; state = 'missing-source'; healthy = $false }; healthy = $false }
        }
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = (& node $args 2>$null | Out-String).Trim()
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0 -and -not $out) { return $null }
    try { return ($out | ConvertFrom-Json) } catch { return $null }
}

# Byte-exact snapshot of an Electron target's owned files, used to restore the
# EXACT pre-operation state if the second (FreeBuff) layer fails (T-190).
function Get-ElectronExe([string]$key) {
    if (-not $ELECTRON.ContainsKey($key)) { return $null }
    $appDir = Split-Path $ELECTRON[$key].Resources -Parent
    if (-not (Test-Path $appDir)) { return $null }
    # Mirror install-electron.js resolveExe: the ONE exe that is not an installer.
    $exes = @(Get-ChildItem $appDir -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(uninstall|elevate|squirrel|update)' })
    if ($exes.Count -eq 1) { return $exes[0].FullName }
    return $null
}

function Save-ElectronStateSnapshot([string]$key, [string]$Operation = 'Apply') {
    $e = $ELECTRON[$key]
    $snap = Join-Path $env:TEMP ("wintage-elstate-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $snap -Force | Out-Null
    $r = $e.Resources
    # PERF-005: the snapshot is MUTATION-SET AWARE. A repaint of an already-themed
    # target changes only small sidecars (and possibly the exe/fuse backup) - it
    # never touches the huge archive. Copying the whole app/ tree (which in
    # relocation mode CONTAINS the moved archive) for a palette repaint pays
    # archive-sized I/O for bytes that cannot change. The helper's own
    # --status-json tells us which mutation class we are in: themed states =
    # repaint = lightweight snapshot (small files only); everything else keeps
    # the full pre-state.
    # CORE-001: a Revert of a themed-relocated target deletes the moved archive
    # during the operation; the snapshot MUST carry the archive too, otherwise
    # a failed child rollback leaves no recoverable copy on disk. The lightweight
    # path is now strictly opt-in via -Operation Repaint.
    $repaintOnly = $Operation -eq 'Repaint'
    if ($repaintOnly) {
        $appf = Join-Path $snap 'appfiles'
        New-Item -ItemType Directory -Path $appf -Force | Out-Null
        foreach ($f in @('package.json', 'shim.cjs', 'wintage.css', 'wintage-status.txt')) {
            $src = Join-Path $r "app\$f"
            if (Test-Path $src) { Copy-Item $src (Join-Path $appf $f) -Force }
        }
        foreach ($f in @('wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt', 'wintage-status.txt')) {
            $src = Join-Path $r $f
            if (Test-Path $src) { Copy-Item $src (Join-Path $snap $f) -Force }
        }
    } else {
        foreach ($f in @('app', 'app.asar', 'app.asar.unpacked', 'wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt', 'wintage-status.txt')) {
            $src = Join-Path $r $f
            if (Test-Path $src) { Copy-Item $src (Join-Path $snap $f) -Recurse -Force }
        }
    }
    # T-191 P0#3: the app EXE lives OUTSIDE resources/ (the app root), and the
    # fuse values live inside it. The Electron layer can flip the runAsNode fuse
    # during apply, so the snapshot must carry the exe byte-exactly AND the fuse
    # backup file the defuse writes, otherwise a failed FreeBuff second layer
    # would leave a half-defused exe behind.
    $exe = Get-ElectronExe $key
    if ($exe) {
        Copy-Item $exe (Join-Path $snap ([IO.Path]::GetFileName($exe))) -Force
        $fuseBak = $exe + '.wintage-fuse.bak'
        if (Test-Path $fuseBak) { Copy-Item $fuseBak (Join-Path $snap ([IO.Path]::GetFileName($fuseBak))) -Force }
    }
    return $snap
}

function Restore-ElectronStateSnapshot([string]$key, [string]$snap) {
    $e = $ELECTRON[$key]
    $r = $e.Resources
    # PERF-005: detect the repaint-mode snapshot (small sidecars only). Those
    # snapshots never carry the app/ tree, so the structural restore loop below
    # must NOT treat their absence as "delete the live dir": a repaint cannot
    # change the archive layout, and wiping resources\app would destroy the
    # relocated archive plus every sidecar.
    $appf = Join-Path $snap 'appfiles'
    $repaintOnly = Test-Path $appf
    # T-191 P0#12: copy-over FIRST, delete leftovers AFTER. A restore that removes
    # the live file and then fails to copy leaves the app broken; overwriting in
    # place never does. Directories cannot be overwritten in place (Copy-Item would
    # nest them), so they are swapped through a temp sibling via Restore-DirPreState
    # - the live dir is only touched once the restored copy is fully materialised.
    foreach ($f in @('app', 'app.asar', 'app.asar.unpacked', 'wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt', 'wintage-status.txt')) {
        $src = Join-Path $snap $f
        $dst = Join-Path $r $f
        if (Test-Path $src) {
            if ((Get-Item $src -ErrorAction SilentlyContinue).PSIsContainer) {
                # W2-001: Restore-DirPreState requires a STRUCTURED snapshot
                # (Existed + SnapshotPath). A raw path collapses both branches
                # and was historically deleting the relocated archive directory
                # during a failed rollback. Pass the structured contract here.
                Restore-DirPreState $dst @{ Existed = $true; SnapshotPath = $src }
            } else {
                Copy-Item $src $dst -Force
            }
        } elseif (-not $repaintOnly -and (Test-Path $dst)) {
            # Only a full snapshot may prove that a structural artifact (the app
            # dir or an archive) should be removed as a leftover of THIS operation.
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    # PERF-005: restore the repaint-mode small files back into an EXISTING app/
    # (the lightweight snapshot never removes the app dir - it was not touched).
    if ($repaintOnly) {
        $appDir = Join-Path $r 'app'
        if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }
        foreach ($f in (Get-ChildItem $appf -File)) {
            Copy-Item $f.FullName (Join-Path $appDir $f.Name) -Force
        }
    }
    $exe = Get-ElectronExe $key
    if ($exe) {
        $snapExe = Join-Path $snap ([IO.Path]::GetFileName($exe))
        $fuseBak = $exe + '.wintage-fuse.bak'
        $snapFuse = Join-Path $snap ([IO.Path]::GetFileName($fuseBak))
        if (Test-Path $snapExe) { Copy-Item $snapExe $exe -Force }
        elseif (Test-Path $exe) { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
        # A snapshot WITHOUT a fuse bak means the exe was never defused before the
        # operation: the stale bak from the failed transaction is removed only
        # AFTER the exe itself is back, so a later --revert cannot restore a
        # defused exe over the pristine one.
        if (Test-Path $snapFuse) { Copy-Item $snapFuse $fuseBak -Force }
        elseif (Test-Path $fuseBak) { Remove-Item $fuseBak -Force -ErrorAction SilentlyContinue }
    }
}

# W2-005: Total Commander health compares EVERY Wintage-owned key in BOTH
# colour sections against the values the recorded palette would write - the
# same expectations Apply generates. Returns $null (healthy) or a reason string.
function Test-TotalCmdThemed([string]$ini, $palTokens) {
    if (-not $ini -or -not (Test-Path $ini)) { return 'totalcmd ini missing' }
    if (-not $palTokens) { return 'recorded palette tokens unavailable' }
    $t = $palTokens
    $expected = @{
        BackColor = Convert-HexToBgr $t.background
        BackColor2 = Convert-HexToBgr $t.background
        ForeColor = Convert-HexToBgr $t.textPrimary
        MarkColor = Convert-HexToBgr $t.danger
        CursorColor = Convert-HexToBgr $t.selection
        CursorText = Convert-HexToBgr $t.borderHighlight
        ActiveTitle = Convert-HexToBgr $t.surface
        ActiveTitleText = Convert-HexToBgr $t.textPrimary
        InactiveTitle = Convert-HexToBgr $t.backgroundSoft
        InactiveTitleText = Convert-HexToBgr $t.textMuted
    }
    $recentFg = Convert-HexToBgr $t.link
    $lines = (Read-Utf8 $ini) -split '\r?\n'
    $bad = @()
    foreach ($section in @('Colors', 'ColorsDark')) {
        foreach ($key in $expected.Keys) {
            $v = Get-IniKey $lines $section $key
            if ($null -eq $v) { $bad += "$section.$key missing" }
            elseif ([string]$v -ne [string]$expected[$key]) { $bad += "$section.$key=$v (want $($expected[$key]))" }
        }
    }
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^ColorFilter(\d+)Color(Dark)?=')
        if ($m.Success) {
            $v = $line.Substring($m.Index + $m.Length)
            if ([string]$v -ne [string]$recentFg) { $bad += "ColorFilter$($m.Groups[1].Value)Color$($m.Groups[2].Value)=$v (want $recentFg)" }
        }
    }
    if ($bad.Count) { return 'totalcmd owned colours drifted: ' + (($bad | Select-Object -First 4) -join '; ') }
    return $null
}

# needsReapply = ANY of: payload outdated/malformed, resolved path moved, app
# version changed, marker/theme state missing, target unresolved.
function Test-TargetNeedsReapply([string]$key, $data, [string]$currentVer) {
    $reasons = @()
    if (-not (Test-PayloadUpToDate $data.payloadVersion $currentVer)) {
        $reasons += "payload v$($data.payloadVersion) -> repo v$currentVer"
    }
    if ($ELECTRON.ContainsKey($key)) {
        $st = Get-ElectronStatus $key
        if (-not $st) {
            $reasons += 'electron status unavailable (node failed or the app cannot be resolved)'
            return [pscustomobject]@{ Needs = $true; Reasons = ($reasons -join '; '); Path = $null }
        }
        # CORE-008: Reapply consumes the RUNTIME health verdict, not a
        # re-inference of state/version. `healthy` already bakes in the required
        # sidecar set; missingSidecars names the gaps explicitly.
        if ($st.PSObject.Properties['healthy'] -and -not $st.healthy) {
            if ($st.missingSidecars -and @($st.missingSidecars).Count) { $reasons += "missing runtime sidecar(s): $(@($st.missingSidecars) -join ', ')" }
            else { $reasons += ("electron health: $($st.detail)") }
        }
        elseif ($st.state -in @('updated-relocated', 'updated-inplace')) { $reasons += "electron state $($st.state) (app updated, theme lost)" }
        elseif ($st.state -eq 'stock') { $reasons += 'electron state stock (not themed)' }
        elseif ($st.state -eq 'ambiguous') { $reasons += "electron state ambiguous: $($st.detail)" }
        elseif ($data.appVersion -and $st.version -and $data.appVersion -ne $st.version) { $reasons += "app version $($data.appVersion) -> $($st.version)" }
        if ($st.fuses) {
            if ($st.fuses.unverifiable) { $reasons += ("electron fuse state unverifiable: $($st.fuses.reason)") }
            elseif ($st.fuses.fusedShut) { $reasons += 'electron fuses are blocking the shim (fused shut)' }
        }
        if ($data.palette -and $st.palette -and $st.palette -ne $data.palette) { $reasons += "palette $($data.palette) -> $($st.palette)" }
        if ($data.path -and $st.resources -and ([IO.Path]::GetFullPath($data.path) -ne [IO.Path]::GetFullPath($st.resources))) {
            $reasons += "resolved path moved ($($data.path) -> $($st.resources))"
        }
        if ($key -eq 'freebuff') {
            # FreeBuff health = Electron health AND patch health AND desired-sound
            # state (T-190). The patch layer is probed directly, never inferred.
            $fh = Get-FreeBuffHealth -DesiredSound
            if (-not $fh) { $reasons += 'freebuff patch health unavailable (node failed or the helper cannot run)' }
            else {
                if ($fh.renderer -and $fh.renderer -ne 'patched') { $reasons += "freebuff renderer $($fh.renderer)" }
                if ($fh.orchestrator -and $fh.orchestrator -ne 'patched') { $reasons += "freebuff orchestrator $($fh.orchestrator)" }
                if ($fh.sound -and $fh.sound.requested -and -not $fh.sound.healthy) { $reasons += "freebuff sound state $($fh.sound.state)" }
            }
        }
        return [pscustomobject]@{ Needs = ($reasons.Count -gt 0); Reasons = ($reasons -join '; '); Path = $st.resources }
    }
    $currentPath = Get-TargetCurrentPath $key
    # Multi-item targets: compare the RECORDED owned set against current discovery
    # (T-190). A recorded item that vanished or moved is unhealthy; a newly
    # discovered item is NOT (it belongs to the next Apply).
    if ($key -eq 'obsidian' -or $key -eq 'terminal') {
        $recorded = @(Get-ManifestItems $data)
        if (-not $recorded.Count) {
            $reasons += "$key manifest carries no recorded item set"
        } else {
            $current = if ($key -eq 'obsidian') { @(Get-ObsidianVaults | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }) }
                      else { @(Get-WindowsTerminalSettingsPaths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }) }
            foreach ($r in $recorded) {
                $canon = [IO.Path]::GetFullPath($r).TrimEnd('\')
                if ($canon -notin $current) { $reasons += "recorded $key item gone or moved: $canon" }
            }
            # T-191 P0#8: a passing SET is not enough - probe the EFFECTIVE owned
            # state of every item (marker presence AND the recorded palette value).
            # A marker that was deleted or rewritten to another palette is just as
            # unhealthy as a vanished vault, and must trigger Reapply.
            if ($key -eq 'terminal') {
                # CORE-011: probe the EFFECTIVE marker/palette state only for the
                # RECORDED item set. The set comparison above already proved every
                # recorded item still exists. A newly discovered unowned settings
                # file (no marker, never Apply'd) must NOT make an existing
                # healthy install look unhealthy -- it belongs to the next user
                # Apply, not to an automatic Reapply adoption.
                $paths = @($recorded)
                $markers = @($paths | ForEach-Object { $_ + '.wintage-palette' } | Where-Object { Test-Path $_ })
                if ($markers.Count -lt $paths.Count) { $reasons += 'terminal theme marker(s) missing' }
                else {
                    foreach ($marker in $markers) { $mv = (Read-Utf8 $marker).Trim(); if ($mv -ne $data.palette) { $reasons += "terminal marker palette mismatch ($mv)" } }
                    # CORE-004 (SRC-002): marker alone is not enough - the
                    # effective owned fields (colorScheme, font, AA,
                    # historySize, Wintage scheme) may have been deleted or
                    # drifted by the user. Validate the actual settings.json
                    # owned fields against the Wintage floor/expected values.
                    foreach ($settingsPath in $paths) {
                        if (-not (Test-Path $settingsPath)) {
                            $reasons += "terminal settings.json missing: $settingsPath"
                            continue
                        }
                        try {
                            $term = Read-Utf8 $settingsPath | ConvertFrom-Json
                            $def = $term.profiles.defaults
                            $cs = if ($def.colorScheme) { $def.colorScheme.ToString() } else { $null }
                            $aa = if ($def.antialiasingMode) { $def.antialiasingMode.ToString() } else { $null }
                            $hs = if ($null -ne $def.historySize) { [int]$def.historySize } else { $null }
                            $fntFace = if ($def.font -and $def.font.face) { $def.font.face.ToString() } else { $null }
                            # colorScheme must be 'Wintage'
                            if ($cs -ne 'Wintage') { $reasons += "terminal colorScheme is '$cs' not 'Wintage': $settingsPath" }
                            # antialiasingMode must be 'aliased'
                            if ($aa -ne 'aliased') { $reasons += "terminal antialiasingMode is '$aa' not 'aliased': $settingsPath" }
                            # historySize must be >= TERMINAL_SCROLLBACK floor
                            if ($null -eq $hs -or $hs -lt $CONSOLE_SCROLLBACK_HEIGHT) { $reasons += "terminal historySize ($hs) below $CONSOLE_SCROLLBACK_HEIGHT floor: $settingsPath" }
                            # font face must be set to a non-default value
                            if ([string]::IsNullOrEmpty($fntFace)) { $reasons += "terminal font face missing: $settingsPath" }
                            # Wintage color scheme must exist in schemes[]
                            $hasWintageScheme = $false
                            if ($term.schemes) {
                                foreach ($s in $term.schemes) {
                                    if ($s.name -and $s.name.ToString() -eq 'Wintage') { $hasWintageScheme = $true; break }
                                }
                            }
                            if (-not $hasWintageScheme) { $reasons += "terminal Wintage color scheme missing from schemes[]: $settingsPath" }
                        } catch { $reasons += "terminal settings.json unparseable: $settingsPath ($($_.Exception.Message))" }
                    }
                }
            } else {
                # CORE-003: health tests the EXACT expected owned theme per vault,
                # never a 'Wintage *' prefix wildcard - a user lookalike folder
                # must not make a missing owned theme look healthy.
                $builtRoot = Join-Path $out 'obsidian'
                $activeName = $null
                $activeManifest = Join-Path $builtRoot "$($data.palette)/manifest.json"
                if (Test-Path $activeManifest) {
                    try { $activeName = (Read-Utf8 $activeManifest | ConvertFrom-Json).name } catch { }
                }
                $expectedNames = @()
                if (Test-Path $builtRoot) {
                    $expectedNames = @(Get-ChildItem $builtRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        try { (Read-Utf8 (Join-Path $_.FullName 'manifest.json') | ConvertFrom-Json).name } catch { $null }
                    } | Where-Object { $_ })
                }
                foreach ($r in $recorded) {
                    $themesDir = Join-Path $r '.obsidian/themes'
                    foreach ($expected in $expectedNames) {
                        if (-not (Test-Path (Join-Path $themesDir $expected))) {
                            $reasons += "obsidian vault missing owned theme '$expected': $r"
                        }
                    }
                    $appearance = Join-Path $r '.obsidian/appearance.json'
                    if (Test-Path $appearance) {
                        $css = (Read-Utf8 $appearance | ConvertFrom-Json).cssTheme
                        if ($activeName -and $css -ne $activeName) { $reasons += "obsidian vault not set active ('$css' != '$activeName'): $r" }
                    } else { $reasons += "obsidian appearance.json missing: $r" }
                }
            }
        }
        return [pscustomobject]@{ Needs = ($reasons.Count -gt 0); Reasons = ($reasons -join '; '); Path = ($recorded -join '; ') }
    }
    if ($data.path) {
        if (-not $currentPath) { $reasons += 'recorded path is gone (target cannot be resolved)' }
        # Registry-key targets (conhost, mpchc) record an HKCU:\... value as their
        # "path". A GetFullPath comparison is meaningless there AND throws
        # NotSupportedException under Windows PowerShell 5.1 (.NET Framework
        # cannot resolve a registry-provider root), which crashed every conhost or
        # mpchc Reapply before the marker switch even ran. Their health is decided
        # by the marker checks below, never by a filesystem path comparison.
        elseif ($data.path -notmatch '^(HKCU|HKLM|Registry)::?\\' -and [IO.Path]::GetFullPath($data.path) -ne [IO.Path]::GetFullPath($currentPath)) { $reasons += "resolved path moved ($($data.path) -> $currentPath)" }
    } elseif (-not $currentPath) { $reasons += 'target cannot be resolved' }
    if ($currentPath) {
        # The palette file for the RECORDED palette - its token values are the
        # desired owned state (T-190). Absent palette file is itself unhealthy.
        $palFile = Join-Path $root "themes\$($data.palette).json"
        $palTokens = if (Test-Path $palFile) { Get-PaletteTokens $palFile } else { $null }
        switch ($key) {
            # W2-005: Windows health is the managed theme FILE plus the marker -
            # the marker alone survives a deleted Wintage-<hash>.theme or a user
            # switching CurrentTheme away, and both are real theme loss.
            'windows'   { if (Test-Path $WINDOWS_THEME_MARKER) { $m = (Read-Utf8 $WINDOWS_THEME_MARKER).Trim(); if ($m -ne $data.palette) { $reasons += "windows marker palette mismatch ($m)" } } else { $reasons += 'windows theme marker missing' }
                $activePathMarker = Join-Path $WINDOWS_THEMES_DIR '.wintage-active-theme-path'
                $managed = if (Test-Path $activePathMarker) { (Read-Utf8 $activePathMarker).Trim() } else { $null }
                if ($managed -and -not (Test-Path $managed)) { $reasons += 'managed windows theme file deleted' }
                $currentTheme = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
                if ($managed -and $currentTheme -and ([IO.Path]::GetFullPath($currentTheme) -ne [IO.Path]::GetFullPath($managed))) { $reasons += 'current windows theme is not the Wintage-managed theme' }
            }
            'obs'       { $obsTheme = Join-Path $OBS_CONFIG 'themes\Wintage.ovt'; $obsMarker = Join-Path $OBS_CONFIG '.wintage-obs-palette'; if (-not (Test-Path $obsTheme) -or -not (Test-Path $obsMarker)) { $reasons += 'obs theme/marker missing' } else { $mv = (Read-Utf8 $obsMarker).Trim(); if ($mv -ne $data.palette) { $reasons += "obs marker palette mismatch ($mv)" } } }
            # W2-005 discipline: health probes the COMPLETE owned set - both theme
            # files, the marker, AND both INI keys. qBittorrent rewrites its whole
            # INI on exit, so a user toggling "Use custom UI theme" off (or picking
            # another theme file) silently un-themes the app while every file is
            # still on disk; the INI checks are what catch that.
            'qbittorrent' {
                $qCfg = Join-Path $QBT_THEME_DIR 'config.json'
                $qQss = Join-Path $QBT_THEME_DIR 'stylesheet.qss'
                if (-not (Test-Path $qCfg)) { $reasons += 'qbittorrent config.json missing' }
                if (-not (Test-Path $qQss)) { $reasons += 'qbittorrent stylesheet.qss missing' }
                if (-not (Test-Path $QBT_MARKER)) { $reasons += 'qbittorrent theme marker missing' }
                else { $mv = (Read-Utf8 $QBT_MARKER).Trim(); if ($mv -ne $data.palette) { $reasons += "qbittorrent marker palette mismatch ($mv)" } }
                if ($palTokens -and (Test-Path $qCfg) -and -not ((Read-Utf8 $qCfg) -match [regex]::Escape($palTokens.background))) {
                    $reasons += 'qbittorrent config.json does not carry the recorded palette'
                }
                $qLines = (Read-Utf8 $currentPath) -split '\r?\n'
                $qUse = Get-IniKey $qLines 'Preferences' 'General\UseCustomUITheme'
                if ("$qUse".Trim() -ne 'true') { $reasons += "qbittorrent UseCustomUITheme is '$qUse' not 'true'" }
                $qPath = Get-IniKey $qLines 'Preferences' 'General\CustomUIThemePath'
                if (-not (Test-QbtThemePath $qPath $qCfg)) { $reasons += "qbittorrent CustomUIThemePath points elsewhere ($qPath)" }
            }
            'conhost'   { $pal = (Get-ItemProperty $CONHOST_KEY -Name WintagePalette -ErrorAction SilentlyContinue).WintagePalette; if (-not $pal) { $reasons += 'conhost WintagePalette marker missing' } elseif ($pal -ne $data.palette) { $reasons += "conhost marker palette mismatch ($pal)" }
                # A console profile whose screen-buffer height fell at/below its
                # window height has ZERO scrollback and no scrollbar. conhost
                # rewrites ScreenBufferSize into the registry on window resize,
                # so a Wintage-applied 9001 floor can silently collapse after the
                # fact (marker stays intact, so the palette check above misses it).
                # Flag any owned profile that drifted below the floor so Reapply
                # re-asserts it instead of leaving the console scrollbar-less.
                $collapsed = @(Get-ConhostKeys | Where-Object {
                    $sb = (Get-ItemProperty -LiteralPath $_.PSPath -Name ScreenBufferSize -ErrorAction SilentlyContinue).ScreenBufferSize
                    if ($null -eq $sb) { return $false }
                    (([uint32]$sb -shr 16) -band 0xFFFF) -lt $CONSOLE_SCROLLBACK_HEIGHT
                })
                if ($collapsed.Count) { $reasons += "conhost scrollback collapsed (buffer height < $CONSOLE_SCROLLBACK_HEIGHT, no scrollbar): $($collapsed.PSChildName -join ', ')" }
            }
            'browsers'  { $marker = Join-Path $BrowserStageRoot '.wintage-palette'; if (-not (Test-Path $marker)) { $reasons += 'browser stage marker missing' } else { $mv = (Read-Utf8 $marker).Trim(); if ($mv -ne $data.palette) { $reasons += "browser marker palette mismatch ($mv)" } } }
            'totalcmd'  { $tc = Test-TotalCmdThemed $currentPath $palTokens; if ($tc -is [string]) { $reasons += $tc } }
            'totalcmd2' { $tc = Test-TotalCmdThemed $currentPath $palTokens; if ($tc -is [string]) { $reasons += $tc } }
            # W2-005: health compares EVERY owned registry value (the exact set
            # Invoke-MpcHc owns), not just one cheap marker.
            'mpchc'     { $props = Get-ItemProperty $MPC_KEY -ErrorAction SilentlyContinue; if ($props) { if ($props.MPCTheme -ne 1) { $reasons += 'mpc MPCTheme not themed' }; if ($props.ModernThemeMode -ne 2) { $reasons += 'mpc ModernThemeMode not themed' }; $wantFace = Get-WintageFontFace; if ($props.OSDFont -ne $wantFace) { $reasons += "mpc OSD font is '$($props.OSDFont)' not '$wantFace'" }; if ($props.OSDSize -ne 16) { $reasons += 'mpc OSD size not themed' }; if ($props.OSDTransparency -ne 0) { $reasons += 'mpc OSD transparency not themed' }; if ($props.OSDBorder -ne 1) { $reasons += 'mpc OSD border not themed' }; if ($props.TitleBarTextStyle -ne 1) { $reasons += 'mpc title bar text style not themed' } } else { $reasons += 'mpc settings key unreadable' } }
            'discord'   { $bdCss = Join-Path (Join-Path $env:APPDATA 'BetterDiscord\themes') 'wintage.theme.css'; if (-not (Test-Path $bdCss)) { $reasons += 'betterdiscord css missing' } elseif ($palTokens -and -not ((Read-Utf8 $bdCss) -match [regex]::Escape($palTokens.background))) { $reasons += 'betterdiscord css does not match the recorded palette' } }
            # CORE-012: $currentPath IS the resolved CSS file (see
            # Get-TargetCurrentPath); the old $cssFile variable is not defined in
            # this scope and the Read-Utf8 of a null path THREW instead of
            # returning an unhealthy verdict. An unreadable CSS file is an
            # explicit health reason, never an uncaught exception.
            'saipenview' { $svBak = if ($currentPath) { $currentPath + '.bak' } else { $null }; if (-not $svBak -or -not (Test-Path $svBak)) { $reasons += 'saipenview backup missing (never themed)' } elseif ($palTokens) { try { if (-not ((Read-Utf8 $currentPath) -match [regex]::Escape($palTokens.background))) { $reasons += 'saipenview css does not carry the recorded palette' } } catch { $reasons += 'saipenview css unreadable: ' + $_.Exception.Message } } }
            'smartvac'  { $py = if ($SmartVacPath) { Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py' } else { $null }; if (-not $py -or -not (Test-Path $py)) { $reasons += 'smartvac file missing' } elseif (-not (Test-Path ($py + '.bak'))) { $reasons += 'smartvac backup missing (never themed)' } elseif ($palTokens -and -not ((Read-Utf8 $py) -match [regex]::Escape($palTokens.background))) { $reasons += 'smartvac owned tokens do not match the recorded palette' } }
            'wildrift'  { $py = if ($WildRiftPath) { Join-Path $WildRiftPath 'theme.py' } else { $null }; if (-not $py -or -not (Test-Path $py)) { $reasons += 'wildrift file missing' } elseif (-not (Test-Path ($py + '.bak'))) { $reasons += 'wildrift backup missing (never themed)' } elseif ($palTokens -and -not ((Read-Utf8 $py) -match [regex]::Escape($palTokens.background))) { $reasons += 'wildrift owned tokens do not match the recorded palette' } }
        }
    }
    [pscustomobject]@{ Needs = ($reasons.Count -gt 0); Reasons = ($reasons -join '; '); Path = $currentPath }
}

# Strict-target semantics (T-189): -Target all treats genuine absence as SKIP;
# an explicitly-requested or manifest-recorded target that cannot be fulfilled is
# a FAIL. Set by install.ps1 from the dispatch context; handlers consult it.
function Assert-TargetResolvable([string]$label, [bool]$present) {
    if ($present) { return }
    if ($script:StrictTarget) { throw "$label : expected to be present but cannot be resolved/validated - refusing to continue (strict target)." }
    Say "$label : not installed on this machine - skipped." 'DarkYellow'
}

# ─── Owned-field INI helpers (T-189) ─────────────────────────────────────────
# Total Commander revert restores ONLY the keys Wintage owns, merged into the
# CURRENT ini, so unrelated user edits made after Apply survive.
$script:TC_OWNED_KEYS = @('BackColor','BackColor2','ForeColor','MarkColor','CursorColor','CursorText','ActiveTitle','ActiveTitleText','InactiveTitle','InactiveTitleText')
$script:TC_OWNED_SECTIONS = @('Colors','ColorsDark')

function Get-IniSectionRange([string[]]$lines, [string]$section) {
    $start = -1; $end = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\[$([regex]::Escape($section))\]$") { $start = $i; continue }
        if ($start -ge 0 -and $lines[$i] -match '^\[') { $end = $i; break }
    }
    [pscustomobject]@{ Start = $start; End = $end }
}

function Set-IniKey([string[]]$lines, [string]$section, [string]$key, [string]$value) {
    $r = Get-IniSectionRange $lines $section
    $new = @()
    if ($r.Start -lt 0) {
        $new = $lines
        if ($new.Count -and $new[-1] -ne '') { $new += '' }
        $new += "[$section]"
        $new += "$key=$value"
        return $new
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $r.Start) {
            $new += $lines[$i]
            $found = $false
            for ($j = $r.Start + 1; $j -lt $r.End; $j++) {
                if ($lines[$j] -match "^$([regex]::Escape($key))\s*=") { $new += "$key=$value"; $found = $true }
                else { $new += $lines[$j] }
            }
            if (-not $found) { $new += "$key=$value" }
            $i = $r.End - 1
        } else { $new += $lines[$i] }
    }
    return $new
}

function Remove-IniKey([string[]]$lines, [string]$section, [string]$key) {
    $r = Get-IniSectionRange $lines $section
    if ($r.Start -lt 0) { return $lines }
    $new = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ge $r.Start -and $i -lt $r.End -and $lines[$i] -match "^$([regex]::Escape($key))\s*=") { continue }
        $new += $lines[$i]
    }
    return $new
}

function Get-IniKey([string[]]$lines, [string]$section, [string]$key) {
    $r = Get-IniSectionRange $lines $section
    if ($r.Start -lt 0) { return $null }
    for ($j = $r.Start + 1; $j -lt $r.End; $j++) {
        if ($lines[$j] -match "^$([regex]::Escape($key))\s*=(.*)$") { return $matches[1] }
    }
    return $null
}

# Capture a JSON snapshot of the Wintage-owned TotalCmd keys (with their original
# values, or null when absent) so Revert can merge exactly those into the current
# ini. Legacy whole-file .bak files are parsed by Revert and their owned keys
# extracted the same way.
function Save-TotalCmdSnapshot([string[]]$lines, [int[]]$recentFilterIds) {
    $owned = @{}
    foreach ($s in $script:TC_OWNED_SECTIONS) {
        $owned[$s] = @{}
        foreach ($k in $script:TC_OWNED_KEYS) {
            $v = Get-IniKey $lines $s $k
            $owned[$s][$k] = if ($null -ne $v) { $v } else { $null }
        }
    }
    foreach ($s in $script:TC_OWNED_SECTIONS) {
        foreach ($id in $recentFilterIds) {
            foreach ($suffix in @('Color', 'ColorDark')) {
                $ck = "ColorFilter$($id)$suffix"
                $v = Get-IniKey $lines $s $ck
                $owned[$s][$ck] = if ($null -ne $v) { $v } else { $null }
            }
        }
    }
    @{ owned = $owned } | ConvertTo-Json -Depth 6
}

function Restore-TotalCmdOwned([string]$ini, [string]$iniBak, [switch]$Keep) {
    $snapshot = $null
    if (Test-Path $iniBak) {
        try {
            $parsed = Read-Utf8 $iniBak | ConvertFrom-Json
            if ($parsed.owned) { $snapshot = $parsed }
        } catch {
            # Legacy whole-file backup: parse as INI and extract the owned keys.
            $legacy = (Read-Utf8 $iniBak) -split '\r?\n'
            $owned = @{}
            foreach ($s in $script:TC_OWNED_SECTIONS) {
                $owned[$s] = @{}
                foreach ($k in $script:TC_OWNED_KEYS) {
                    $v = Get-IniKey $legacy $s $k
                    $owned[$s][$k] = if ($null -ne $v) { $v } else { $null }
                }
            }
            $snapshot = [pscustomobject]@{ owned = $owned }
        }
    }
    if (-not $snapshot) { return $false }
    $current = (Read-Utf8 $ini) -split '\r?\n'
    # The split yields a trailing empty element for a file ending in EOL; trimming
    # it keeps the write from appending an extra blank line (byte-exact revert).
    while ($current.Count -and $current[-1] -eq '') { $current = $current[0..($current.Count - 2)] }
    foreach ($s in $script:TC_OWNED_SECTIONS) {
        if (-not $snapshot.owned.$s) { continue }
        foreach ($prop in $snapshot.owned.$s.PSObject.Properties) {
            $val = $prop.Value
            if ($null -ne $val -and "$val" -ne '') {
                if (Get-IniKey $current $s $prop.Name) { $current = Set-IniKey $current $s $prop.Name "$val" }
                else { $current = Set-IniKey $current $s $prop.Name "$val" }
            } else {
                $current = Remove-IniKey $current $s $prop.Name
            }
        }
    }
    Write-Utf8BomLines $ini $current
    # T-192 P2/C: the backup is consumed only when no manifest transition is
    # still pending; a failed Remove-ManifestEntry must keep it for a retry.
    if (-not $Keep) { Remove-Item $iniBak -Force }
    return $true
}

# ─── Source-tree backup provenance (T-189) ───────────────────────────────────
# SmartVac/WildRift keep a pristine backup of the file as it was when Wintage
# first touched it. If the UPSTREAM source changes after that (a new version of
# the app's own file, unrelated to Wintage), the rollback base must follow: the
# obsolete backup can never be the authority again, and repaint must not rebuild
# a new live file from it. The re-base compares the LIVE file against the backup
# with the Wintage-owned regions normalised out - a difference means upstream
# changed, so the backup is refreshed from the current pre-patch live file.
function Test-SourceProvenanceChanged([string]$liveText, [string]$backupText, [string]$kind) {
    $liveNorm = if ($kind -eq 'smartvac') { [regex]::Replace($liveText, '(?m)^WIN95_\w+\s*=\s*''[^'']*''', 'WIN95_X =') }
                else { [regex]::Replace($liveText, '(?s)TOKENS\s*=\s*\{.*?\}', 'TOKENS = {}') }
    $backupNorm = if ($kind -eq 'smartvac') { [regex]::Replace($backupText, '(?m)^WIN95_\w+\s*=\s*''[^'']*''', 'WIN95_X =') }
                  else { [regex]::Replace($backupText, '(?s)TOKENS\s*=\s*\{.*?\}', 'TOKENS = {}') }
    return ($liveNorm -ne $backupNorm)
}

function Sync-SourceBackup([string]$liveFile, [string]$bakFile, [string]$kind, [string]$label) {
    if (-not (Test-Path $bakFile)) {
        Copy-Item $liveFile $bakFile -Force
        # W2-001: the backup is now the revert source - stamp it with the epoch.
        Write-RecoveryProvenance $bakFile $kind
        return
    }
    $live = Read-Utf8 $liveFile
    $bak = Read-Utf8 $bakFile
    if (-not (Test-SourceProvenanceChanged $live $bak $kind)) { return }
    # REBASE (T-190): the live file's NON-owned content becomes the new pristine
    # base, but its OWNED token values are replaced by the OLD pristine's owned
    # values. A themed live file (Wintage still applied while the user edited an
    # unrelated function) must NEVER become the "pristine" backup wholesale -
    # that would make Revert restore Wintage colours instead of the stock source.
    $newPristine = $live
    if ($kind -eq 'smartvac') {
        foreach ($anchor in $script:SV_ANCHOR_NAMES) {
            $oldM = [regex]::Match($bak, "(?m)^$anchor\s*=\s*'([^']*)'")
            $newM = [regex]::Match($newPristine, "(?m)^$anchor\s*=\s*'([^']*)'")
            # Only rewrite an owned region whose VALUE actually changed (Wintage
            # themed it). A same-value anchor keeps its original bytes so an
            # unmodified upstream file stays byte-exact.
            if ($oldM.Success -and $newM.Success -and $newM.Groups[1].Value -ne $oldM.Groups[1].Value) {
                $newPristine = [regex]::Replace($newPristine, "(?m)^$anchor\s*=\s*'[^']*'", "$anchor = '$($oldM.Groups[1].Value)'")
            }
        }
    } else {
        $m = [regex]::Match($bak, '(?s)TOKENS\s*=\s*\{.*?\}')
        if ($m.Success) { $newPristine = [regex]::Replace($newPristine, '(?s)TOKENS\s*=\s*\{.*?\}', $m.Value) }
    }
    Write-Utf8 $bakFile $newPristine
    # W2-001: the rebased backup is still OUR recovery - re-stamp it.
    Write-RecoveryProvenance $bakFile $kind
    Say "$label : the source changed since the last Wintage touch - rollback base re-based (owned token values kept from the previous pristine)." 'Yellow'
}

# The 23 SMART VAC owned assignment names (the anchors the apply patches).
$script:SV_ANCHOR_NAMES = @('WIN95_BG','WIN95_BG_SOFT','WIN95_SURFACE_RAISED','WIN95_SURFACE_ALT','WIN95_BEVEL_HI','WIN95_BEVEL_SH','WIN95_TEXT','WIN95_TEXT_DIM','WIN95_TEXT_MUTED','WIN95_GOLD','WIN95_GOLD_DIM','WIN95_ACCENT','WIN95_DANGER','WIN95_SUCCESS','WIN95_BUTTON','WIN95_BUTTON_HOVER','WIN95_ENTRY')

# --- T-191 P0#1: target-level commit transactions -------------------------------
# A target's manifest commit is the LAST step of its operation. If that commit
# fails AFTER the target was mutated, the target must return to its exact
# pre-operation state (the old manifest entry - if any - is untouched because
# Set/Remove-ManifestEntry writes atomically and fails whole). Save-FilePreState
# captures byte-exact snapshots before any mutation; Invoke-TargetCommit pairs a
# commit with the restore that undoes it.
function Save-FilePreState([string]$file, [string]$bakFile) {
    $bakOk = $bakFile -and (Test-Path $bakFile)
    return [pscustomobject]@{
        fileBytes = if ($file -and (Test-Path $file)) { [System.IO.File]::ReadAllBytes($file) } else { $null }
        bakExists = [bool]$bakOk
        bakBytes  = if ($bakOk) { [System.IO.File]::ReadAllBytes($bakFile) } else { $null }
    }
}
function Restore-FilePreState($pre, [string]$file, [string]$bakFile) {
    if ($pre -and $null -ne $pre.fileBytes -and $file) { [System.IO.File]::WriteAllBytes($file, $pre.fileBytes) }
    elseif ($file -and (Test-Path $file)) { Remove-Item $file -Force }
    if ($pre -and $pre.bakExists -and $bakFile) { [System.IO.File]::WriteAllBytes($bakFile, $pre.bakBytes) }
    elseif ($bakFile -and (Test-Path $bakFile)) { Remove-Item $bakFile -Force }
}
function Invoke-TargetCommit([string]$target, [string]$label, [scriptblock]$commit, [scriptblock]$restore) {
    # W2-005: rollback is a CHECKED phase. The restore scriptblock must throw
    # on any failure -- including native-program non-zero exits that PowerShell
    # does not promote to terminating errors. The wrapper below captures every
    # call's $LASTEXITCODE and any PowerShell error stream output, and throws
    # a single composite message on rollback failure. The exact-restoration
    # message below is only printed when the entire restore succeeded.
    try {
        & $commit
    } catch {
        if ($restore) {
            try {
                & $restore
                Say "$label`: manifest commit failed - target restored to its exact pre-operation state." 'Yellow'
            } catch {
                Say "$label`: manifest commit failed AND rollback failed - $($_.Exception.Message)" 'Red'
                throw
            }
        }
        throw
    }
}

# W2-005: every native command in a rollback path goes through this helper
# so a non-zero exit is treated as a failure (PowerShell does not promote
# $LASTEXITCODE to a terminating error by itself; $ErrorActionPreference='Stop'
# only does so for PowerShell errors). The captured stdout/stderr is folded
# into the thrown message so a failing rollback never silently succeeds.
function Invoke-Native([string]$label, [scriptblock]$cmd) {
    $output = & $cmd 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $msg = ($output | ForEach-Object { "$_" }) -join "`n"
        throw "$label`: native command FAILED with exit $code. Output: $msg"
    }
    return $output
}

# Whole-directory snapshots for targets whose mutation is directory-shaped (the
# browser stage root, the VS Code extension dirs). Byte-exact, recursive.
#
# CORE-005: the snapshot must represent BOTH pre-states -- "directory existed
# at capture time" and "directory was absent" -- because first-install targets
# routinely create the directory as part of their mutation. A nullable-path
# snapshot collapses those two states into one, and a first-install failure
# leaves a newly-created directory behind while the manifest stays at its
# previous (absent) state. The structured snapshot here is the contract every
# caller relies on.
function Save-DirPreState([string]$dir) {
    if (-not $dir) { return @{ Existed = $false; SnapshotPath = $null } }
    if (-not (Test-Path $dir)) { return @{ Existed = $false; SnapshotPath = $null } }
    $snap = Join-Path $env:TEMP ("wintage-dirstate-" + [guid]::NewGuid().ToString('N'))
    Copy-Item $dir $snap -Recurse -Force
    return @{ Existed = $true; SnapshotPath = $snap }
}
function Restore-DirPreState([string]$dir, $snap) {
    if (-not $snap) { return }
    # W2-001: refuse malformed/non-structured snapshot values. A raw path or
    # any object without explicit Existed/SnapshotPath fields must never be
    # silently coerced into the absent-prestate branch (which would delete a
    # live directory the snapshot was meant to restore).
    $hasExisted = $false
    $hasSnapshotPath = $false
    if ($snap -is [hashtable]) {
        $hasExisted = $snap.ContainsKey('Existed')
        $hasSnapshotPath = $snap.ContainsKey('SnapshotPath')
    } elseif ($snap -is [System.Collections.Specialized.OrderedDictionary]) {
        $hasExisted = $snap.Contains('Existed')
        $hasSnapshotPath = $snap.Contains('SnapshotPath')
    } elseif ($snap.PSObject) {
        $hasExisted = $snap.PSObject.Properties['Existed'] -ne $null
        $hasSnapshotPath = $snap.PSObject.Properties['SnapshotPath'] -ne $null
    }
    if (-not ($hasExisted -and $hasSnapshotPath)) {
        throw "Restore-DirPreState: malformed snapshot for '$dir' (expected @{ Existed = ...; SnapshotPath = ... }, got $($snap.GetType().FullName))"
    }
    $existed = [bool]$snap.Existed
    $path = $snap.SnapshotPath
    if (-not $existed) {
        # The directory was absent pre-Apply; the restore must recreate that
        # exact pre-state, even if a mutation created the directory in the
        # meantime (first-install failure path).
        if ($dir -and (Test-Path $dir)) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        return
    }
    if (-not $path -or -not (Test-Path $path)) { return }
    # W2-002: true two-phase swap. Phase 1 materialise snapshot to a temp
    # sibling (the live dir is untouched at this point). Phase 2 retire the
    # live dir into a recovery sibling, then rename the materialised temp into
    # place. Either rename can fail, but the live content and the restored
    # copy are both preserved as recovery locations until the swap is known
    # good. A failed retire leaves the original at $dir; a failed final
    # rename leaves BOTH the original and the restored copy recoverable.
    $parent = Split-Path $dir
    if (-not $parent) { $parent = '.' }
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = Join-Path $parent ('.wintage-restore-' + [guid]::NewGuid().ToString('N'))
    $retired = $null
    $swapFailures = @()
    try {
        Copy-Item $path $tmp -Recurse -Force
        if (Test-Path $dir) {
            $retired = Join-Path $parent ('.wintage-retired-' + [guid]::NewGuid().ToString('N'))
            try { Rename-Item $dir $retired }
            catch { $swapFailures += "retire: $($_.Exception.Message)"; throw }
        }
        try { Rename-Item $tmp ([IO.Path]::GetFileName($dir)) }
        catch { $swapFailures += "swap: $($_.Exception.Message)"; throw }
        # The restored copy is live; the retired copy may now be retired safely.
        if ($retired -and (Test-Path $retired)) { Remove-Item $retired -Recurse -Force -ErrorAction SilentlyContinue }
    } catch {
        # Preserve every surviving recovery location; do not claim exact
        # restoration when the swap itself is incomplete.
        $surviving = @()
        if ($retired -and (Test-Path $retired)) { $surviving += $retired }
        if (Test-Path $tmp) { $surviving += $tmp }
        $detail = ($swapFailures -join '; ')
        throw "Restore-DirPreState: two-phase swap INCOMPLETE for '$dir' ($detail). Recovery locations preserved: $([string]::Join('; ', $surviving))"
    } finally {
        # The captured snapshot is no longer needed once Restore finishes.
        if ($path -and (Test-Path $path)) { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-WindowsTerminal {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $settingsPaths = @(Get-WindowsTerminalSettingsPaths)
    if (-not $settingsPaths.Count) { Assert-TargetResolvable 'Windows Terminal' $false; return }
    if (-not $node) { throw 'Windows Terminal: node is required to patch JSON-with-comments safely.' }

    $helper = Join-Path $root 'tools/install-terminal.js'
    $paletteFile = Join-Path $root "themes\$PaletteSlug.json"

    if ($DoRevert) {
        # Revert walks the RECORDED owned settings files, not today's discovery
        # (T-190): a settings.json that vanished from discovery after Apply is
        # still part of the ledger and must be handled (or fail closed).
        $m = Read-Manifest
        $recorded = if ($m.ContainsKey('terminal')) { @(Get-ManifestItems $m['terminal']) } else { @() }
        if (-not $recorded.Count) { $recorded = @($settingsPaths) }
        # W2-007: every recorded item is reverted with --keep-recovery so the
        # owned-field backup and the palette marker survive each individual
        # call. A failed sibling keeps the recovery intact for a clean retry.
        # The marker itself is only removed after the manifest commits (below),
        # so a failed manifest commit can re-theme the recorded files
        # without resorting to the palette for state reconstruction.
        $failedItems = @()
        $revertedItems = @()
        foreach ($settings in $recorded) {
            try {
                $args = @($helper, '--settings', $settings, '--revert', '--keep-recovery')
                if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw "Windows Terminal dry-run FAILED ($LASTEXITCODE) - see the message above." }; continue }
                if ($PSCmdlet.ShouldProcess($settings, 'Restore the pre-Wintage settings')) {
                    & node $args
                    if ($LASTEXITCODE -ne 0) { throw "Windows Terminal revert failed for $settings" }
                    $revertedItems += $settings
                }
            } catch { $failedItems += $settings }
        }
        if ($failedItems.Count) {
            # W2-007: an item-N failure must NOT leave items 1..N-1 consumed.
            # Roll the already-reverted items BACK to their themed state from
            # the preserved recovery so the manifest and the file system agree.
            $rollbackErrs = @()
            foreach ($settings in $revertedItems) {
                try {
                    # Re-apply the recorded palette to put the file back. A
                    # final --revert --keep-recovery is safe to call again on
                    # the same file because the recovery artifacts are still
                    # on disk; this re-apply must precede the manifest commit.
                    $palForRollback = $null
                    if ($m.ContainsKey('terminal') -and $m['terminal'].palette) {
                        $palForRollback = Join-Path $root "themes/$($m['terminal'].palette).json"
                    }
                    if ($palForRollback -and (Test-Path $palForRollback)) {
                        Invoke-Native "Windows Terminal rollback re-theme of $settings" { & node $helper --settings $settings --palette $palForRollback }
                    }
                } catch { $rollbackErrs += "$settings`: $($_.Exception.Message)" }
            }
            if ($rollbackErrs.Count) {
                throw "Windows Terminal revert INCOMPLETE for: $($failedItems -join '; ') AND rollback INCOMPLETE ($($rollbackErrs -join '; ')). Manifest and recovery preserved for manual recovery."
            }
            throw "Windows Terminal revert INCOMPLETE for: $($failedItems -join '; ') - already-reverted items were re-themed; manifest kept."
        }
        # T-192 P2/B: the manifest transition is part of the revert transaction.
        # A failed Remove-ManifestEntry re-themes the recorded settings from the
        # recorded palette so state and ledger never disagree.
        Invoke-TargetCommit 'terminal' 'Windows Terminal' {
            Remove-ManifestEntry 'terminal'
        } {
            $m = Read-Manifest
            if ($m.ContainsKey('terminal') -and $m['terminal'].palette) {
                $palFile = Join-Path $root "themes/$($m['terminal'].palette).json"
                foreach ($settings in $revertedItems) {
                    if (Test-Path $settings) {
                        # W2-005: the rollback re-applies the recorded palette via
                        # install-terminal.js. A non-zero exit is a rollback
                        # failure and must throw, not just disappear into Out-Null.
                        Invoke-Native "Windows Terminal rollback for $settings" { & node $helper --settings $settings --palette $palFile }
                    }
                }
            }
        }
        # W2-007: with the manifest transition committed, every reverted item
        # is now safe to consume its recovery artifacts. A failure here is
        # reported but does not undo the manifest removal - the recovery files
        # are inert and can be cleaned up by the next revert or by hand.
        $consumeErrs = @()
        foreach ($settings in $revertedItems) {
            try {
                & node $helper --settings $settings --finalize-recovery
                if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
            } catch { $consumeErrs += "$settings`: $($_.Exception.Message)" }
        }
        if ($consumeErrs.Count) {
            Say "Windows Terminal: recovery artifact consumption incomplete for: $($consumeErrs -join '; '). Run a clean Revert to clean them up." 'Yellow'
        }
        return
    }

    # Multi-settings apply is transactional (T-190): EVERY file is preflighted
    # first, then each is mutated; if item N fails, items 1..N-1 are reverted to
    # their owned-field state so no themed file is left without a manifest.
    $applied = @()
    foreach ($settings in $settingsPaths) {
        $args = @($helper, '--settings', $settings)
        $args += @('--palette', $paletteFile)
        $action = "Apply $PaletteSlug + $CONSOLE_FONT to every profile"
        if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw "Windows Terminal dry-run FAILED ($LASTEXITCODE) - see the message above." }; continue }
        if ($PSCmdlet.ShouldProcess($settings, $action)) {
            & node $args
            if ($LASTEXITCODE -ne 0) {
                # CORE-006: roll back the previously applied items AND the failing
                # current item - the helper writes settings before its marker, so
                # a failure between the two leaves THIS item themed too.
                $rollbackErrs = @()
                foreach ($done in (@($applied) + @($settings))) {
                    try {
                        # W2-005: a failed revert here is a rollback failure that
                        # must surface - the helper owns the item's recovery
                        # markers and a silent failure would consume them.
                        Invoke-Native "Windows Terminal revert of $done" { & node $helper --settings $done --revert }
                    } catch { $rollbackErrs += "$done`: $($_.Exception.Message)" }
                }
                if ($rollbackErrs.Count) {
                    throw "Windows Terminal patch failed for $settings AND rollback INCOMPLETE ($($rollbackErrs -join '; ')). Manifest was NOT updated; the marked settings still own their recovery artifacts."
                }
                throw "Windows Terminal patch failed for $settings - all mutated settings were reverted; the manifest was NOT updated."
            }
            $applied += $settings
        }
    }
    if ($applied.Count) {
        # T-192 P2/B: a manifest-commit failure must roll back the applied settings
        # (the same revert each failed item triggers), never leave them themed with
        # an old manifest.
        Invoke-TargetCommit 'terminal' 'Windows Terminal' {
            Set-ManifestEntryMulti 'terminal' $PaletteSlug (@($applied | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })) 'n/a' (Get-PayloadVersion)
        } {
            foreach ($done in $applied) { & node $helper --settings $done --revert 2>$null | Out-Null }
        }
    }
}

function Invoke-Conhost {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $keys = @(Get-ConhostKeys)
    if (-not $keys.Count) { Assert-TargetResolvable 'Console Host' $false; return }

    # The full set of Wintage-owned console values for a palette. Shared by Apply,
    # the revert rollback (rebuild the themed state after a failed manifest
    # removal) and the health probe, so the "owned state" is defined ONCE.
    #
    # ScreenBufferSize is also owned, but its value is COMPUTED PER KEY by
    # Get-ConhostBufferValue (Value = $null marks it). Some Windows console
    # profiles - cmd.exe and 64-bit PowerShell born from certain launchers - have
    # a screen buffer height EXACTLY equal to the window height, i.e. ZERO
    # scrollback: every command shows only the last screenful and earlier output
    # is gone forever. Wintage owns the console look, so it also guarantees a
    # usable history buffer: height floor 9001 (the classic conhost default),
    # width preserved from the profile's own current value.
    function Get-ConhostBufferValue([string]$psPath) {
        $current = (Get-ItemProperty -LiteralPath $psPath -Name ScreenBufferSize -ErrorAction SilentlyContinue).ScreenBufferSize
        if ($null -eq $current) { return (($CONSOLE_SCROLLBACK_HEIGHT -shl 16) -bor 120) }
        $u = [uint32]$current
        $width = $u -band 0xFFFF
        $height = ($u -shr 16) -band 0xFFFF
        if ($width -lt 20 -or $width -gt 999) { $width = 120 }
        if ($height -lt $CONSOLE_SCROLLBACK_HEIGHT) { $height = $CONSOLE_SCROLLBACK_HEIGHT }
        return (($height -shl 16) -bor $width)
    }
    # Write one owned value; ScreenBufferSize (Value $null) is resolved per key.
    function Set-ConhostValue([string]$psPath, [string]$name, $entry) {
        $value = $entry.Value
        if ($null -eq $value -and $name -eq 'ScreenBufferSize') { $value = Get-ConhostBufferValue $psPath }
        New-ItemProperty -LiteralPath $psPath -Name $name -Value $value -PropertyType $entry.Type -Force | Out-Null
    }
    function Get-ConhostThemeValues([string]$paletteSlug) {
        $t = Get-PaletteTokens (Join-Path $root "themes/$paletteSlug.json")
        return [ordered]@{
            FaceName       = @{ Value = $CONSOLE_FONT; Type = 'String' }
            FontFamily     = @{ Value = 54; Type = 'DWord' }
            FontWeight     = @{ Value = 400; Type = 'DWord' }
            FontSize       = @{ Value = 1048576; Type = 'DWord' }
            ScreenColors   = @{ Value = 15; Type = 'DWord' }
            PopupColors    = @{ Value = 240; Type = 'DWord' }
            CursorColor    = @{ Value = (Convert-HexToBgr $t.link); Type = 'DWord' }
            WindowAlpha    = @{ Value = 255; Type = 'DWord' }
            ScreenBufferSize = @{ Value = $null; Type = 'DWord' }
            ColorTable00   = @{ Value = (Convert-HexToBgr $t.background); Type = 'DWord' }
            ColorTable01   = @{ Value = (Convert-HexToBgr $t.accentTealDeep); Type = 'DWord' }
            ColorTable02   = @{ Value = (Convert-HexToBgr $t.success); Type = 'DWord' }
            ColorTable03   = @{ Value = (Convert-HexToBgr $t.accentTeal); Type = 'DWord' }
            ColorTable04   = @{ Value = (Convert-HexToBgr $t.danger); Type = 'DWord' }
            ColorTable05   = @{ Value = (Convert-HexToBgr $t.surfaceAlt); Type = 'DWord' }
            ColorTable06   = @{ Value = (Convert-HexToBgr $t.warning); Type = 'DWord' }
            ColorTable07   = @{ Value = (Convert-HexToBgr $t.textSecondary); Type = 'DWord' }
            ColorTable08   = @{ Value = (Convert-HexToBgr $t.borderMuted); Type = 'DWord' }
            ColorTable09   = @{ Value = (Convert-HexToBgr $t.link); Type = 'DWord' }
            ColorTable10   = @{ Value = (Convert-HexToBgr $t.success); Type = 'DWord' }
            ColorTable11   = @{ Value = (Convert-HexToBgr $t.accentTeal); Type = 'DWord' }
            ColorTable12   = @{ Value = (Convert-HexToBgr $t.dangerText); Type = 'DWord' }
            ColorTable13   = @{ Value = (Convert-HexToBgr $t.surfaceAlt); Type = 'DWord' }
            ColorTable14   = @{ Value = (Convert-HexToBgr $t.textPrimary); Type = 'DWord' }
            ColorTable15   = @{ Value = (Convert-HexToBgr $t.textPrimary); Type = 'DWord' }
            WintagePalette = @{ Value = $paletteSlug; Type = 'String' }
        }
    }

    if ($DoRevert) {
        # W2-002: a NOOP (no manifest, no recovery) returns $false - stop here
        # instead of reading a backup that does not exist.
        if (-not (Assert-RevertSource 'conhost' $CONHOST_BACKUP 'Console Host')) { return }
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
            Say 'Console Host: restored pre-Wintage registry values.' 'Green'
            # P0#4: the recovery backup is consumed ONLY AFTER the manifest
            # transition succeeds. A failed Remove-ManifestEntry must not destroy
            # the only recovery authority - the rollback puts the THEMED values
            # back (rebuilt from the recorded palette) and leaves the backup for
            # an idempotent retry. Never: target reverted + recovery deleted +
            # manifest still says installed.
            Invoke-TargetCommit 'conhost' 'Console Host' {
                Remove-ManifestEntry 'conhost'
            } {
                $m = Read-Manifest
                if ($m.ContainsKey('conhost') -and $m['conhost'].palette) {
                    $tv = Get-ConhostThemeValues ([string]$m['conhost'].palette)
                    foreach ($key in $keys) {
                        foreach ($name in $tv.Keys) {
                            Set-ConhostValue $key.PSPath $name $tv[$name]
                        }
                    }
                }
            }
            Remove-Item $CONHOST_BACKUP -Force
            Remove-Item ($CONHOST_BACKUP + '.provenance.json') -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $paletteFile = Join-Path $root "themes\$PaletteSlug.json"
    if (-not (Test-Path $paletteFile)) { throw "Console Host: theme file not found ($PaletteSlug.json)" }
    $values = Get-ConhostThemeValues $PaletteSlug

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
            # W2-001: the recovery file is now authoritative - stamp it with the
            # owning install epoch so a foreign copy can never be adopted later.
            Write-RecoveryProvenance $CONHOST_BACKUP 'conhost'
        }
        foreach ($key in $keys) {
            foreach ($name in $values.Keys) {
                Set-ConhostValue $key.PSPath $name $values[$name]
            }
        }
        Say "Console Host: applied $PaletteSlug + $CONSOLE_FONT to $($keys.Count) registry profile(s)." 'Green'
        Say "  Restart cmd/PowerShell windows: new font cells + guaranteed $CONSOLE_SCROLLBACK_HEIGHT-line scrollback (zero-history consoles are fixed)." 'Yellow'
        Invoke-TargetCommit 'conhost' 'Console Host' {
            Set-ManifestEntry 'conhost' $PaletteSlug $CONHOST_KEY 'n/a' (Get-PayloadVersion)
        } {
            # Manifest commit failed: restore every owned value to the exact
            # pre-Wintage snapshot (the backup holds it) and KEEP the backup.
            if (Test-Path $CONHOST_BACKUP) {
                $snap = @(Read-Utf8 $CONHOST_BACKUP | ConvertFrom-Json)
                foreach ($item in $snap) {
                    if (-not (Test-Path -LiteralPath $item.Path)) { continue }
                    if ($item.Existed) {
                        New-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value $item.Value -PropertyType $item.Kind -Force | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}

function Invoke-WindowsTheme {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not $node) { throw 'Windows theme: node is required to preserve and merge the active .theme safely.' }
    $current = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
    $originalTheme = Join-Path $WINDOWS_THEMES_DIR 'Wintage.original.theme'
    $resolvedCurrent = if ($current -and (Test-Path $current)) { $current }
                       elseif (Test-Path $originalTheme) { $originalTheme }
                       elseif (Test-Path 'C:\Windows\Resources\Themes\aero.theme') { 'C:\Windows\Resources\Themes\aero.theme' }
                       elseif (Test-Path 'C:\Windows\Resources\Themes\Light.theme') { 'C:\Windows\Resources\Themes\Light.theme' }
                       else { $null }
    $helper = Join-Path $root 'tools/install-windows-theme.js'
    $built = Join-Path $out "windows/$PaletteSlug/Wintage.theme"
    if (-not $DoRevert -and -not (Test-Path $built)) { throw "No Windows theme build for palette '$PaletteSlug'." }
    if (-not $DoRevert -and -not $resolvedCurrent) {
        throw 'Windows theme: the active .theme file was not found - refusing to apply because the wallpaper/cursor merge would have nothing to preserve.'
    }

    $args = @($helper, '--themes-dir', $WINDOWS_THEMES_DIR)
    if ($DoRevert) { $args += '--revert' }
    else { $args += @('--theme', $built, '--current-theme', $resolvedCurrent, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore the exact pre-Wintage Windows theme snapshot' } else { "Merge and activate Wintage $PaletteSlug, preserving wallpaper/sounds and selecting ___CURRENT___ cursors" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw 'Windows theme dry-run FAILED - see the message above.' }; return }
    if (-not $PSCmdlet.ShouldProcess($WINDOWS_THEMES_DIR, $action)) { return }

    $preAccentItem = Get-Item $WINDOWS_DWM_KEY -ErrorAction SilentlyContinue
    $preAccentExists = $preAccentItem -and ($preAccentItem.GetValueNames() -contains 'AccentColorInactive')
    $preAccent = if ($preAccentExists) { $preAccentItem.GetValue('AccentColorInactive', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
    $preCurrentTheme = $current
    $preThemePaths = @(
        @(Get-ChildItem $WINDOWS_THEMES_DIR -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        (Join-Path $WINDOWS_THEMES_DIR 'Wintage.original.theme')
        (Join-Path $WINDOWS_THEMES_DIR '.wintage-original-theme-path')
        (Join-Path $WINDOWS_THEMES_DIR 'Wintage.theme.wintage.bak')
        (Join-Path $WINDOWS_THEMES_DIR 'Wintage.theme.wintage-created')
        (Join-Path $WINDOWS_THEMES_DIR '.wintage-windows-palette')
        (Join-Path $WINDOWS_THEMES_DIR '.wintage-active-theme-path')
        (Join-Path $WINDOWS_THEMES_DIR '.wintage-epoch-retired')
    ) | Sort-Object -Unique
    $preThemeState = @($preThemePaths | ForEach-Object {
        [pscustomobject]@{
            Path = $_
            Exists = (Test-Path $_)
            Bytes = if (Test-Path $_) { [IO.File]::ReadAllBytes($_) } else { $null }
        }
    })
    function Restore-WindowsPreState {
        if ($preAccentExists) {
            New-ItemProperty -Path $WINDOWS_DWM_KEY -Name AccentColorInactive -Value $preAccent -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $WINDOWS_DWM_KEY -Name AccentColorInactive -ErrorAction SilentlyContinue
        }
        foreach ($t in @(Get-ChildItem $WINDOWS_THEMES_DIR -Filter 'Wintage*.theme' -ErrorAction SilentlyContinue)) {
            if (-not ($preThemeState.Path -contains $t.FullName)) { Remove-Item -LiteralPath $t.FullName -Force -ErrorAction SilentlyContinue }
        }
        foreach ($item in $preThemeState) {
            if ($item.Exists) {
                New-Item -ItemType Directory -Force -Path (Split-Path $item.Path -Parent) | Out-Null
                [IO.File]::WriteAllBytes($item.Path, $item.Bytes)
            } elseif (Test-Path $item.Path) {
                Remove-Item $item.Path -Force -ErrorAction SilentlyContinue
            }
        }
        if ($preCurrentTheme -and (Test-Path $preCurrentTheme)) {
            $now = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
            if (-not $now -or [IO.Path]::GetFullPath($now) -ne [IO.Path]::GetFullPath($preCurrentTheme)) {
                $restoreShell = New-Object -ComObject Shell.Application
                try { $restoreShell.ShellExecute([string]$preCurrentTheme, '', '', 'open', 0) }
                finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($restoreShell) }
            }
        }
    }

    $helperOutput = @(& node $args)
    if ($LASTEXITCODE -ne 0) { throw 'Windows theme preparation failed.' }
    $payload = $helperOutput[-1] | ConvertFrom-Json

    $expectedAccent = $null
    if ($DoRevert) { Restore-WindowsInactiveAccent -Keep }
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
    if (-not $activated) {
        # P1#27: activation was not confirmed - restore the exact owned pre-state
        # (DWM accent + any Wintage*.theme this run created) and keep the DWM
        # backup as the recovery authority. Never throw after partial mutation.
        Restore-WindowsPreState
        throw 'Windows: theme activation was dispatched but Windows did not confirm it after both attempts - the owned pre-state was restored, so the manifest was NOT updated. Re-run to retry.'
    }
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
    if ($DoRevert) {
        Say 'Windows: restored the saved pre-Wintage theme.' 'Green'
        # P1#27: the DWM backup is consumed ONLY after the manifest transition
        # succeeded. A failed Remove-ManifestEntry keeps it for an idempotent retry.
        Invoke-TargetCommit 'windows' 'Windows system theme' {
            Remove-ManifestEntry 'windows'
        } {
            Restore-WindowsPreState
        }
        # W2-003: retire the snapshot epoch ONLY after the manifest transition
        # committed. The next Apply re-baselines from the then-current theme.
        $finalize = & node $helper --themes-dir $WINDOWS_THEMES_DIR --finalize-revert 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Windows: could not finalize the theme epoch after manifest removal; recovery state was kept for retry.' }
        if (Test-Path $WINDOWS_DWM_BACKUP) { Remove-Item $WINDOWS_DWM_BACKUP -Force }
    }
    else {
        Say "Windows: activated Wintage $PaletteSlug; wallpaper/sounds preserved, ___CURRENT___ cursors selected." 'Green'
        Invoke-TargetCommit 'windows' 'Windows system theme' {
            Set-ManifestEntry 'windows' $PaletteSlug $WINDOWS_THEMES_DIR 'n/a' (Get-PayloadVersion)
        } { Restore-WindowsPreState }
    }
}

function Invoke-TotalCmd {
    param([int]$Index, [switch]$DoRevert, [string]$PaletteSlug)
    $appName = if ($Index -eq 1) { 'Total Commander' } else { 'Total Commander (Local)' }
    $manifestName = if ($Index -eq 1) { 'totalcmd' } else { 'totalcmd2' }
    # W2-004: ONE resolver shared with health (RedirectSection followed the same
    # way everywhere); Apply no longer reimplements a second reduced discovery.
    $ini = Resolve-TotalCmdIni $Index
    if (-not $ini) { Assert-TargetResolvable $appName $false; return }

    $lines = (Read-Utf8 $ini) -split '\r?\n'

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
                # Ownership merge (T-189): restore ONLY the Wintage-owned keys into
                # the CURRENT ini; unrelated user edits made after Apply survive.
                # T-192 P2/C: the backup is kept until the manifest transition wins.
                $restored = Restore-TotalCmdOwned $ini $iniBak -Keep
                if (-not $restored) { throw "$($appName): backup exists but could not be parsed - nothing restored." }
                Say "$($appName): restored the Wintage-owned keys into the current wincmd.ini" 'Green'
                Invoke-TargetCommit $manifestName $appName {
                    Remove-ManifestEntry $manifestName
                } {
                    # Manifest removal failed: the backup is still present (kept
                    # above), so an idempotent retry can finish the revert.
                }
                if (Test-Path $iniBak) { Remove-Item $iniBak -Force }
            }
            else {
                # No backup. Only an ini that WE themed (manifest says so) may be
                # stripped; a never-touched ini must not have its [Colors] keys
                # edited by a "revert" that has no recovery state (T-189).
                $m = Read-Manifest
                if (-not $m.ContainsKey($manifestName)) {
                    Say "$($appName): nothing to revert (no Wintage recovery state)." 'DarkYellow'
                    return
                }
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
                # W2-008: the legacy strip is a REAL revert transaction - snapshot
                # the pre-strip INI, strip only the legacy owned keys, then remove
                # the manifest entry through the commit boundary. A failed manifest
                # transition restores the complete pre-strip INI (and the manifest
                # stays), so a retry can finish cleanly instead of repeating the
                # strip forever with installed.json still claiming an install.
                $preLegacy = Save-FilePreState $ini $null
                Write-Utf8BomLines $ini $newLines
                Say "$($appName): no backup found - stripped the colour keys from [Colors]/[ColorsDark] only." 'Yellow'
                Say "  Colours you had set there before Wintage cannot be restored from here." 'Yellow'
                Invoke-TargetCommit $manifestName $appName {
                    Remove-ManifestEntry $manifestName
                } { Restore-FilePreState $preLegacy $ini $null }
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($ini, 'Apply Wintage theme')) {
        $preIni = Save-FilePreState $ini $iniBak
        # Snapshot ONLY the Wintage-owned keys once (T-189): a second snapshot
        # would capture the already-themed values and destroy the one copy of the
        # originals. Same discipline as the MPC-HC .reg backup.
        $jsonPath = Join-Path $root "themes\$PaletteSlug.json"
        if (-not (Test-Path $jsonPath)) { throw "$($appName): theme file not found ($PaletteSlug.json)" }
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

        # Snapshot ONLY the owned keys (with their original values/absence) once,
        # BEFORE any mutation - never a whole-file copy (T-189).
        if (-not (Test-Path $iniBak)) {
            $snapshotJson = Save-TotalCmdSnapshot $lines $recentFilterIds
            New-Item -ItemType Directory -Force -Path (Split-Path $iniBak -Parent) | Out-Null
            Write-Utf8 $iniBak $snapshotJson
            Say "$($appName): snapshotted the Wintage-owned keys -> $(Split-Path $iniBak -Leaf)" 'DarkGray'
        }

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
        # T-192 P2/B: a manifest-commit failure restores the exact pre-mutation ini.
        Invoke-TargetCommit $manifestName $appName {
            Set-ManifestEntry $manifestName $PaletteSlug $ini 'n/a' (Get-PayloadVersion)
        } { Restore-FilePreState $preIni $ini $iniBak }
    }
}

function Invoke-SmartVac {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $SmartVacPath 'SMART VAC CLEANER'
    if (-not (Test-Path $SmartVacPath)) { Assert-TargetResolvable 'SMART VAC CLEANER' $false; return }

    $pyFile = Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py'
    $bakFile = Join-Path $SmartVacPath '_SMART_VAC_CLEANER.py.bak'
    # W2-010: a missing live file is a recovery barrier ONLY for Apply (the
    # source we read does not exist). Revert's recovery source is the backup,
    # and a missing live is exactly the case Revert must repair -- so the
    # gate is split: Apply refuses, Revert proceeds to Assert-RevertSource
    # which validates the backup and its provenance.
    if (-not $DoRevert -and -not (Test-Path $pyFile)) { Assert-TargetResolvable 'SMART VAC CLEANER' $false; return }

    if ($DoRevert) {
        if (-not (Assert-RevertSource 'smartvac' $bakFile 'SMART VAC CLEANER')) { return }
        if ($PSCmdlet.ShouldProcess($pyFile, 'Restore SMART VAC CLEANER from backup')) {
            $pre = Save-FilePreState $pyFile $bakFile
            Copy-Item $bakFile $pyFile -Force
            Say "SMART VAC CLEANER: restored from backup" 'Green'
            # W2-009: defer backup consumption until the manifest removal has
            # committed. A process death between Copy-Item and the manifest
            # transition now leaves bak intact and the manifest at its previous
            # state -- the Revert is retryable, not stranded. Delete the
            # backup inside the commit scriptblock so Restore-FilePreState on
            # a commit failure rebuilds the bak from the in-memory prestate.
            Invoke-TargetCommit 'smartvac' 'SMART VAC CLEANER' {
                Remove-ManifestEntry 'smartvac'
                Remove-Item $bakFile -Force
            } { Restore-FilePreState $pre $pyFile $bakFile }
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($pyFile, "Apply $PaletteSlug theme")) { return }
    
    $json = (Read-Utf8 (Join-Path $root "themes/$PaletteSlug.json")) | ConvertFrom-Json
    $t = $json.tokens
    $code = Read-Utf8 $pyFile
    
    # Every anchor must be matched exactly once before anything is written. A
    # regex that matches nothing would otherwise produce a byte-identical file,
    # be reported as "installed" and advance the manifest -- a no-op patch sold
    # as an install. Requiring exactly one hit per anchor also proves the
    # non-colour shape of each assignment survived (T-187).
    $anchors = [ordered]@{
        'WIN95_BG'           = '(?m)^WIN95_BG\s*=\s*''[^'']+'''
        'WIN95_BG_SOFT'      = '(?m)^WIN95_BG_SOFT\s*=\s*''[^'']+'''
        'WIN95_SURFACE_RAISED' = '(?m)^WIN95_SURFACE_RAISED\s*=\s*''[^'']+'''
        'WIN95_SURFACE_ALT'  = '(?m)^WIN95_SURFACE_ALT\s*=\s*''[^'']+'''
        'WIN95_BEVEL_HI'     = '(?m)^WIN95_BEVEL_HI\s*=\s*''[^'']+'''
        'WIN95_BEVEL_SH'     = '(?m)^WIN95_BEVEL_SH\s*=\s*''[^'']+'''
        'WIN95_TEXT'         = '(?m)^WIN95_TEXT\s*=\s*''[^'']+'''
        'WIN95_TEXT_DIM'     = '(?m)^WIN95_TEXT_DIM\s*=\s*''[^'']+'''
        'WIN95_TEXT_MUTED'   = '(?m)^WIN95_TEXT_MUTED\s*=\s*''[^'']+'''
        'WIN95_GOLD'         = '(?m)^WIN95_GOLD\s*=\s*''[^'']+'''
        'WIN95_GOLD_DIM'     = '(?m)^WIN95_GOLD_DIM\s*=\s*''[^'']+'''
        'WIN95_ACCENT'       = '(?m)^WIN95_ACCENT\s*=\s*''[^'']+'''
        'WIN95_DANGER'       = '(?m)^WIN95_DANGER\s*=\s*''[^'']+'''
        'WIN95_SUCCESS'      = '(?m)^WIN95_SUCCESS\s*=\s*''[^'']+'''
        'WIN95_BUTTON'       = '(?m)^WIN95_BUTTON\s*=\s*''[^'']+'''
        'WIN95_BUTTON_HOVER' = '(?m)^WIN95_BUTTON_HOVER\s*=\s*''[^'']+'''
        'WIN95_ENTRY'        = '(?m)^WIN95_ENTRY\s*=\s*''[^'']+'''
    }
    $values = [ordered]@{
        'WIN95_BG'           = $t.background
        'WIN95_BG_SOFT'      = $t.backgroundSoft
        'WIN95_SURFACE_RAISED' = $t.surfaceRaised
        'WIN95_SURFACE_ALT'  = $t.surfaceAlt
        'WIN95_BEVEL_HI'     = $t.bevelLight
        'WIN95_BEVEL_SH'     = $t.borderDark
        'WIN95_TEXT'         = $t.textPrimary
        'WIN95_TEXT_DIM'     = $t.textSecondary
        'WIN95_TEXT_MUTED'   = $t.textMuted
        'WIN95_GOLD'         = $t.textPrimary
        'WIN95_GOLD_DIM'     = $t.textSecondary
        'WIN95_ACCENT'       = $t.accentTeal
        'WIN95_DANGER'       = $t.danger
        'WIN95_SUCCESS'      = $t.success
        'WIN95_BUTTON'       = $t.surfaceRaised
        'WIN95_BUTTON_HOVER' = $t.surfaceAlt
        'WIN95_ENTRY'        = $t.background
    }
    $appliedHexes = @{}
    foreach ($anchor in $anchors.Keys) {
        $count = ([regex]::Matches($code, $anchors[$anchor])).Count
        if ($count -ne 1) {
            throw "SMART VAC CLEANER: anchor $anchor matched $count time(s) (expected exactly 1) - the source file shape has changed; refusing to patch and leaving the manifest untouched."
        }
        $replacement = "$anchor = '$($values[$anchor])'"
        $code = [regex]::Replace($code, $anchors[$anchor], $replacement)
        $appliedHexes[$values[$anchor]] = $true
    }
    # Verify the output really carries the intended palette before writing.
    if ($appliedHexes.Count -lt 2) { throw 'SMART VAC CLEANER: internal error - the patched output was not verified to contain the palette block.' }
    if (-not ($appliedHexes.Keys | Where-Object { $code.Contains($_) })) {
        throw 'SMART VAC CLEANER: patched output does not contain the intended palette values - refusing to write.'
    }
    # And re-verify the shape survived the patch (each anchor still exactly once).
    foreach ($anchor in $anchors.Keys) {
        $count = ([regex]::Matches($code, $anchors[$anchor])).Count
        if ($count -ne 1) {
            throw "SMART VAC CLEANER: anchor $anchor no longer matches exactly once after patching - source shape corrupted; refusing to write."
        }
    }

    # The pre-Wintage backup is taken ONCE and never overwritten by a repaint
    # (T-187). If the UPSTREAM source changes after a Wintage touch, the backup is
    # re-based from the current source so Revert restores the new version, never
    # the obsolete one (T-189).
    $pre = Save-FilePreState $pyFile $bakFile
    Sync-SourceBackup $pyFile $bakFile 'smartvac' 'SMART VAC CLEANER'
    Write-Utf8 $pyFile $code
    Say "SMART VAC CLEANER: installed theme -> $pyFile" 'Green'
    Invoke-TargetCommit 'smartvac' 'SMART VAC CLEANER' {
        Set-ManifestEntry 'smartvac' $PaletteSlug $pyFile 'n/a' (Get-PayloadVersion)
    } { Restore-FilePreState $pre $pyFile $bakFile }
}

function Invoke-WildRift {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $WildRiftPath 'WildRiftAssistant'
    if (-not (Test-Path $WildRiftPath)) { Assert-TargetResolvable 'WildRiftAssistant' $false; return }

    $pyFile = Join-Path $WildRiftPath 'theme.py'
    $bakFile = Join-Path $WildRiftPath 'theme.py.bak'
    # W2-010: see Invoke-SmartVac -- the live-file gate is split: Apply
    # refuses, Revert proceeds to Assert-RevertSource which validates the
    # backup and its provenance.
    if (-not $DoRevert -and -not (Test-Path $pyFile)) { Assert-TargetResolvable 'WildRiftAssistant' $false; return }

    if ($DoRevert) {
        if (-not (Assert-RevertSource 'wildrift' $bakFile 'WildRiftAssistant')) { return }
        if ($PSCmdlet.ShouldProcess($pyFile, 'Restore WildRiftAssistant from backup')) {
            $pre = Save-FilePreState $pyFile $bakFile
            Copy-Item $bakFile $pyFile -Force
            Say "WildRiftAssistant: restored from backup" 'Green'
            # W2-009: defer backup consumption until the manifest removal has
            # committed -- a process death at this seam is now retryable.
            Invoke-TargetCommit 'wildrift' 'WildRiftAssistant' {
                Remove-ManifestEntry 'wildrift'
                Remove-Item $bakFile -Force
            } { Restore-FilePreState $pre $pyFile $bakFile }
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($pyFile, "Apply $PaletteSlug theme")) { return }
    
    # The rollback base follows the upstream source (T-189): a repaint must never
    # rebuild the live file from an obsolete pre-update backup. The backup is
    # re-based when the live file changed in non-Wintage content.
    $pre = Save-FilePreState $pyFile $bakFile
    Sync-SourceBackup $pyFile $bakFile 'wildrift' 'WildRiftAssistant'
    $json = (Read-Utf8 (Join-Path $root "themes/$PaletteSlug.json")) | ConvertFrom-Json
    $pyTokens = "TOKENS = {`r`n"
    foreach ($p in $json.tokens.psobject.properties) {
        $pyTokens += "    `"$($p.Name)`": `"$($p.Value)`",`r`n"
    }
    $pyTokens += "}"
    $code = Read-Utf8 $pyFile
    # The TOKENS block must exist exactly once. Zero matches means the source has
    # no such block (a different theme.py) and a silent no-op write would look
    # like a successful install; more than one is a shape this patch never wrote.
    $tokPattern = '(?s)TOKENS\s*=\s*\{.*?\}'
    $tokCount = ([regex]::Matches($code, $tokPattern)).Count
    if ($tokCount -ne 1) {
        throw "WildRiftAssistant: TOKENS block matched $tokCount time(s) (expected exactly 1) - the source file shape has changed; refusing to patch and leaving the manifest untouched."
    }
    $code = [regex]::Replace($code, $tokPattern, $pyTokens)
    if (-not $code.Contains('"' + $json.tokens.background + '"') -or -not $code.Contains('"' + $json.tokens.textPrimary + '"')) {
        throw 'WildRiftAssistant: patched output does not contain the intended palette tokens - refusing to write.'
    }
    if (([regex]::Matches($code, $tokPattern)).Count -ne 1) {
        throw 'WildRiftAssistant: TOKENS block no longer matches exactly once after patching - refusing to write.'
    }
    Write-Utf8 $pyFile $code
    Say "WildRiftAssistant: installed theme -> $pyFile" 'Green'
    Invoke-TargetCommit 'wildrift' 'WildRiftAssistant' {
        Set-ManifestEntry 'wildrift' $PaletteSlug $pyFile 'n/a' (Get-PayloadVersion)
    } { Restore-FilePreState $pre $pyFile $bakFile }
}

function Invoke-Saipenview {
    param([switch]$DoRevert, [string]$PaletteSlug)
    Assert-SafeProjectPath $SaipenviewPath 'SAIPENVIEW'
    if (-not (Test-Path $SaipenviewPath)) { Assert-TargetResolvable 'SAIPENVIEW' $false; return }
    
    $cssFile = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css'
    $bakFile = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css.bak'
    
    if ($DoRevert) {
        if (-not (Assert-RevertSource 'saipenview' $bakFile 'SAIPENVIEW')) { return }
        if ($PSCmdlet.ShouldProcess($cssFile, 'Restore SAIPENVIEW original CSS')) {
            $pre = Save-FilePreState $cssFile $bakFile
            Copy-Item $bakFile $cssFile -Force
            Say "SAIPENVIEW: restored from backup" 'Green'
            # W2-009: defer backup consumption until the manifest removal has
            # committed -- a process death at this seam is now retryable.
            Invoke-TargetCommit 'saipenview' 'SAIPENVIEW' {
                Remove-ManifestEntry 'saipenview'
                Remove-Item $bakFile -Force
            } { Restore-FilePreState $pre $cssFile $bakFile }
        }
        return
    }
    
    if (-not (Test-Path $cssFile)) { Assert-TargetResolvable 'SAIPENVIEW' $false; return }
    
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
                # T-192 P1#18: REBASE, never a wholesale copy. The live CSS may
                # already carry Wintage palette values (theme still applied while
                # SAIPENVIEW/upstream added unrelated selectors). Copying it
                # wholesale into the pristine authority would make Revert restore
                # Wintage colours. The new pristine = current non-owned CSS with
                # every Wintage-owned --token VALUE taken from the OLD pristine.
                $oldPristine = Read-Utf8 $bakFile
                $live = Read-Utf8 $cssFile
                $newPristine = Rebase-CssTokens $live $oldPristine
                Write-Utf8 $bakFile $newPristine
                Write-RecoveryProvenance $bakFile 'saipenview'
                Say "SAIPENVIEW: style.css has changed since the backup was taken - backup rebased (previous kept as style.css.bak.stale)" 'DarkYellow'
            }
        } else {
            Copy-Item $cssFile $bakFile -Force
            Write-RecoveryProvenance $bakFile 'saipenview'
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
        if (-not (Test-Path $jsonPath)) { throw "SAIPENVIEW: theme file not found ($PaletteSlug.json)" }
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

        # Zero tokens recoloured would be a no-op wearing an install's clothes:
        # same bytes on disk, "installed" in the log, manifest advanced. Fail
        # BEFORE any write so a doomed run mutates nothing (T-191 P0#1).
        if ($applied.Count -eq 0) {
            throw 'SAIPENVIEW: no --token declarations matched in style.css - refusing to write an unchanged file as an install; check that the CSS is the one this theme expects.'
        }

        $pre = Save-FilePreState $cssFile $bakFile
        Write-Utf8 $cssFile $text

        Say "SAIPENVIEW: recoloured $($applied.Count) tokens to $PaletteSlug - colours only, layout untouched" 'Green'
        Invoke-TargetCommit 'saipenview' 'SAIPENVIEW' {
            Set-ManifestEntry 'saipenview' $PaletteSlug $cssFile 'n/a' (Get-PayloadVersion)
        } { Restore-FilePreState $pre $cssFile $bakFile }
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
    
    if (-not (Test-Path $bdDir)) { Assert-TargetResolvable 'BetterDiscord' $false; return }

    # CORE-002: persistent first-touch recovery OUTSIDE the target directory with
    # explicit created-vs-replaced provenance. The filename is never ownership
    # authority; the recovery ledger is. Repaint never overwrites the pristine.
    $recDir = Join-Path $WintageAppData 'recovery\discord'
    $recMeta = Join-Path $recDir 'recovery.json'
    $pristine = Join-Path $recDir 'pristine.css'

    if ($DoRevert) {
        if (Test-Path $bdCss) {
            if ($PSCmdlet.ShouldProcess($bdCss, 'Restore/remove the Wintage theme')) {
                $pre = Save-FilePreState $bdCss $null
                if (Test-Path $recMeta) {
                    $meta = Read-Utf8 $recMeta | ConvertFrom-Json
                            # W2-001: a recovery ledger stamped by another install is
                    # never adopted to rewrite the user's live css.
                    Assert-RecoveryProvenance $recMeta 'discord' 'BetterDiscord' | Out-Null
                    if ($meta.mode -eq 'replaced') {
                        if (-not (Test-Path $pristine)) { throw "BetterDiscord: pristine recovery is missing ($pristine) - refusing to delete the live CSS." }
                        [System.IO.File]::WriteAllBytes($bdCss, [System.IO.File]::ReadAllBytes($pristine))
                        Say 'BetterDiscord: restored the pre-existing user theme byte-for-byte' 'Green'
                    } else {
                        Remove-Item $bdCss -Force
                        Say "BetterDiscord: removed $bdCss (Wintage-created, nothing pre-existed)" 'Green'
                    }
                    Invoke-TargetCommit 'discord' 'BetterDiscord' {
                        Remove-ManifestEntry 'discord'
                    } { Restore-FilePreState $pre $bdCss $null }
                    # Recovery is consumed ONLY after the manifest transition
                    # committed; a failed transition keeps it for a retry.
                    Remove-Item $recMeta -Force -ErrorAction SilentlyContinue
                    Remove-Item $pristine -Force -ErrorAction SilentlyContinue
                } else {
                    $m = Read-Manifest
                    if ($m.ContainsKey('discord')) {
                        throw "BetterDiscord: the manifest records an install but the persistent recovery is missing ($recMeta) - cannot restore an unverifiable state; the css and the manifest were both left untouched."
                    }
                    # A never-installed same-name user file survives explicit Revert.
                    Say "BetterDiscord: nothing to revert (no Wintage recovery state) - $bdCss was left untouched." 'DarkYellow'
                }
            }
        } else {
            $m = Read-Manifest
            if ($m.ContainsKey('discord')) {
                # The themed file is already gone; the ledger is the only thing
                # left to reconcile, and removing the entry cannot harm user data.
                if ($PSCmdlet.ShouldProcess($ManifestPath, 'Remove the discord manifest entry (theme file already absent)')) {
                    Invoke-TargetCommit 'discord' 'BetterDiscord' { Remove-ManifestEntry 'discord' } { }
                    Remove-Item $recMeta -Force -ErrorAction SilentlyContinue
                    Remove-Item $pristine -Force -ErrorAction SilentlyContinue
                }
            } else { Say "BetterDiscord: nothing installed, nothing to revert." }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($bdCss, 'Install Wintage theme')) {
        $built = Join-Path $out "betterdiscord/$PaletteSlug/wintage.theme.css"
        if (-not (Test-Path $built)) { throw "Built BetterDiscord output missing for '$PaletteSlug'. Run 'node tools/build-desktop.js'." }
        # Capture the pristine ONLY on the first-ever touch; a repaint must never
        # overwrite it with Wintage output.
        if (-not (Test-Path $recMeta)) {
            New-Item -ItemType Directory -Force -Path $recDir | Out-Null
            $mode = if (Test-Path $bdCss) { 'replaced' } else { 'created' }
            if ($mode -eq 'replaced') { [System.IO.File]::WriteAllBytes($pristine, [System.IO.File]::ReadAllBytes($bdCss)) }
            Write-Utf8 $recMeta (@{ mode = $mode; target = 'discord'; created = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json)
            # W2-001: the ledger is authoritative - stamp it with the owning epoch.
            Write-RecoveryProvenance $recMeta 'discord'
        }
        $pre = Save-FilePreState $bdCss $null
        Copy-Item $built $bdCss -Force
        Say "BetterDiscord: installed theme -> $bdCss" 'Green'
        Invoke-TargetCommit 'discord' 'BetterDiscord' {
            Set-ManifestEntry 'discord' $PaletteSlug $bdCss 'n/a' (Get-PayloadVersion)
        } { Restore-FilePreState $pre $bdCss $null }
    }
}

function Invoke-Obsidian {
    param([switch]$DoRevert, [string]$PaletteSlug)

    # T-191 P0#1: Obsidian mutates whole theme trees + appearance.json per vault,
    # so a manifest-commit failure needs a full per-vault byte snapshot to roll
    # back. Save-VaultPreState captures the Wintage-* dirs + appearance + the
    # cssTheme snapshot file's existence; Restore-VaultPreState re-materialises it.
    function Save-VaultPreState([string]$vault) {
        $themesDir = Join-Path $vault '.obsidian/themes'
        $appearance = Join-Path $vault '.obsidian/appearance.json'
        $dirs = @{}
        if (Test-Path $themesDir) {
            foreach ($d in (Get-ChildItem $themesDir -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue)) {
                $files = @{}
                Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $files[$_.FullName.Substring($d.FullName.Length)] = [System.IO.File]::ReadAllBytes($_.FullName)
                }
                $dirs[$d.FullName] = $files
            }
        }
        $apBytes = if (Test-Path $appearance) { [System.IO.File]::ReadAllBytes($appearance) } else { $null }
        $bakPath = (Get-VaultBackupPath $vault)
        # CORE-002 (SRC-002): the per-vault cssTheme recovery file is a Revert
        # input, not an Apply output. Snapshot its bytes byte-exactly alongside
        # dirs+appearance so a manifest-commit failure mid-Revert can put it
        # back even after a successful Revert read+merged+deleted it; otherwise
        # a later clean Revert has no cssTheme to merge back.
        $bakBytes = if (Test-Path $bakPath) { [System.IO.File]::ReadAllBytes($bakPath) } else { $null }
        return [pscustomobject]@{
            vault = $vault
            dirs = $dirs
            appearance = $apBytes
            bakExists = ($null -ne $bakBytes)
            bakBytes = $bakBytes
        }
    }
    function Restore-VaultPreState($pre) {
        $themesDir = Join-Path $pre.vault '.obsidian/themes'
        if (Test-Path $themesDir) {
            Get-ChildItem $themesDir -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force
            }
        }
        foreach ($dir in $pre.dirs.Keys) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            foreach ($rel in $pre.dirs[$dir].Keys) {
                [System.IO.File]::WriteAllBytes((Join-Path $dir $rel), $pre.dirs[$dir][$rel])
            }
        }
        $appearance = Join-Path $pre.vault '.obsidian/appearance.json'
        if ($null -ne $pre.appearance) { [System.IO.File]::WriteAllBytes($appearance, $pre.appearance) }
        elseif (Test-Path $appearance) { Remove-Item $appearance -Force }
        $bakPath = Get-VaultBackupPath $pre.vault
        # CORE-002: byte-exact restore matches the snapshot's prior existence -
        # if the cssTheme recovery file existed before, rewrite its exact bytes;
        # only remove it when it did not pre-exist (this is the original
        # Save-FilePreState contract applied to the recovery file).
        if ($pre.bakExists) {
            $parent = Split-Path $bakPath -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            [System.IO.File]::WriteAllBytes($bakPath, $pre.bakBytes)
        }
        elseif (Test-Path $bakPath) { Remove-Item $bakPath -Force }
    }
    # CORE-003: every generated theme directory carries verifiable Wintage
    # ownership metadata. Obsidian ignores unknown files in a theme folder, so
    # an extra .json cannot affect the community theme.
    function Write-VaultThemeOwner([string]$dir, [string]$displayName) {
        # W2-001: the marker carries the owning install epoch so a theme dir
        # copied from another machine is never treated as ours.
        $owner = [ordered]@{ owner = 'Wintage'; schema = 1; target = 'obsidian-theme'; name = $displayName; epoch = (Get-InstallEpoch); created = (Get-Date).ToUniversalTime().ToString('o') }
        Write-Utf8 (Join-Path $dir '.wintage-owner.json') (($owner | ConvertTo-Json) + "`n")
    }
    # The exact generated display names for every pack - the ONLY names Wintage
    # may treat as owned in a vault (CORE-003): never a prefix wildcard.
    function Get-BuiltThemeNames([string]$builtRoot) {
        $names = @()
        if (Test-Path $builtRoot) {
            $names = @(Get-ChildItem $builtRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                try { (Read-Utf8 (Join-Path $_.FullName 'manifest.json') | ConvertFrom-Json).name } catch { $null }
            } | Where-Object { $_ })
        }
        return $names
    }
    # A dir is owned when it carries a marker from THIS install epoch, OR (legacy
    # installs that predate markers) its name is exactly one of the generated
    # display names. A marker stamped for another install is foreign evidence:
    # it may not authorize deletion and it is not counted as our health either.
    function Test-VaultThemeOwned([string]$dir, [string[]]$expectedNames) {
        $marker = Join-Path $dir '.wintage-owner.json'
        if (Test-Path $marker) {
            try {
                $owned = Read-Utf8 $marker | ConvertFrom-Json
                if ($owned.epoch -and $owned.epoch.ToString() -eq (Get-InstallEpoch)) { return $true }
                return $false
            } catch { return $false }
        }
        return ((Split-Path $dir -Leaf) -in $expectedNames)
    }

    $vaults = Get-ObsidianVaults
    if (-not $vaults) { Assert-TargetResolvable 'Obsidian' $false; return }

    $builtRoot = Join-Path $out 'obsidian'
    if (-not (Test-Path $builtRoot)) { throw "Built Obsidian output missing. Run 'node tools/build-desktop.js'." }
    # The active theme's display name comes from the built manifest for that slug, so
    # it always matches the folder name Obsidian will look for -- never guessed.
    $activeManifest = Join-Path $builtRoot "$PaletteSlug/manifest.json"
    if (-not (Test-Path $activeManifest)) { throw "No Obsidian build for palette '$PaletteSlug'." }
        $activeName = (Read-Utf8 $activeManifest | ConvertFrom-Json).name

    $bakDir = $backupBase
    New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
    # Canonical per-vault identity: two different vault paths must never hash to
    # the same backup name, and the same path must always name the same backup.
    # A sanitised path collides (T-189).
    $sha = [System.Security.Cryptography.SHA256]::Create()
    function Get-VaultBackupPath([string]$vault) {
        $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($vault))).Replace('-', '').Substring(0, 20)
        Join-Path $bakDir ("obsidian-cssTheme-" + $hash + '.json')
    }

    if ($DoRevert) {
        # Revert walks the RECORDED owned vault set, not today's discovery
        # (T-190): a vault removed from obsidian.json after Apply must still be
        # reverted, and a newly-discovered vault belongs to the next Apply, never
        # to this rollback. Legacy manifests without `items` fall back to the
        # single recorded `path`.
        $m = Read-Manifest
        $recorded = if ($m.ContainsKey('obsidian')) { @(Get-ManifestItems $m['obsidian']) } else { @() }
        if (-not $recorded.Count) { $recorded = @($vaults) }
        $preStates = @($recorded | ForEach-Object { Save-VaultPreState $_ })
        $expectedNames = Get-BuiltThemeNames $builtRoot
        $failedVaults = @()
        foreach ($vault in $recorded) {
            $preThis = Save-VaultPreState $vault
            try {
                $themesDir = Join-Path $vault '.obsidian/themes'
                $appearance = Join-Path $vault '.obsidian/appearance.json'
                # CORE-003: ONLY exact directories whose ownership is proven (the
                # owner marker, or an exact generated display name for legacy
                # installs) are touched. A hand-made 'Wintage MyHandMade' lookalike
                # - or any dir that is not exactly ours - is preserved.
                if (Test-Path $themesDir) {
                    foreach ($d in (Get-ChildItem $themesDir -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue)) {
                        if (-not (Test-VaultThemeOwned $d.FullName $expectedNames)) { continue }
                        if ($PSCmdlet.ShouldProcess($d.FullName, 'Remove Wintage theme')) { Remove-Item $d.FullName -Recurse -Force }
                    }
                    # Restore ONLY the cssTheme choice into the CURRENT appearance.json
                    # (T-189); unrelated appearance.json edits made after Apply survive.
                    $bak = Get-VaultBackupPath $vault
                    if (Test-Path $bak) {
                        # W2-001: never consume a cssTheme snapshot from another install.
                        Assert-RecoveryProvenance $bak 'obsidian' 'Obsidian' | Out-Null
                        $snap = Read-Utf8 $bak | ConvertFrom-Json
                        if (Test-Path $appearance) {
                            $ap = (Read-Utf8 $appearance) | ConvertFrom-Json
                            if ($snap.existed) { $ap | Add-Member -NotePropertyName cssTheme -NotePropertyValue $snap.value -Force }
                            else { $ap.PSObject.Properties.Remove('cssTheme') }
                            Write-Utf8 $appearance ($ap | ConvertTo-Json -Depth 10)
                        }
                        Remove-Item $bak -Force
                    }
                    Say "Obsidian: removed Wintage themes from $vault" 'Green'
                }
            } catch {
                # CORE-006: a failing vault restores ITS OWN pre-state immediately
                # (rollback is not deferred to some outer boundary that never sees
                # this mutation - Obsidian captures prestate BEFORE entering the
                # manifest-transaction wrapper).
                try { Restore-VaultPreState $preThis } catch { }
                $failedVaults += "$vault ($($_.Exception.Message))"
            }
        }
        # Remove the manifest ONLY after every RECORDED vault reverted; a partial
        # revert keeps it as recovery evidence (T-189/T-190).
        if ($failedVaults.Count) { throw "Obsidian revert INCOMPLETE for: $($failedVaults -join '; ') - manifest kept." }
        Invoke-TargetCommit 'obsidian' 'Obsidian' {
            Remove-ManifestEntry 'obsidian'
        } { foreach ($p in $preStates) { Restore-VaultPreState $p } }
        return
    }

    $preStates = @($vaults | ForEach-Object { Save-VaultPreState $_ })
    $failedVaults = @()
    foreach ($vault in $vaults) {
        $preThis = Save-VaultPreState $vault
        try {
            $themesDir = Join-Path $vault '.obsidian/themes'
            $appearance = Join-Path $vault '.obsidian/appearance.json'
            if ($PSCmdlet.ShouldProcess($vault, "Install all Wintage themes, activate $PaletteSlug")) {
                New-Item -ItemType Directory -Force -Path $themesDir | Out-Null
                foreach ($pack in (Get-ChildItem $builtRoot -Directory)) {
                    $manifest = Read-Utf8 (Join-Path $pack.FullName 'manifest.json') | ConvertFrom-Json
                    $dest = Join-Path $themesDir $manifest.name
                    # CORE-003: an exact-name collision with a pre-existing USER
                    # directory of the same generated name is recorded in the
                    # per-vault prestate (Save-VaultPreState captures it byte-
                    # exactly), so Revert can restore it. The fresh dir is then
                    # stamped with the ownership marker after the pack lands.
                    New-Item -ItemType Directory -Force -Path $dest | Out-Null
                    Copy-Item (Join-Path $pack.FullName '*') -Destination $dest -Recurse -Force
                    Write-VaultThemeOwner $dest $manifest.name
                }
                $count = (Get-ChildItem $builtRoot -Directory).Count
                # Set the chosen palette active, snapshotting the cssTheme choice
                # ONCE so revert can merge it back (T-189) - never a whole-file copy.
                if (Test-Path $appearance) {
                    $bak = Get-VaultBackupPath $vault
                    if (-not (Test-Path $bak)) {
                        $ap0 = (Read-Utf8 $appearance) | ConvertFrom-Json
                        $prev = if ($ap0.PSObject.Properties['cssTheme']) { $ap0.cssTheme } else { $null }
                        Write-Utf8 $bak (@{ existed = ($null -ne $prev); value = $prev } | ConvertTo-Json -Depth 4)
                        # W2-001: the cssTheme snapshot is now authoritative - stamp it.
                        Write-RecoveryProvenance $bak 'obsidian'
                    }
                    $ap = (Read-Utf8 $appearance) | ConvertFrom-Json
                    $ap | Add-Member -NotePropertyName cssTheme -NotePropertyValue $activeName -Force
                    Write-Utf8 $appearance ($ap | ConvertTo-Json -Depth 10)
                }
                Say "Obsidian: installed $count themes into $vault, active '$activeName'" 'Green'
                Say "  Reload the vault (Ctrl+R) or Settings > Appearance to see it." 'DarkGray'
            }
        } catch {
            # CORE-006: this vault's partial mutation is rolled back NOW, so a
            # failing vault 2 never leaves vault 1 themed without a manifest.
            try { Restore-VaultPreState $preThis } catch { }
            $failedVaults += "$vault ($($_.Exception.Message))"
        }
    }
    # The manifest is advanced ONLY after EVERY vault succeeded (T-189) and
    # records the EXACT owned vault SET (T-190) so a later Reapply compares sets,
    # not a `;`-joined fake path.
    if ($failedVaults.Count) {
        throw "Obsidian apply INCOMPLETE for: $($failedVaults -join '; ') - manifest NOT advanced; re-run after fixing the failing vault(s)."
    }
    Invoke-TargetCommit 'obsidian' 'Obsidian' {
        Set-ManifestEntryMulti 'obsidian' $PaletteSlug (@($vaults | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })) 'n/a' (Get-PayloadVersion)
    } { foreach ($p in $preStates) { Restore-VaultPreState $p } }
}

function Invoke-Obs {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not (Test-Path $OBS_CONFIG)) { Assert-TargetResolvable 'OBS Studio' $false; return }
    if (Get-Process obs64 -ErrorAction SilentlyContinue) {
        throw 'OBS Studio: close OBS and Apply again so it cannot overwrite user.ini on exit.'
    }
    if (-not $node) { throw 'OBS Studio: node is required to patch user.ini safely.' }

    $helper = Join-Path $root 'tools/install-obs.js'
    $theme = Join-Path $out "obs/$PaletteSlug/Wintage.ovt"
    if (-not $DoRevert -and -not (Test-Path $theme)) { throw "No OBS build for palette '$PaletteSlug'." }
    $args = @($helper, '--config', $OBS_CONFIG)
    if ($DoRevert) {
        # CORE-010/CORE-001: parent-coordinated revert. The helper restores the
        # target but KEEPS its persistent recovery (--keep-recovery); the parent
        # consumes it via --finalize-revert ONLY after the manifest transition
        # commits. A failed transition can then restore every artifact exactly.
        $args += @('--revert', '--keep-recovery')
    } else { $args += @('--theme', $theme, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore previous OBS theme and selection' } else { "Install and activate Wintage $PaletteSlug" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw 'OBS Studio dry-run FAILED - see the message above.' }; return }

    # CORE-010: the complete helper-owned OBS set is ONE transaction. The parent
    # snapshots user.ini (the ONE authoritative settings file - the helper never
    # touches global.ini, so global.ini is never a rollback surrogate), the
    # theme file, the palette marker AND the helper's own recovery artifacts, so
    # a manifest-transition failure can restore every one of them exactly.
    function Save-ObsPreState {
        $snap = @{}
        foreach ($rel in @('user.ini', '.wintage-obs-palette', 'themes\Wintage.ovt',
                'user.ini.wintage.bak', 'user.ini.wintage-created',
                'themes\Wintage.ovt.wintage.bak', 'themes\Wintage.ovt.wintage-created')) {
            $p = Join-Path $OBS_CONFIG $rel
            $snap[$rel] = if (Test-Path $p) { [System.IO.File]::ReadAllBytes($p) } else { $null }
        }
        return $snap
    }
    function Restore-ObsPreState($snap) {
        foreach ($rel in $snap.Keys) {
            $dst = Join-Path $OBS_CONFIG $rel
            try {
                if ($null -ne $snap[$rel]) {
                    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                    [System.IO.File]::WriteAllBytes($dst, $snap[$rel])
                } elseif (Test-Path $dst) { Remove-Item $dst -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
    }

    if ($PSCmdlet.ShouldProcess($OBS_CONFIG, $action)) {
        if ($DoRevert) {
            # W2-001: recovery artifacts stamped by another install are never
            # consumed to rewrite the live OBS config - fail closed BEFORE the
            # helper mutates anything. Files without a stamp predate the contract.
            foreach ($rel in @('user.ini.wintage.bak', 'user.ini.wintage-created',
                    'themes\Wintage.ovt.wintage.bak', 'themes\Wintage.ovt.wintage-created')) {
                $p = Join-Path $OBS_CONFIG $rel
                if (Test-Path $p) { Assert-RecoveryProvenance $p 'obs' 'OBS Studio' | Out-Null }
            }
        }
        $pre = Save-ObsPreState
        # The .ovt names Verdana_m1 first and falls back to Verdana (Qt cannot
        # switch antialiasing off, so UI.md law 1 comes from the FACE). Advice
        # only - Wintage never installs or removes fonts.
        if (-not $DoRevert) { Say-WintageFontAdvice 'OBS Studio' }
        & node $args
        if ($LASTEXITCODE -ne 0) { throw 'OBS Studio theme patch failed.' }
        if ($DoRevert) {
            Invoke-TargetCommit 'obs' 'OBS Studio' {
                Remove-ManifestEntry 'obs'
            } { Restore-ObsPreState $pre }
            # The manifest transition committed: the persistent recovery the
            # helper preserved can now be consumed.
            & node $helper --config $OBS_CONFIG --finalize-revert
            if ($LASTEXITCODE -ne 0) { throw 'OBS Studio: recovery finalize FAILED - the manifest is already removed; remove the .wintage recovery files by hand if they remain.' }
        } else {
            Invoke-TargetCommit 'obs' 'OBS Studio' {
                Set-ManifestEntry 'obs' $PaletteSlug $OBS_CONFIG 'n/a' (Get-PayloadVersion)
            } { Restore-ObsPreState $pre }
            # W2-001: the helper's recovery files are now authoritative - stamp
            # them so a later Revert refuses to adopt a foreign copy.
            foreach ($rel in @('user.ini.wintage.bak', 'user.ini.wintage-created',
                    'themes\Wintage.ovt.wintage.bak', 'themes\Wintage.ovt.wintage-created')) {
                $p = Join-Path $OBS_CONFIG $rel
                if (Test-Path $p) { Write-RecoveryProvenance $p 'obs' }
            }
        }
    }
}

function Invoke-MpcHc {
    param([switch]$DoRevert)

    if (-not (Test-Path $MPC_KEY)) { Assert-TargetResolvable 'MPC-HC' $false; return }

    $bakDir = $backupBase
    $bak = Join-Path $bakDir 'mpc-hc-settings.reg'

    # MPCTheme 1 = the dark UI. ModernThemeMode 2 = dark title bar too.
    # OSD: Verdana per UI.md law 1, a size on its ladder, zero transparency
    # (law 2 forbids it outright), and a border so it reads as a raised surface.
    #
    # The face is Verdana_m1 - the non-antialiased Verdana patch this repo ships -
    # when the machine has it, because OSDFont is a plain GDI face name and there
    # is no setting anywhere in MPC-HC to switch smoothing off. Law 1's
    # "non-antialiased" therefore has to come from the font itself. Unlike a
    # stylesheet this value carries NO fallback chain, so naming an absent face
    # would hand the OSD to whatever GDI substitutes: the face is probed, never
    # assumed, and Wintage does not install it (see the font note at the top).
    $osdFont = Get-WintageFontFace
    $vals = @{
        MPCTheme         = 1
        ModernThemeMode  = 2
        OSDFont          = $osdFont
        OSDSize          = 16
        OSDTransparency  = 0
        OSDBorder        = 1
        TitleBarTextStyle = 1
    }

    if ($DoRevert) {
        if (-not (Assert-RevertSource 'mpchc' $bak 'MPC-HC')) { return }
        if ($PSCmdlet.ShouldProcess($MPC_REG, "Restore from $bak")) {
            # reg import merges; it restores the values that were captured and leaves
            # anything created since. That is the honest limit of a .reg backup and
            # it is stated rather than glossed.
            & reg import $bak 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "MPC-HC: reg import failed ($LASTEXITCODE) -- values were NOT restored. The manifest and backup are kept so a retry or manual reg import can still recover."
            }
            Say "MPC-HC: restored the captured values from $bak" 'Green'
            Invoke-TargetCommit 'mpchc' 'MPC-HC' {
                Remove-ManifestEntry 'mpchc'
            } {
                # W2-005: rollback re-applies the theme keys. Each registry
                # write is checked, so a single failure does not silently
                # claim exact restoration while leaving partial state behind.
                $failed = @()
                foreach ($k in $vals.Keys) {
                    $type = if ($vals[$k] -is [string]) { 'String' } else { 'DWord' }
                    try {
                        Set-ItemProperty -Path $MPC_KEY -Name $k -Value $vals[$k] -Type $type -ErrorAction Stop
                    } catch {
                        $failed += "$k`: $($_.Exception.Message)"
                    }
                }
                if ($failed.Count) { throw "MPC-HC: rollback registry writes failed ($($failed -join '; ')). Manifest kept; user must rerun or fix registry manually." }
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($MPC_REG, 'Back up and apply the Wintage/UI.md settings')) {
        New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
        if (-not (Test-Path $bak)) {
            # The backup IS the revert source. If it cannot be exported, the registry
            # must not be touched: mutating MPC-HC now and advertising a reversible
            # install that has no rollback file is exactly the false success this
            # pass removes.
            & reg export $MPC_REG $bak /y 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "MPC-HC: reg export failed ($LASTEXITCODE) -- backup not created, so the registry was NOT changed. Fix reg export and re-run." }
            Write-RecoveryProvenance $bak 'mpchc'
            Say "MPC-HC: settings backed up to $bak" 'DarkGray'
        }
        else { Say "MPC-HC: keeping the existing backup at $bak (it holds the pre-Wintage state)" 'DarkGray' }

        # OSDFont carries no fallback chain, so an absent face is reported rather
        # than named. Wintage never installs the font itself.
        Say-WintageFontAdvice 'MPC-HC'

        foreach ($k in $vals.Keys) {
            $type = if ($vals[$k] -is [string]) { 'String' } else { 'DWord' }
            Set-ItemProperty -Path $MPC_KEY -Name $k -Value $vals[$k] -Type $type
        }
        Say "MPC-HC: dark theme on, OSD set to $osdFont 16, zero transparency, bordered." 'Green'
        Invoke-TargetCommit 'mpchc' 'MPC-HC' {
            Set-ManifestEntry 'mpchc' 'n/a' $MPC_KEY 'n/a' (Get-PayloadVersion)
        } {
            # The backup holds the EXACT pre-apply values; re-import restores them.
            & reg import $bak 2>&1 | Out-Null
        }
        Say '  NOT reachable: the player chrome colours are compiled into MPC-HC and no' 'Yellow'
        Say '  registry value exposes them, so this target cannot take a palette. Only the' 'Yellow'
        Say '  built-in dark theme and the OSD typography are settable.' 'Yellow'
        Say '  MPC-HC rewrites these on exit - close it BEFORE applying, or re-apply after.' 'Yellow'
    }
}

# ─── qBittorrent ─────────────────────────────────────────────────────────────
# Qt6 desktop client. qBittorrent loads an UNPACKED theme when
# General\CustomUIThemePath names a config.json: it then reads that config.json
# plus the stylesheet.qss beside it (FolderThemeSource). That is the mode this
# target uses, deliberately over the packed .qbtheme bundle -- a .qbtheme is a Qt
# Resource Collection file and would need a matching-major-version `rcc` binary on
# the user's machine to produce, which is a compiler dependency for two text files.
#
# The theme is written into the user's own config directory (%APPDATA%\qBittorrent\
# themes\wintage), so a qBittorrent update cannot take it with it. What an update
# CAN do is nothing at all here: the two INI keys and the two files are all this
# target owns.
#
# qBittorrent rewrites its whole INI when it exits, so an edit made while it is
# running is discarded on close. The target refuses to run in that state rather
# than reporting a success the next exit erases.

$script:QBT_OWNED_INI_KEYS = @('General\UseCustomUITheme', 'General\CustomUIThemePath')

# QSettings stores an INI string with backslashes doubled, and qBittorrent's own
# Path type normalises to forward slashes. Both spellings name the same file, so
# the comparison canonicalises before it judges.
function Test-QbtThemePath([string]$value, [string]$expected) {
    if (-not $value) { return $false }
    $v = $value.Trim().Trim('"') -replace '\\\\', '\' -replace '/', '\'
    try { $v = [IO.Path]::GetFullPath($v) } catch { return $false }
    try { $e = [IO.Path]::GetFullPath($expected) } catch { return $false }
    return $v.TrimEnd('\') -eq $e.TrimEnd('\')
}

# A BOM is not cosmetic in a QSettings INI: it would ride in front of the first
# section header and turn `[Preferences]` into a section nobody looks for. The
# file is written back as UTF-8 WITHOUT a BOM, CRLF, exactly as Qt wrote it.
function Write-QbtIni([string]$path, $lines) {
    $l = @($lines)
    while ($l.Count -and $l[-1] -eq '') { $l = if ($l.Count -gt 1) { $l[0..($l.Count - 2)] } else { @() } }
    Write-Utf8 $path (($l -join "`r`n") + "`r`n")
}

function Invoke-Qbittorrent {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not (Test-Path $QBT_INI)) { Assert-TargetResolvable 'qBittorrent' $false; return }
    # Test seam: a fixture redirects APPDATA, so the machine's own running
    # qBittorrent is not the instance that owns the fixture INI and must not
    # block it. Never set outside tests - for a real install the guard is the
    # only thing standing between an applied theme and qBittorrent's exit
    # rewriting the INI back over it.
    $qbtRunning = if ($env:WINTAGE_TEST_ALLOW_RUNNING_QBT) { $null } else { Get-Process qbittorrent -ErrorAction SilentlyContinue }
    if ($qbtRunning) {
        throw 'qBittorrent: close qBittorrent and run this again - it rewrites qBittorrent.ini on exit and would discard the theme selection.'
    }

    $cfgFile = Join-Path $QBT_THEME_DIR 'config.json'
    $qssFile = Join-Path $QBT_THEME_DIR 'stylesheet.qss'

    # CORE-002 discipline: persistent first-touch recovery OUTSIDE the target,
    # recording created-vs-replaced for the theme directory AND the original value
    # (or absence) of every owned INI key. A repaint never overwrites it.
    $recDir = Join-Path $WintageAppData 'recovery\qbittorrent'
    $recMeta = Join-Path $recDir 'recovery.json'
    $pristineDir = Join-Path $recDir 'pristine'

    if ($DoRevert) {
        if (-not (Assert-RevertSource 'qbittorrent' $recMeta 'qBittorrent')) { return }
        if (-not $PSCmdlet.ShouldProcess($QBT_INI, 'Restore the pre-Wintage UI theme selection')) { return }
        $meta = Read-Utf8 $recMeta | ConvertFrom-Json
        $preIni = Save-FilePreState $QBT_INI $null
        $preDir = Save-DirPreState $QBT_THEME_DIR
        $preMarker = Save-FilePreState $QBT_MARKER $null

        $lines = (Read-Utf8 $QBT_INI) -split '\r?\n'
        foreach ($k in $script:QBT_OWNED_INI_KEYS) {
            $orig = if ($meta.ini) { $meta.ini.$k } else { $null }
            if ($null -ne $orig -and "$orig" -ne '') { $lines = Set-IniKey $lines 'Preferences' $k "$orig" }
            else { $lines = Remove-IniKey $lines 'Preferences' $k }
        }
        Write-QbtIni $QBT_INI $lines

        if ($meta.mode -eq 'replaced') {
            if (-not (Test-Path $pristineDir)) { throw "qBittorrent: pristine recovery is missing ($pristineDir) - refusing to delete the live theme directory." }
            # Restore-DirPreState CONSUMES the snapshot it is handed, so it is
            # handed a working copy: the persistent pristine must survive until the
            # manifest transition commits, or a failed transition would leave the
            # revert unretryable (the one copy of the pre-Wintage directory gone).
            $pristineWork = Join-Path $env:TEMP ('wintage-qbt-pristine-' + [guid]::NewGuid().ToString('N'))
            Copy-Item $pristineDir $pristineWork -Recurse -Force
            Restore-DirPreState $QBT_THEME_DIR @{ Existed = $true; SnapshotPath = $pristineWork }
            Say "qBittorrent: restored the pre-Wintage $QBT_THEME_DIR" 'Green'
        } elseif (Test-Path $QBT_THEME_DIR) {
            Remove-Item $QBT_THEME_DIR -Recurse -Force
            Say "qBittorrent: removed $QBT_THEME_DIR (Wintage-created, nothing pre-existed)" 'Green'
        }
        if (Test-Path $QBT_MARKER) { Remove-Item $QBT_MARKER -Force }
        Say 'qBittorrent: restored the previous UI theme selection.' 'Green'

        Invoke-TargetCommit 'qbittorrent' 'qBittorrent' {
            Remove-ManifestEntry 'qbittorrent'
        } {
            Restore-FilePreState $preIni $QBT_INI $null
            Restore-DirPreState $QBT_THEME_DIR $preDir
            Restore-FilePreState $preMarker $QBT_MARKER $null
        }
        # Recovery is consumed ONLY after the manifest transition committed; a
        # failed transition keeps it so a retry can finish the revert.
        Remove-Item ($recMeta + '.provenance.json') -Force -ErrorAction SilentlyContinue
        Remove-Item $recMeta -Force -ErrorAction SilentlyContinue
        if (Test-Path $pristineDir) { Remove-Item $pristineDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($preDir -and $preDir.SnapshotPath -and (Test-Path $preDir.SnapshotPath)) { Remove-Item $preDir.SnapshotPath -Recurse -Force -ErrorAction SilentlyContinue }
        return
    }

    $built = Join-Path $out "qbittorrent/$PaletteSlug"
    $builtCfg = Join-Path $built 'config.json'
    $builtQss = Join-Path $built 'stylesheet.qss'
    if (-not (Test-Path $builtCfg) -or -not (Test-Path $builtQss)) {
        throw "qBittorrent: built output missing for '$PaletteSlug' ($built). Run 'node tools/build-desktop.js'."
    }

    if (-not $PSCmdlet.ShouldProcess($QBT_INI, "Install and select the Wintage $PaletteSlug UI theme")) { return }

    $lines = (Read-Utf8 $QBT_INI) -split '\r?\n'
    if (-not (Test-Path $recMeta)) {
        New-Item -ItemType Directory -Force -Path $recDir | Out-Null
        $mode = if (Test-Path $QBT_THEME_DIR) { 'replaced' } else { 'created' }
        if ($mode -eq 'replaced') {
            if (Test-Path $pristineDir) { Remove-Item $pristineDir -Recurse -Force }
            Copy-Item $QBT_THEME_DIR $pristineDir -Recurse -Force
        }
        $ownedIni = [ordered]@{}
        foreach ($k in $script:QBT_OWNED_INI_KEYS) {
            $v = Get-IniKey $lines 'Preferences' $k
            $ownedIni[$k] = if ($null -ne $v) { "$v" } else { $null }
        }
        Write-Utf8 $recMeta (@{ mode = $mode; target = 'qbittorrent'; ini = $ownedIni; created = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json)
        Write-RecoveryProvenance $recMeta 'qbittorrent'
        Say "qBittorrent: recorded the pre-Wintage theme selection ($mode) -> $recMeta" 'DarkGray'
    }

    $preIni = Save-FilePreState $QBT_INI $null
    $preDir = Save-DirPreState $QBT_THEME_DIR
    $preMarker = Save-FilePreState $QBT_MARKER $null

    New-Item -ItemType Directory -Force -Path $QBT_THEME_DIR | Out-Null
    Copy-Item $builtCfg $cfgFile -Force
    Copy-Item $builtQss $qssFile -Force
    # UI.md law 1: Qt cannot switch antialiasing off, so the FACE carries it.
    # stylesheet.qss names Verdana_m1 first and falls back to Verdana, so this is
    # advice, never a mutation - see the font note at the top of this file.
    Say-WintageFontAdvice 'qBittorrent'

    # Forward slashes: qBittorrent's own Path type normalises to them, and a
    # backslash would have to be written doubled in the INI (QSettings escaping) -
    # one spelling with no escape rule beats two with one.
    $iniPath = $cfgFile -replace '\\', '/'
    $lines = Set-IniKey $lines 'Preferences' 'General\UseCustomUITheme' 'true'
    $lines = Set-IniKey $lines 'Preferences' 'General\CustomUIThemePath' $iniPath
    Write-QbtIni $QBT_INI $lines
    Write-Utf8 $QBT_MARKER $PaletteSlug

    Say "qBittorrent: installed the Wintage $PaletteSlug theme -> $QBT_THEME_DIR" 'Green'
    Invoke-TargetCommit 'qbittorrent' 'qBittorrent' {
        Set-ManifestEntry 'qbittorrent' $PaletteSlug $QBT_INI 'n/a' (Get-PayloadVersion)
    } {
        Restore-FilePreState $preIni $QBT_INI $null
        Restore-DirPreState $QBT_THEME_DIR $preDir
        Restore-FilePreState $preMarker $QBT_MARKER $null
    }
    if ($preDir -and $preDir.SnapshotPath -and (Test-Path $preDir.SnapshotPath)) { Remove-Item $preDir.SnapshotPath -Recurse -Force -ErrorAction SilentlyContinue }
    Say '  Start qBittorrent to see it. Undo: .\install.ps1 -Target qbittorrent -Revert' 'DarkGray'
    Say '  NOT reachable: qBittorrent draws its own toolbar/tray icons from its resource' 'Yellow'
    Say '  bundle, so those keep their stock colours - the palette, the transfer-list state' 'Yellow'
    Say '  colours, the log colours and the Win95 bevel geometry are what this target owns.' 'Yellow'
}

