# Per-target Invoke-* implementations for install.ps1 (T-169 split). Functions here
# run in the calling script's scope, so they see install.ps1's data tables, parameters
# and helpers at call time. Dot-sourced by install.ps1 before the target tables are built.

function Invoke-WindowsTerminal {
    param([switch]$DoRevert, [string]$PaletteSlug)
    $settingsPaths = @(Get-WindowsTerminalSettingsPaths)
    if (-not $settingsPaths.Count) { Say 'Windows Terminal: not installed on this machine - skipped.' 'DarkYellow'; return }
    if (-not $node) { throw 'Windows Terminal: node is required to patch JSON-with-comments safely.' }

    $helper = Join-Path $root 'tools/install-terminal.js'
    $paletteFile = Join-Path $root "themes\$PaletteSlug.json"
    foreach ($settings in $settingsPaths) {
        $args = @($helper, '--settings', $settings)
        if ($DoRevert) { $args += '--revert' } else { $args += @('--palette', $paletteFile) }
        $action = if ($DoRevert) { 'Restore the pre-Wintage settings' } else { "Apply $PaletteSlug + $CONSOLE_FONT to every profile" }
        if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw "Windows Terminal dry-run FAILED ($LASTEXITCODE) - see the message above." }; continue }
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
    if (-not (Test-Path $paletteFile)) { throw "Console Host: theme file not found ($PaletteSlug.json)" }
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

function Invoke-WindowsTheme {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not $node) { throw 'Windows theme: node is required to preserve and merge the active .theme safely.' }
    $current = (Get-ItemProperty $WINDOWS_THEME_KEY -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
    $helper = Join-Path $root 'tools/install-windows-theme.js'
    $built = Join-Path $out "windows/$PaletteSlug/Wintage.theme"
    if (-not $DoRevert -and -not (Test-Path $built)) { throw "No Windows theme build for palette '$PaletteSlug'." }
    if (-not $DoRevert -and (-not $current -or -not (Test-Path $current))) {
        throw 'Windows theme: the active .theme file was not found - refusing to apply because the wallpaper/cursor merge would have nothing to preserve.'
    }

    $args = @($helper, '--themes-dir', $WINDOWS_THEMES_DIR)
    if ($DoRevert) { $args += '--revert' }
    else { $args += @('--theme', $built, '--current-theme', $current, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore the exact pre-Wintage Windows theme snapshot' } else { "Merge and activate Wintage $PaletteSlug, preserving wallpaper/sounds and selecting ___CURRENT___ cursors" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw 'Windows theme dry-run FAILED - see the message above.' }; return }
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
    if (-not $activated) { throw 'Windows: theme activation was dispatched but Windows did not confirm it after both attempts - the palette may be only partly applied, so the manifest was NOT updated. Re-run to retry.' }
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
        'WIN95_SURFACE'      = '(?m)^WIN95_SURFACE\s*=\s*''[^'']+'''
        'WIN95_SURFACE_RAISED' = '(?m)^WIN95_SURFACE_RAISED\s*=\s*''[^'']+'''
        'WIN95_SURFACE_ALT'  = '(?m)^WIN95_SURFACE_ALT\s*=\s*''[^'']+'''
        'WIN95_BEVEL_HI'     = '(?m)^WIN95_BEVEL_HI\s*=\s*''[^'']+'''
        'WIN95_BEVEL_SH'     = '(?m)^WIN95_BEVEL_SH\s*=\s*''[^'']+'''
        'WIN95_BORDER_MUTED' = '(?m)^WIN95_BORDER_MUTED\s*=\s*''[^'']+'''
        'WIN95_TEXT'         = '(?m)^WIN95_TEXT\s*=\s*''[^'']+'''
        'WIN95_TEXT_DIM'     = '(?m)^WIN95_TEXT_DIM\s*=\s*''[^'']+'''
        'WIN95_TEXT_MUTED'   = '(?m)^WIN95_TEXT_MUTED\s*=\s*''[^'']+'''
        'WIN95_GOLD'         = '(?m)^WIN95_GOLD\s*=\s*''[^'']+'''
        'WIN95_GOLD_LIGHT'   = '(?m)^WIN95_GOLD_LIGHT\s*=\s*''[^'']+'''
        'WIN95_GOLD_DIM'     = '(?m)^WIN95_GOLD_DIM\s*=\s*''[^'']+'''
        'WIN95_GOLD_DARK'    = '(?m)^WIN95_GOLD_DARK\s*=\s*''[^'']+'''
        'WIN95_RED'          = '(?m)^WIN95_RED\s*=\s*''[^'']+'''
        'WIN95_DANGER'       = '(?m)^WIN95_DANGER\s*=\s*''[^'']+'''
        'WIN95_GREEN'        = '(?m)^WIN95_GREEN\s*=\s*''[^'']+'''
        'WIN95_BUTTON'       = '(?m)^WIN95_BUTTON\s*=\s*''[^'']+'''
        'WIN95_BUTTON_HOVER' = '(?m)^WIN95_BUTTON_HOVER\s*=\s*''[^'']+'''
        'WIN95_ENTRY'        = '(?m)^WIN95_ENTRY\s*=\s*''[^'']+'''
        'WIN95_SCROLL'       = '(?m)^WIN95_SCROLL\s*=\s*''[^'']+'''
        'WIN95_SCROLL_HOVER' = '(?m)^WIN95_SCROLL_HOVER\s*=\s*''[^'']+'''
    }
    $values = [ordered]@{
        'WIN95_BG'           = $t.background
        'WIN95_BG_SOFT'      = $t.backgroundSoft
        'WIN95_SURFACE'      = $t.surface
        'WIN95_SURFACE_RAISED' = $t.surfaceRaised
        'WIN95_SURFACE_ALT'  = $t.surfaceAlt
        'WIN95_BEVEL_HI'     = $t.bevelLight
        'WIN95_BEVEL_SH'     = $t.borderDark
        'WIN95_BORDER_MUTED' = $t.borderMuted
        'WIN95_TEXT'         = $t.textPrimary
        'WIN95_TEXT_DIM'     = $t.textSecondary
        'WIN95_TEXT_MUTED'   = $t.textMuted
        'WIN95_GOLD'         = $t.textPrimary
        'WIN95_GOLD_LIGHT'   = $t.borderHighlight
        'WIN95_GOLD_DIM'     = $t.textSecondary
        'WIN95_GOLD_DARK'    = $t.textMuted
        'WIN95_RED'          = $t.danger
        'WIN95_DANGER'       = $t.danger
        'WIN95_GREEN'        = $t.success
        'WIN95_BUTTON'       = $t.surfaceRaised
        'WIN95_BUTTON_HOVER' = $t.surfaceAlt
        'WIN95_ENTRY'        = $t.background
        'WIN95_SCROLL'       = $t.surfaceRaised
        'WIN95_SCROLL_HOVER' = $t.surfaceAlt
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

    # The pre-Wintage backup is taken ONCE and never overwritten (same discipline
    # as WildRift and TotalCmd). Copying the live file over it on every Apply
    # destroyed the rollback snapshot after the first repaint, so A -> B -> Revert
    # restored B, not the original (T-187). Taken AFTER validation so a rejected
    # patch leaves no trace at all.
    if (-not (Test-Path $bakFile)) { Copy-Item $pyFile $bakFile -Force }
    
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
    Set-ManifestEntry 'wildrift' $PaletteSlug $pyFile 'n/a' (Get-PayloadVersion)
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

        Write-Utf8 $cssFile $text

        # Zero tokens recoloured means the write was a no-op wearing an install's
        # clothes: same bytes on disk, "installed" in the log, manifest advanced.
        # That is the exact silent-false-success the patch gates exist to stop.
        if ($applied.Count -eq 0) {
            throw 'SAIPENVIEW: no --token declarations matched in style.css - refusing to write an unchanged file as an install; check that the CSS is the one this theme expects.'
        }

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
        $built = Join-Path $out "betterdiscord/$PaletteSlug/wintage.theme.css"
        if (-not (Test-Path $built)) { throw "Built BetterDiscord output missing for '$PaletteSlug'. Run 'node tools/build-desktop.js'." }
        Copy-Item $built $bdCss -Force
        Say "BetterDiscord: installed theme -> $bdCss" 'Green'
        Set-ManifestEntry 'discord' $PaletteSlug $bdCss 'n/a' (Get-PayloadVersion)
    }
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

function Invoke-Obs {
    param([switch]$DoRevert, [string]$PaletteSlug)

    if (-not (Test-Path $OBS_CONFIG)) { Say 'OBS Studio: not installed (no obs-studio profile) - skipped.' 'DarkYellow'; return }
    if (Get-Process obs64 -ErrorAction SilentlyContinue) {
        throw 'OBS Studio: close OBS and Apply again so it cannot overwrite user.ini on exit.'
    }
    if (-not $node) { throw 'OBS Studio: node is required to patch user.ini safely.' }

    $helper = Join-Path $root 'tools/install-obs.js'
    $theme = Join-Path $out "obs/$PaletteSlug/Wintage.ovt"
    if (-not $DoRevert -and -not (Test-Path $theme)) { throw "No OBS build for palette '$PaletteSlug'." }
    $args = @($helper, '--config', $OBS_CONFIG)
    if ($DoRevert) { $args += '--revert' } else { $args += @('--theme', $theme, '--palette', $PaletteSlug) }
    $action = if ($DoRevert) { 'Restore previous OBS theme and selection' } else { "Install and activate Wintage $PaletteSlug" }
    if ($WhatIfPreference) { & node ($args + '--dry-run'); if ($LASTEXITCODE -ne 0) { throw 'OBS Studio dry-run FAILED - see the message above.' }; return }
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
            if ($LASTEXITCODE -ne 0) {
                throw "MPC-HC: reg import failed ($LASTEXITCODE) -- values were NOT restored. The manifest and backup are kept so a retry or manual reg import can still recover."
            }
            Say "MPC-HC: restored the captured values from $bak" 'Green'
            Remove-ManifestEntry 'mpchc'
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
        Set-ManifestEntry 'mpchc' 'n/a' $MPC_KEY 'n/a' (Get-PayloadVersion)
        Say '  NOT reachable: the player chrome colours are compiled into MPC-HC and no' 'Yellow'
        Say '  registry value exposes them, so this target cannot take a palette. Only the' 'Yellow'
        Say '  built-in dark theme and the OSD typography are settable.' 'Yellow'
        Say '  MPC-HC rewrites these on exit - close it BEFORE applying, or re-apply after.' 'Yellow'
    }
}
