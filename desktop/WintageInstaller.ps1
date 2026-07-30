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
[System.Windows.Forms.Application]::EnableVisualStyles() | Out-Null

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$themeDir = Join-Path $root 'themes'

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ PALETTE LOADING Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
$script:packs = @{}
function Load-Packs {
    $script:packs = @{}
    Get-ChildItem $themeDir -Filter '*.json' | ForEach-Object {
        $p = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $script:packs[$p.slug] = $p
    }
}
Load-Packs
$script:current = if ($script:packs.ContainsKey('golden')) { 'golden' } else { ($script:packs.Keys | Select-Object -First 1) }
# The custom palette is a working copy, seeded from whatever is selected, so
# "Custom" always starts from something that already looks right instead of black.
$script:custom = $null

$TOKENS = @(
    'background', 'backgroundSoft',
    'surface', 'surfaceRaised', 'surfaceAlt',
    'borderDark', 'borderHighlight', 'borderMuted',
    'textPrimary', 'textSecondary', 'textMuted',
    'accentTeal', 'accentTealDeep',
    'success', 'warning', 'danger',
    'selection', 'compareBack', 'link'
)

function Get-ActiveTokens {
    if ($script:current -eq '<custom>') { return $script:custom }
    $t = $script:packs[$script:current].tokens
    $h = @{}
    foreach ($k in $TOKENS) { $h[$k] = $t.$k }
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

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ WIN95 DRAWING Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
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

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ FORM Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
$form = New-Object Windows.Forms.Form
$form.Text = 'Wintage Theme Installer'
$form.Size = New-Object Drawing.Size(880, 620)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = $FONT

# Theme list ------------------------------------------------------------------
$lblThemes = New-Object Windows.Forms.Label
$lblThemes.Text = 'THEME'; $lblThemes.Location = '12,10'; $lblThemes.Size = '200,16'; $lblThemes.Font = $FONTB
$lstThemes = New-Object Windows.Forms.ListBox
$lstThemes.Location = '12,28'; $lstThemes.Size = '200,300'
$lstThemes.BorderStyle = 'FixedSingle'
$lstThemes.DrawMode = 'OwnerDrawFixed'
$lstThemes.ItemHeight = 18
$lstThemes.IntegralHeight = $false

# Targets ---------------------------------------------------------------------
$lblTargets = New-Object Windows.Forms.Label
$lblTargets.Text = 'APPLY TO'; $lblTargets.Location = '12,338'; $lblTargets.Size = '200,16'; $lblTargets.Font = $FONTB
$clbTargets = New-Object Windows.Forms.CheckedListBox
$clbTargets.Location = '12,356'; $clbTargets.Size = '200,146'
$clbTargets.BorderStyle = 'FixedSingle'
$clbTargets.CheckOnClick = $true
$clbTargets.IntegralHeight = $false

$script:customPaths = @{}
$clbTargets.Add_ItemCheck({
    param($sender, $e)
    if ($e.NewValue -eq 'Checked') {
        $item = $clbTargets.Items[$e.Index]
        $key = ($item -split '\s+')[0]
        if ($key -in @('saipenview', 'smartvac', 'wildrift')) {
            $defaults = @{
                'saipenview' = 'v:\___VAC\__K\__CODE\_PY\_SAIPENVIEW\'
                'smartvac' = 'v:\___VAC\__K\__CODE\_PY\_SMART_VAC_CLEANER\'
                'wildrift' = 'v:\___VAC\__K\__CODE\_PY\_WR\WildRiftAssistant\'
            }
            $dlg = New-Object Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Select folder for $key"
            $dlg.SelectedPath = $defaults[$key]
            if ($dlg.ShowDialog() -eq 'OK') {
                $script:customPaths[$key] = $dlg.SelectedPath
            } else {
                $e.NewValue = 'Unchecked'
            }
        }
    }
})

$btnSelectAll = New-Object Windows.Forms.Button
$btnSelectAll.Text = 'ALL'; $btnSelectAll.Location = '12,508'; $btnSelectAll.Size = '96,24'; $btnSelectAll.Font = $FONT
$btnSelectAll.FlatStyle = 'Flat'; $btnSelectAll.FlatAppearance.BorderSize = 0

$btnSelectNone = New-Object Windows.Forms.Button
$btnSelectNone.Text = 'NONE'; $btnSelectNone.Location = '116,508'; $btnSelectNone.Size = '96,24'; $btnSelectNone.Font = $FONT
$btnSelectNone.FlatStyle = 'Flat'; $btnSelectNone.FlatAppearance.BorderSize = 0

# Preview ---------------------------------------------------------------------
$lblPreview = New-Object Windows.Forms.Label
$lblPreview.Text = 'PREVIEW'; $lblPreview.Location = '226,10'; $lblPreview.Size = '200,16'; $lblPreview.Font = $FONTB
$preview = New-Object Windows.Forms.Panel
$preview.Location = '226,28'; $preview.Size = '400,300'

# Swatches --------------------------------------------------------------------
$lblTokens = New-Object Windows.Forms.Label
$lblTokens.Text = 'COLOURS  (click a swatch to change - switches to Custom)'
$lblTokens.Location = '226,338'; $lblTokens.Size = '420,16'; $lblTokens.Font = $FONTB
$swatchPanel = New-Object Windows.Forms.Panel
$swatchPanel.Location = '226,356'; $swatchPanel.Size = '400,180'
$swatchPanel.AutoScroll = $true

# Right column ----------------------------------------------------------------
$lblInfo = New-Object Windows.Forms.Label
$lblInfo.Location = '640,28'; $lblInfo.Size = '212,300'; $lblInfo.Font = $FONT

$btnApply = New-Object Windows.Forms.Button
$btnApply.Text = 'APPLY'; $btnApply.Location = '640,356'; $btnApply.Size = '212,34'; $btnApply.Font = $FONTB
$btnApply.FlatStyle = 'Flat'; $btnApply.FlatAppearance.BorderSize = 0

$btnSave = New-Object Windows.Forms.Button
$btnSave.Text = 'SAVE'; $btnSave.Location = '640,396'; $btnSave.Size = '104,26'
$btnSave.FlatStyle = 'Flat'; $btnSave.FlatAppearance.BorderSize = 0

$btnDelCustom = New-Object Windows.Forms.Button
$btnDelCustom.Text = 'DEL CUSTOM'; $btnDelCustom.Location = '748,396'; $btnDelCustom.Size = '104,26'
$btnDelCustom.FlatStyle = 'Flat'; $btnDelCustom.FlatAppearance.BorderSize = 0

$btnRevert = New-Object Windows.Forms.Button
$btnRevert.Text = 'REVERT SELECTED TARGETS'; $btnRevert.Location = '640,428'; $btnRevert.Size = '212,26'
$btnRevert.FlatStyle = 'Flat'; $btnRevert.FlatAppearance.BorderSize = 0

$log = New-Object Windows.Forms.TextBox
$log.Location = '640,460'; $log.Size = '212,76'
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true
$log.BorderStyle = 'FixedSingle'

$status = New-Object Windows.Forms.Label
$status.Location = '12,546'; $status.Size = '840,26'

$form.Controls.AddRange(@($lblThemes, $lstThemes, $lblTargets, $clbTargets, $btnSelectAll, $btnSelectNone, $lblPreview, $preview,
        $lblTokens, $swatchPanel, $lblInfo, $btnApply, $btnSave, $btnDelCustom, $btnRevert, $log, $status))

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ TARGET DISCOVERY Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
# Read from install.ps1's own listing rather than duplicated here: one source of
# truth for what exists on this machine, and a target added there shows up here
# without a second edit.
$script:targets = @()
function Load-Targets {
    $clbTargets.Items.Clear()
    $script:targets = @()
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install.ps1') 2>&1
    foreach ($line in $out) {
        if ($line -match '^\s{2}(\S+)\s{2,}(.+?)\s{2,}(not installed|themed|found, not themed|fused shut)\s{2,}(.+)$') {
            $t = [pscustomobject]@{ Key = $Matches[1]; Name = $Matches[2].Trim(); State = $Matches[3]; Palette = $Matches[4].Trim() }
            if ($t.Key -eq 'target') { continue }
            $script:targets += $t
            $label = '{0,-16} {1}' -f $t.Key, $t.State
            [void]$clbTargets.Items.Add($label)
            $i = $clbTargets.Items.Count - 1
            # Pre-check what is installable and already themed; leave the rest alone
            # so Apply never silently touches something the user did not ask for.
            if ($t.State -eq 'themed' -and $t.Key -notin @('saipenview', 'smartvac', 'wildrift')) { $clbTargets.SetItemChecked($i, $true) }
        }
    }
    [void]$clbTargets.Items.Add('userscript      (Tampermonkey)')
    $clbTargets.SetItemChecked($clbTargets.Items.Count - 1, $true)
}

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ RENDERING Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
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

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ ACTIONS Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
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
    & node (Join-Path $root 'tools/build-desktop.js') | Out-Null
    Load-Packs
}

function Delete-Custom {
    $file = Join-Path $themeDir 'custom.json'
    if (Test-Path $file) {
        Remove-Item $file -Force
        Say-Log "deleted themes/custom.json"
        & node (Join-Path $root 'tools/apply-themes.js') | Out-Null
        & node (Join-Path $root 'tools/build-desktop.js') | Out-Null
        Load-Packs
        $script:current = 'golden'
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
            $checked = @()
            foreach ($i in $clbTargets.CheckedIndices) { $checked += $clbTargets.Items[$i] }
            if (-not $checked) { Say-Log 'nothing selected'; return }
            foreach ($item in $checked) {
                $key = ($item -split '\s+')[0]
                if ($key -eq 'userscript') {
                    & node (Join-Path $root 'tools/apply-themes.js') | Out-Null
                    Say-Log 'userscript: themes written (pick it from the Tampermonkey menu)'
                    continue
                }
                $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here 'install.ps1'), "-Target", $key, "-Palette", $slug)
                if ($key -eq 'saipenview' -and $script:customPaths.ContainsKey('saipenview')) { $argsList += @("-SaipenviewPath", $script:customPaths['saipenview']) }
                if ($key -eq 'smartvac' -and $script:customPaths.ContainsKey('smartvac')) { $argsList += @("-SmartVacPath", $script:customPaths['smartvac']) }
                if ($key -eq 'wildrift' -and $script:customPaths.ContainsKey('wildrift')) { $argsList += @("-WildRiftPath", $script:customPaths['wildrift']) }
                $out = & powershell $argsList 2>&1
                $last = ($out | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
                Say-Log ("{0}: {1}" -f $key, $last)
            }
            Load-Targets
            $status.Text = "Applied '$slug'. Restart any app that was themed."
        }
        catch { Say-Log ('APPLY FAILED: ' + $_.Exception.Message) }
        finally { $btnApply.Enabled = $true }
    })

$btnSelectAll.Add_Click({
        for ($i = 0; $i -lt $script:targets.Count; $i++) {
            $state = $script:targets[$i].State
            if ($state -eq 'not installed' -or $state -eq 'fused shut') { continue }
            $clbTargets.SetItemChecked($i, $true)
        }
        if ($clbTargets.Items.Count -gt $script:targets.Count) {
            $clbTargets.SetItemChecked($clbTargets.Items.Count - 1, $true)
        }
    })
$btnSelectNone.Add_Click({
        for ($i = 0; $i -lt $clbTargets.Items.Count; $i++) { $clbTargets.SetItemChecked($i, $false) }
    })

$btnRevert.Add_Click({
        foreach ($i in $clbTargets.CheckedIndices) {
            $key = (($clbTargets.Items[$i]) -split '\s+')[0]
            if ($key -eq 'userscript') { continue }
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

# Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ SKIN THE INSTALLER ITSELF Р Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљР Р†РІР‚СњР вЂљ
# The window wears the palette it is about to install. It is the fastest possible
# preview and it also keeps the tool honest: a palette that makes this window
# unreadable is one you can see is unreadable.
function Skin-Self {
    $t = Get-ActiveTokens
    if (-not $t) { return }
    $form.BackColor = C $t.background
    $form.ForeColor = C $t.textPrimary
    foreach ($c in @($lblThemes, $lblTargets, $lblPreview, $lblTokens, $lblInfo, $status)) {
        $c.BackColor = C $t.background; $c.ForeColor = C $t.textPrimary
    }
    foreach ($c in @($lstThemes, $clbTargets, $log)) {
        $c.BackColor = C $t.compareBack; $c.ForeColor = C $t.textPrimary
    }
    foreach ($b in @($btnApply, $btnSave, $btnDelCustom, $btnRevert, $btnSelectAll, $btnSelectNone)) {
        $b.BackColor = C $t.surfaceRaised; $b.ForeColor = C $t.textPrimary
        $b.FlatAppearance.BorderColor = C $t.borderHighlight
        $b.FlatAppearance.BorderSize = 2
    }
    $swatchPanel.BackColor = C $t.backgroundSoft
}

Load-Targets
foreach ($p in ($script:packs.Values | Sort-Object { $_.order }, { $_.slug })) { [void]$lstThemes.Items.Add($p.label) }
[void]$lstThemes.Items.Add('Custom')
$lstThemes.SelectedItem = $script:packs[$script:current].label
Refresh-Swatches
Update-Info
Skin-Self
$lstThemes.Add_SelectedIndexChanged({ Skin-Self })
$status.Text = 'Pick a theme, tick the targets, press APPLY. Editing any colour forks it into Custom.'

[void]$form.ShowDialog()

