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

# ---- PALETTE LOADING ----
$script:packs = @{}
function Load-Packs {
    $script:packs = @{}
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

$TOKENS = @(
    'background', 'backgroundSoft',
    'surface', 'surfaceRaised', 'surfaceAlt',
    'borderDark', 'borderHighlight', 'bevelLight', 'borderMuted',
    'textPrimary', 'textSecondary', 'textMuted',
    'accentTeal', 'accentTealDeep',
    'success', 'warning', 'danger', 'dangerText',
    'selection', 'compareBack', 'link'
)

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
    $tl = if ($raised) { $light } else { $dark }
    $br = if ($raised) { $dark } else { $light }
    for ($i = 0; $i -lt 2; $i++) {
        $g.DrawLine((New-Object Drawing.Pen $tl), $rect.Left + $i, $rect.Top + $i, $rect.Right - 1 - $i, $rect.Top + $i)
        $g.DrawLine((New-Object Drawing.Pen $tl), $rect.Left + $i, $rect.Top + $i, $rect.Left + $i, $rect.Bottom - 1 - $i)
        $g.DrawLine((New-Object Drawing.Pen $br), $rect.Left + $i, $rect.Bottom - 1 - $i, $rect.Right - 1 - $i, $rect.Bottom - 1 - $i)
        $g.DrawLine((New-Object Drawing.Pen $br), $rect.Right - 1 - $i, $rect.Top + $i, $rect.Right - 1 - $i, $rect.Bottom - 1 - $i)
    }
}

$FONT = New-Object Drawing.Font('Verdana', 8.25, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Point)
$FONTB = New-Object Drawing.Font('Verdana', 8.25, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Point)

# ---- FORM ----
$form = New-Object Windows.Forms.Form
$form.Text = (T 'WintageInstallerTitle')
$form.Size = New-Object Drawing.Size(880, 620)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = $FONT
$form.AutoScroll = $true
$work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($form.Width -gt $work.Width -or $form.Height -gt $work.Height) {
    $form.Size = New-Object Drawing.Size ([Math]::Min(880, $work.Width)), ([Math]::Min(620, $work.Height))
}

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
$MY_APP_KEYS = @('codenomad', 'saipenview', 'smartvac', 'wildrift')
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
# Three targets patch a source file in a checkout, so only the user knows where it
# is. Asking was correct; asking EVERY TIME was not -- the answer does not change
# between runs, and re-picking the same folder to tick the same box is the kind of
# friction that makes someone stop using the installer.
#
# Stored under %APPDATA%, deliberately NOT beside the script: the repo is a git
# checkout that gets pulled, moved and re-cloned, and a per-machine preference has
# no business in it (nor in .gitignore, where it would be one more thing to
# remember). A remembered folder that no longer exists is dropped on load rather
# than trusted, so a moved checkout asks once more instead of silently patching
# nothing.
#
# Right-click a target to change its folder -- that is the whole escape hatch, and
# it is why the dialog no longer opens on tick.
$PATH_TARGETS = @('saipenview', 'smartvac', 'wildrift')
$PATH_DEFAULTS = @{
    'saipenview' = 'v:\___VAC\__K\__CODE\_PY\_SAIPENVIEW\'
    'smartvac'   = 'v:\___VAC\__K\__CODE\_PY\_SMART_VAC_CLEANER\'
    'wildrift'   = 'v:\___VAC\__K\__CODE\_PY\_WR\WildRiftAssistant\'
}
$script:pathsFile = Join-Path $env:APPDATA 'Wintage\paths.json'
$script:customPaths = @{}

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
    try {
        $dir = Split-Path $script:pathsFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $o = [ordered]@{}
        foreach ($k in $PATH_TARGETS) { if ($script:customPaths.ContainsKey($k)) { $o[$k] = $script:customPaths[$k] } }
        [System.IO.File]::WriteAllText($script:pathsFile, ($o | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
    }
    catch {
        $message = "could not save paths.json: $($_.Exception.Message)"
        if (Get-Command Say-Log -CommandType Function -ErrorAction SilentlyContinue) { Say-Log $message }
        else { Write-Warning $message }
        return $false
    }
    return $true
}

# $true if a folder is now known for this target, $false if the user backed out.
function Ask-CustomPath([string]$key) {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select folder for $key"
    $dlg.SelectedPath = if ($script:customPaths.ContainsKey($key)) { $script:customPaths[$key] } else { $PATH_DEFAULTS[$key] }
    if ($dlg.ShowDialog() -ne 'OK') { return $false }
    $script:customPaths[$key] = $dlg.SelectedPath
    Save-CustomPaths
    return $true
}

Load-CustomPaths

$onTargetCheck = {
    param($sender, $e)
    if ($e.NewValue -eq 'Checked') {
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
$chkLogonTask.Add_CheckedChanged({
    $taskArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'install.ps1'))
    if ($chkLogonTask.Checked) {
        & powershell @taskArgs -RegisterLogonTask 2>&1 | ForEach-Object { Say-Log $_ }
    } else {
        & powershell @taskArgs -UnregisterLogonTask 2>&1 | ForEach-Object { Say-Log $_ }
    }
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
$script:fbSoundFile = Join-Path $env:APPDATA 'Wintage\freebuff-sound.txt'
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

function Stop-FbSoundPreview {
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
function Convert-ToPlayableWav([string]$path) {
    # Transcodes ANY audio (ADPCM WAV, MP3, OGG, FLAC, M4A, AAC) to a temp PCM WAV
    # that System.Media.SoundPlayer can always decode. ffmpeg is the one
    # dependency; it is present on this machine (C:\Windows\ffmpeg.exe). Returns
    # the temp path on success, $null on failure. The caller owns the file.
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ff) { return $null }
    $tmp = Join-Path $env:TEMP ("fbpreview_{0}.wav" -f ([guid]::NewGuid().ToString('N')))
    try {
        # 2>$null: with $ErrorActionPreference='Stop' the 2>&1 merge turns native
        # stderr into terminating error records on some 5.1 installs. The exit
        # code below is the real success signal anyway.
        & $ff.Source -y -v error -i $path -acodec pcm_s16le -ar 44100 -ac 2 $tmp 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmp)) { return $tmp }
    }
    catch { }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $null
}

function Play-FbSoundPreview([string]$path) {
    # $true  - preview started; $false - not playable: nothing was started,
    #          caller must not save it
    Stop-FbSoundPreview
    if (-not $path -or -not (Test-Path $path)) { return $false }
    $name = [System.IO.Path]::GetFileName($path)
    $kind = Get-FbAudioKind $path
    if (-not $kind) {
        Say-Log "preview skipped: $name is not a recognized audio file (WAV/MP3/OGG/FLAC/M4A/AAC)"
        return $false
    }
    # Primary path: transcode to PCM WAV and play with SoundPlayer. Reliable for
    # ADPCM WAV and every compressed container even on machines where the WPF
    # MediaPlayer cannot decode at all (MediaFailed fires on plain PCM there).
    $pcm = Convert-ToPlayableWav $path
    if ($pcm) {
        $p = $null
        try {
            $p = New-Object System.Media.SoundPlayer $pcm
            $p.Load()
            # The temp must stay until Stop-FbSoundPreview: Play() re-reads the
            # file even after Load(). $script:fbPreviewTmp makes the teardown the
            # owner of the file, so it cannot leak or die early.
            $script:fbPreviewTmp = $pcm
            $p.Play()   # async - the GUI thread is never blocked
            $script:fbSoundPlayer = $p
            Say-Log "preview: $name"
            return $true
        }
        catch {
            try { if ($p) { $p.Dispose() } } catch { }
            Remove-Item -LiteralPath $pcm -Force -ErrorAction SilentlyContinue
            $script:fbPreviewTmp = $null
            $script:fbSoundPlayer = $null
        }
    }
    # Fallback for machines without ffmpeg: SoundPlayer (PCM WAV only), then the
    # WPF MediaPlayer. SoundPlayer throws on anything it cannot decode (ADPCM,
    # mp3-in-wav, ...); those fall through to MediaPlayer below.
    if ($kind -ceq 'wav') {
        $p = $null
        try {
            $p = New-Object System.Media.SoundPlayer $path
            $p.Load()
            $p.Play()   # async - the GUI thread is never blocked
            $script:fbSoundPlayer = $p
            Say-Log "preview: $name"
            return $true
        }
        catch {
            try { if ($p) { $p.Dispose() } } catch { }
            $script:fbSoundPlayer = $null
            # not PCM after all - fall through to the WPF MediaPlayer
        }
    }
    try {
        $mp = New-Object System.Windows.Media.MediaPlayer
        $script:fbPreviewFailed = $false
        $mp.Add_MediaFailed({ $script:fbPreviewFailed = $true })
        $mp.Open((New-Object System.Uri $path))
        # Open() is asynchronous and MediaPlayer reports decode failures through
        # the MediaFailed event, never through an exception from Play(). Pump
        # the message queue until the media is open (HasAudio) or failed, so the
        # playability gate below is real for non-WAV too - not just a guess.
        $deadline = (Get-Date).AddSeconds(3)
        while (-not $mp.HasAudio -and -not $script:fbPreviewFailed -and (Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        if ($script:fbPreviewFailed -or -not $mp.HasAudio) {
            try { $mp.Close() } catch { }
            Say-Log "preview failed: $name could not be decoded"
            return $false
        }
        $mp.Play()   # async - never blocks the GUI thread
        $script:fbSoundPlayer = $mp
        Say-Log "preview: $name"
        return $true
    }
    catch {
        Say-Log "preview failed: $($_.Exception.Message)"
        return $false
    }
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
        if (-not (Play-FbSoundPreview $dlg.FileName)) { return }
        $script:fbSoundPath = $dlg.FileName
        Save-FbSound
        Update-FbSoundButton
        Say-Log "FreeBuff sound set: $($dlg.FileName)  (applies on the next Apply for freebuff)"
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
$status.Location = '12,546'; $status.Size = '840,26'

$form.Controls.AddRange(@($lblThemes, $lstThemes, $lblMyApps, $clbMyApps, $lblPopularApps, $clbPopularApps, $btnSelectAll, $btnSelectNone, $lblPreview, $preview,
        $lblTokens, $swatchPanel, $lblInfo, $btnApply, $btnSave, $btnDelCustom, $btnRevert, $chkLogonTask, $btnFbSound, $btnFbSoundCopy, $log, $status))
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
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install.ps1') 2>&1
    foreach ($line in $out) {
        if ($line -match '^\s{2}(\S+)\s{2,}(.+?)\s{2,}(not installed|themed|found, not themed|fused shut)\s{2,}(.+)$') {
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
            # ticked, because Apply would only print a refusal for it.
            #
            # The three source-tree targets are ticked only when their folder is already
            # remembered: ticking them otherwise would fire the folder dialog from
            # startup, three times, before the window is even usable.
            $selectable = $t.State -ne 'not installed' -and $t.State -ne 'fused shut'
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
        # A colour chip per row: picking a theme by name alone means opening every
        # one to find out what it looks like.
        if ($slug -and $slug -ne '<custom>') {
            $t = $script:packs[$slug].tokens
            $x = $e.Bounds.Right - 46
            foreach ($k in @('background', 'surfaceRaised', 'borderHighlight', 'textPrimary')) {
                $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.$k)), $x, $e.Bounds.Top + 4, 10, 10)
                $x += 11
            }
        }
        $g.DrawString($text, $FONT, (New-Object Drawing.SolidBrush $e.ForeColor), $e.Bounds.Left + 2, $e.Bounds.Top + 2)
    })

$preview.Add_Paint({
        param($s, $e)
        $t = Get-ActiveTokens
        if (-not $t) { return }
        $g = $e.Graphics
        $g.TextRenderingHint = 'SingleBitPerPixelGridFit'
        $w = $preview.Width; $h = $preview.Height

        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.background)), 0, 0, $w, $h)

        # Title bar
        $bar = New-Object Drawing.Rectangle 8, 8, ($w - 16), 22
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.surface)), $bar)
        Draw-Bevel $g $bar (C $t.borderHighlight) (C $t.borderDark) $true
        $g.DrawString('Wintage', $FONTB, (New-Object Drawing.SolidBrush (C $t.textPrimary)), 14, 12)

        # Window body
        $body = New-Object Drawing.Rectangle 8, 30, ($w - 16), ($h - 38)
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.backgroundSoft)), $body)
        Draw-Bevel $g $body (C $t.borderHighlight) (C $t.borderDark) $false

        $g.DrawString('Primary text on backgroundSoft', $FONT, (New-Object Drawing.SolidBrush (C $t.textPrimary)), 18, 40)
        $g.DrawString('Secondary text', $FONT, (New-Object Drawing.SolidBrush (C $t.textSecondary)), 18, 58)
        $g.DrawString('Muted / disabled', $FONT, (New-Object Drawing.SolidBrush (C $t.textMuted)), 18, 76)
        $g.DrawString('A hyperlink', $FONT, (New-Object Drawing.SolidBrush (C $t.link)), 18, 94)

        # Buttons: raised, pressed, disabled
        $b1 = New-Object Drawing.Rectangle 18, 118, 84, 24
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.surfaceRaised)), $b1)
        Draw-Bevel $g $b1 (C $t.borderHighlight) (C $t.borderDark) $true
        $g.DrawString('OK', $FONT, (New-Object Drawing.SolidBrush (C $t.textPrimary)), 48, 124)

        $b2 = New-Object Drawing.Rectangle 110, 118, 84, 24
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.surface)), $b2)
        Draw-Bevel $g $b2 (C $t.borderHighlight) (C $t.borderDark) $false
        $g.DrawString('Pressed', $FONT, (New-Object Drawing.SolidBrush (C $t.textPrimary)), 122, 124)

        $b3 = New-Object Drawing.Rectangle 202, 118, 84, 24
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.surfaceRaised)), $b3)
        Draw-Bevel $g $b3 (C $t.borderHighlight) (C $t.borderDark) $true
        $g.DrawString('Disabled', $FONT, (New-Object Drawing.SolidBrush (C $t.textMuted)), 210, 124)

        # Sunken input with a selection run
        $inp = New-Object Drawing.Rectangle 18, 152, 268, 22
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.compareBack)), $inp)
        Draw-Bevel $g $inp (C $t.borderHighlight) (C $t.borderDark) $false
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.selection)), 24, 156, 96, 14)
        $g.DrawString('selected text', $FONT, (New-Object Drawing.SolidBrush (C $t.textPrimary)), 24, 155)

        # Scrollbar
        $track = New-Object Drawing.Rectangle 294, 152, 16, 96
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.backgroundSoft)), $track)
        Draw-Bevel $g $track (C $t.borderHighlight) (C $t.borderDark) $false
        $thumb = New-Object Drawing.Rectangle 294, 168, 16, 40
        $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.surfaceRaised)), $thumb)
        Draw-Bevel $g $thumb (C $t.borderHighlight) (C $t.borderDark) $true

        # Semantic swatches - backgrounds only, never text (they fail AA as text)
        $x = 18
        foreach ($k in @('success', 'warning', 'danger')) {
            $r = New-Object Drawing.Rectangle $x, 186, 78, 20
            $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.$k)), $r)
            Draw-Bevel $g $r (C $t.borderHighlight) (C $t.borderDark) $true
            $g.DrawString($k, $FONT, (New-Object Drawing.SolidBrush (C $t.textPrimary)), ($x + 6), 189)
            $x += 86
        }

        # Surface ladder, so the three steps are visible as steps
        $x = 18
        foreach ($k in @('background', 'backgroundSoft', 'surface', 'surfaceRaised', 'surfaceAlt')) {
            $r = New-Object Drawing.Rectangle $x, 216, 52, 26
            $g.FillRectangle((New-Object Drawing.SolidBrush (C $t.$k)), $r)
            Draw-Bevel $g $r (C $t.borderMuted) (C $t.borderDark) $true
            $x += 54
        }
    })

function Refresh-Swatches {
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
    foreach ($k in @('textPrimary', 'textSecondary', 'borderHighlight')) {
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

# ---- ACTIONS ----
function Say-Log($msg) { $log.AppendText($msg + "`r`n"); $log.SelectionStart = $log.TextLength; $log.ScrollToCaret() }

function Save-Custom {
    $t = Get-ActiveTokens
    $pack = [ordered]@{ slug = 'custom'; label = 'Custom'; order = 99; source = 'built in the Wintage Theme Installer'; tokens = [ordered]@{} }
    foreach ($k in $TOKENS) { $pack.tokens[$k] = $t.$k }
    $file = Join-Path $themeDir 'custom.json'
    $json = ($pack | ConvertTo-Json -Depth 5)
    [System.IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding $false))
    Say-Log "saved themes/custom.json"
    & node (Join-Path $root 'tools/apply-themes.js') | Out-Null
    if ($LASTEXITCODE -ne 0) { Say-Log 'WARNING: apply-themes.js failed -- theme packs may be stale'; return }
    & node (Join-Path $root 'tools/build-desktop.js') | Out-Null
    if ($LASTEXITCODE -ne 0) { Say-Log 'WARNING: build-desktop.js failed -- desktop/out may be stale'; return }
    Load-Packs
}

function Delete-Custom {
    $file = Join-Path $themeDir 'custom.json'
    if (Test-Path $file) {
        Remove-Item $file -Force
        Say-Log "deleted themes/custom.json"
        & node (Join-Path $root 'tools/apply-themes.js') | Out-Null
        if ($LASTEXITCODE -ne 0) { Say-Log 'WARNING: apply-themes.js failed -- theme packs may be stale'; return }
        & node (Join-Path $root 'tools/build-desktop.js') | Out-Null
        if ($LASTEXITCODE -ne 0) { Say-Log 'WARNING: build-desktop.js failed -- desktop/out may be stale'; return }
        Load-Packs
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
        try {
            $slug = if ($script:current -eq '<custom>') { Save-Custom; 'custom' } else { $script:current }
            $checked = @(Get-CheckedTargetItems)
            if (-not $checked) { Say-Log 'nothing selected'; return }
            foreach ($item in $checked) {
                $key = ($item -split '\s+')[0]
                $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here 'install.ps1'), "-Target", $key, "-Palette", $slug)
                if ($key -eq 'saipenview' -and $script:customPaths.ContainsKey('saipenview')) { $argsList += @("-SaipenviewPath", $script:customPaths['saipenview']) }
                if ($key -eq 'smartvac' -and $script:customPaths.ContainsKey('smartvac')) { $argsList += @("-SmartVacPath", $script:customPaths['smartvac']) }
                if ($key -eq 'wildrift' -and $script:customPaths.ContainsKey('wildrift')) { $argsList += @("-WildRiftPath", $script:customPaths['wildrift']) }
                $out = & powershell $argsList 2>&1
                $last = ($out | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
                Say-Log ("{0}: {1}" -f $key, $last)
            }
            Load-Targets
            Update-FbButtonsVisibility
            $status.Text = "Applied '$slug'. Restart any app that was themed."
        }
        catch { Say-Log ('APPLY FAILED: ' + $_.Exception.Message) }
        finally { $btnApply.Enabled = $true }
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
        foreach ($item in @(Get-CheckedTargetItems)) {
            $key = (($item) -split '\s+')[0]
            $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here 'install.ps1'), "-Target", $key, "-Revert")
            if ($key -eq 'saipenview' -and $script:customPaths.ContainsKey('saipenview')) { $argsList += @("-SaipenviewPath", $script:customPaths['saipenview']) }
            if ($key -eq 'smartvac' -and $script:customPaths.ContainsKey('smartvac')) { $argsList += @("-SmartVacPath", $script:customPaths['smartvac']) }
            if ($key -eq 'wildrift' -and $script:customPaths.ContainsKey('wildrift')) { $argsList += @("-WildRiftPath", $script:customPaths['wildrift']) }
            $out = & powershell $argsList 2>&1
            Say-Log ("{0}: {1}" -f $key, ($out | Where-Object { $_ -match '\S' } | Select-Object -Last 1))
        }
        Load-Targets
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
    foreach ($c in @($lblThemes, $lblMyApps, $lblPopularApps, $lblPreview, $lblTokens, $lblInfo, $status)) {
        $c.BackColor = C $t.background; $c.ForeColor = C $t.textPrimary
    }
    foreach ($c in @($lstThemes, $clbMyApps, $clbPopularApps, $log)) {
        $c.BackColor = C $t.compareBack; $c.ForeColor = C $t.textPrimary
    }
    foreach ($b in @($btnApply, $btnSave, $btnDelCustom, $btnRevert, $btnFbSound, $btnSelectAll, $btnSelectNone)) {
        $b.BackColor = C $t.surfaceRaised; $b.ForeColor = C $t.textPrimary
        $b.FlatAppearance.BorderColor = C $t.borderHighlight
        $b.FlatAppearance.BorderSize = 2
    }
    $swatchPanel.BackColor = C $t.backgroundSoft
}

Load-Targets
Update-FbButtonsVisibility
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
$status.Text = (T 'StatusHint')

# The folder is asked for once and remembered, so the way to CHANGE it has to be
# discoverable somewhere. A tooltip rather than a longer label: the label is 200px
# wide with the preview panel right beside it, and a clipped hint is no hint.
$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($clbMyApps, "Right-click saipenview / smartvac / wildrift to change its folder." + [Environment]::NewLine + "Asked once, then remembered in $($script:pathsFile).")

# A preview's temp PCM WAV is deleted on teardown; closing the window is the
# last teardown of the session, so sweep it there too.
$form.Add_FormClosed({ Stop-FbSoundPreview })

$existing = Get-ScheduledTask -TaskName 'Wintage Reapply at Logon' -ErrorAction SilentlyContinue
if ($existing) { $chkLogonTask.Checked = $true }

[void]$form.ShowDialog()
