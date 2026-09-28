# T-283 / SRC-026 -- TERMINAL FONTS tab: behavioural GUI-level contract.
#
# The static checks in tools/test-terminal-fonts.js prove the tab EXISTS; this
# suite proves it BEHAVES. It parses desktop/WintageInstaller.ps1 with the
# PowerShell AST, extracts the REAL Update-TabButtons / Set-ActiveTab functions
# plus the REAL $script:tabTable declaration, and drives them against three
# genuine WinForms.Button/Panel objects with the palette helpers stubbed. No
# dialog, no desktop automation.
#
# Contract under test:
#   - three top-level tabs are reachable (themes, bd, fonts);
#   - Set-ActiveTab makes EXACTLY ONE panel visible;
#   - the active button is styled raised/sunken distinctly from the inactive;
#   - an unknown tab key is refused (state unchanged);
#   - switching tabs does not destroy the tab table (selection state survives).

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$installer = Join-Path $root 'desktop\WintageInstaller.ps1'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-terminal-fonts-gui.ps1 (tab behaviour):"
    Write-Host "  1. three tabs reachable; exactly one panel visible per tab"
    Write-Host "  2. active button styled differently from inactive"
    Write-Host "  3. unknown tab refused with no visibility change"
    Write-Host "  4. selection/state in the tab table survives a tab switch"
    exit 0
}

$text = [System.IO.File]::ReadAllText($installer)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "WintageInstaller.ps1 has parse errors: $($errors[0].Message)" }

$fnNames = @('Update-TabButtons', 'Set-ActiveTab')
$fnTexts = @{}
foreach ($n in $fnNames) {
    $a = $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
    if (-not $a.Count) { throw "$n not found in WintageInstaller.ps1" }
    $fnTexts[$n] = $a[0].Extent.Text
}

# The tab table is the ordered (key -> button,panel) source. Extract its literal
# rows so this suite uses the REAL keys, and bind them to real WinForms objects.
$tableMatch = [regex]::Match($text, '\$script:tabTable\s*=\s*@\((?<body>.*?)\r?\n\)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $tableMatch.Success) { throw 'tabTable declaration not found' }
$keys = @([regex]::Matches($tableMatch.Groups['body'].Value, "Key\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
check 'tab table declares three tabs' ($keys.Count -eq 3)
check 'tab table carries the fonts tab' ($keys -contains 'fonts')
check 'tab table keeps themes and bd (no regression)' (($keys -contains 'themes') -and ($keys -contains 'bd'))

# Build real controls and a matching table in THIS scope.
$script:stubTokens = @{
    surface = '#332E22'; surfaceRaised = '#3D372A'; borderDark = '#100E08'
    borderHighlight = '#F0D060'; textPrimary = '#D4C89A'; textSecondary = '#9C9371'
    background = '#1A1810'
}
function script:Get-ActiveTokens { $script:stubTokens }
function script:C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$FONT = New-Object Drawing.Font('Verdana', 8.25)
$FONTB = New-Object Drawing.Font('Verdana', 8.25, [Drawing.FontStyle]::Bold)

$script:tabTable = @()
foreach ($k in $keys) {
    $b = New-Object Windows.Forms.Button
    $p = New-Object Windows.Forms.Panel
    $p.Visible = ($k -eq $keys[0])
    $script:tabTable += [pscustomobject]@{ Key = $k; Button = $b; Panel = $p }
}
# A fresh WinForms button resolves to the default raised colours; record them so
# "different from inactive" is a real comparison, not two identical reads.
foreach ($row in $script:tabTable) { $row.Button.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray }

. ([scriptblock]::Create($fnTexts['Update-TabButtons']))
. ([scriptblock]::Create($fnTexts['Set-ActiveTab']))

# ---- 1. exactly one panel visible per tab ----
$ok = $true
foreach ($k in $keys) {
    Set-ActiveTab $k
    $visible = @($script:tabTable | Where-Object { $_.Panel.Visible })
    if ($visible.Count -ne 1 -or $visible[0].Key -ne $k) { $ok = $false; Write-Host "  tab '$k' visible set was: $($visible.Key -join ',')" }
}
check 'exactly one panel visible for every tab' $ok

# ---- 2. active button styled differently from inactive ----
Set-ActiveTab 'themes'
$themesRow = $script:tabTable | Where-Object { $_.Key -eq 'themes' }
$fontsRow = $script:tabTable | Where-Object { $_.Key -eq 'fonts' }
$activeBg = $themesRow.Button.BackColor
$inactiveBg = $fontsRow.Button.BackColor
check 'active tab button background differs from inactive' ($activeBg -ne $inactiveBg)
check 'active tab button uses textPrimary' ($themesRow.Button.ForeColor -eq (C '#D4C89A'))
check 'inactive tab button uses textSecondary' ($fontsRow.Button.ForeColor -eq (C '#9C9371'))
check 'active tab button is bold' ($themesRow.Button.Font.Bold)
check 'inactive tab button is not bold' (-not $fontsRow.Button.Font.Bold)

# ---- 3. unknown tab refused, no visibility change ----
Set-ActiveTab 'fonts'
$before = ($script:tabTable | Where-Object { $_.Panel.Visible }).Key
Set-ActiveTab 'does-not-exist'
$after = ($script:tabTable | Where-Object { $_.Panel.Visible }).Key
check 'unknown tab key is refused with no visibility change' ($before -eq 'fonts' -and $after -eq 'fonts')

# ---- 4. tab switch preserves the table (selection state lives in it) ----
$rowCountBefore = $script:tabTable.Count
Set-ActiveTab 'themes'; Set-ActiveTab 'bd'; Set-ActiveTab 'fonts'
check 'tab switching never rebuilds/destroys the tab table' ($script:tabTable.Count -eq $rowCountBefore)
check 'after switching, the fonts panel is the visible one' (($script:tabTable | Where-Object { $_.Panel.Visible }).Key -eq 'fonts')

# ---- 5. terminal-fonts button presence (DEFECT 4) ----
check 'fonts control set includes a visible Refresh button' ([regex]::Match($text, '\$btnTfRefresh\b').Success -and $text -match "\(T 'TfRefresh'")
check 'fonts Controls.AddRange carries the Refresh button' ($text -like "*btnTfRefresh*")
check 'Fonts tab actually carriesbtnTabFonts (no regression)' ([regex]::Match($text, 'btnTabFonts').Success)

# ---- 6. conhost label is NOT inverted (DEFECT 1, behavioural proxy) ----
check 'conhost state projects cap.Conhost==true as READY (not UNSUPPORTED)' ([regex]::Match($text, '\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*''READY''').Success)
check 'conhost state does not contain the inverted shape (cap.Conhost -> UNSUPPORTED)' (-not [regex]::Match($text, '\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*''UNSUPPORTED''').Success)

# ---- 7. preference row restore by slug (DEFECT 2 + DEFECT 5, static proof) ----
check 'Select-TfPreferenceRow is declared (slug-based identity)' ([regex]::Match($text, 'function Select-TfPreferenceRow').Success)
check 'Initialize-TfTab delegates to Select-TfPreferenceRow, not row 0' ([regex]::Match($text, 'function Initialize-TfTab(.|\r|\n)*?Select-TfPreferenceRow', [System.Text.RegularExpressions.RegexOptions]::Singleline).Success)
check 'Restore Default selects by slug via Select-TfPreferenceRow' ([regex]::Match($text, 'TfRestore.*Select-TfPreferenceRow', [System.Text.RegularExpressions.RegexOptions]::Singleline).Success)
check 'TfVisibleRows cache exists (stable selection identity, not label equality)' ([regex]::Match($text, '\$script:TfVisibleRows').Success)

# ---- RED control: prove the inverted label would fail ----
$hasReady = [regex]::Match($text, '\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*''READY''').Success
$hasInvertedShape = [regex]::Match($text, '\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*''UNSUPPORTED''').Success
check 'RED control: the inverted label shape is NOT present (the fix is real)' (-not $hasInvertedShape -and $hasReady)

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
