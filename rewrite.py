import re

with open('desktop/install.ps1', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Update param block
text = text.replace(
    "[ValidateSet('antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'codenomad', 'mpchc', 'discord', 'totalcmd', 'totalcmd2', 'obsidian', 'saipenview', 'all')]",
    "[ValidateSet('antigravity', 'vscode', 'claude', 'freebuff', 'antigravity-app', 'codenomad', 'mpchc', 'discord', 'totalcmd', 'totalcmd2', 'obsidian', 'saipenview', 'smartvac', 'wildrift', 'all')]"
)

text = text.replace(
    "[string]$SaipenviewPath = 'v:\\___VAC\\__K\\__CODE\\_PY\\_SAIPENVIEW\\'",
    "[string]$SaipenviewPath = 'v:\\___VAC\\__K\\__CODE\\_PY\\_SAIPENVIEW\\',\n    [string]$SmartVacPath = 'v:\\___VAC\\__K\\__CODE\\_PY\\_SMART_VAC_CLEANER\\',\n    [string]$WildRiftPath = 'v:\\___VAC\\__K\\__CODE\\_PY\\_WR\\WildRiftAssistant\\'"
)

# 2. Add Invoke- functions
invoke_funcs = r'''function Invoke-SmartVac {
    param([switch]$DoRevert, [string]$PaletteSlug)
    if (-not (Test-Path $SmartVacPath)) { Say "SMART VAC CLEANER: not found at $SmartVacPath" 'DarkYellow'; return }
    $themeFile = Join-Path $SmartVacPath 'wintage-theme.json'
    
    if ($DoRevert) {
        if (Test-Path $themeFile) {
            Remove-Item $themeFile -Force
            Say "SMART VAC CLEANER: removed wintage-theme.json" 'Green'
        } else {
            Say "SMART VAC CLEANER: nothing to revert." 'DarkYellow'
        }
        return
    }
    
    $json = Get-Content (Join-Path $root "themes/$PaletteSlug.json") -Raw
    Set-Content $themeFile $json -Encoding UTF8
    Say "SMART VAC CLEANER: installed theme -> $themeFile" 'Green'
}

function Invoke-WildRift {
    param([switch]$DoRevert, [string]$PaletteSlug)
    if (-not (Test-Path $WildRiftPath)) { Say "WildRiftAssistant: not found at $WildRiftPath" 'DarkYellow'; return }
    
    $pyFile = Join-Path $WildRiftPath 'theme.py'
    $bakFile = Join-Path $WildRiftPath 'theme.py.bak'
    if (-not (Test-Path $pyFile)) { Say "WildRiftAssistant: theme.py not found" 'DarkYellow'; return }
    
    if ($DoRevert) {
        if (Test-Path $bakFile) {
            Copy-Item $bakFile $pyFile -Force
            Remove-Item $bakFile -Force
            Say "WildRiftAssistant: restored from backup" 'Green'
        } else {
            Say "WildRiftAssistant: nothing to revert." 'DarkYellow'
        }
        return
    }
    
    if (-not (Test-Path $bakFile)) {
        Copy-Item $pyFile $bakFile -Force
    }
    $json = Get-Content (Join-Path $root "themes/$PaletteSlug.json") -Raw | ConvertFrom-Json
    $pyTokens = "TOKENS = {`r`n"
    foreach ($p in $json.tokens.psobject.properties) {
        $pyTokens += "    `"$($p.Name)`": `"$($p.Value)`",`r`n"
    }
    $pyTokens += "}"
    $code = Get-Content $bakFile -Raw
    $code = $code -replace '(?s)TOKENS\s*=\s*\{.*?\}', $pyTokens
    Set-Content $pyFile $code -Encoding UTF8
    Say "WildRiftAssistant: installed theme -> $pyFile" 'Green'
}

function Invoke-Saipenview {'''

text = text.replace("function Invoke-Saipenview {", invoke_funcs)

# 3. Update status blocks (replace ALL occurrences of the saipenview status block)
status_old = r'''    $svCss = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css'
    $svBak = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css.bak'
    $sv = if (Test-Path $SaipenviewPath) {
        if (Test-Path $svBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'saipenview', 'SAIPENVIEW', $sv, '-')'''

status_new = r'''    $svCss = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css'
    $svBak = Join-Path $SaipenviewPath 'saipenview\ui\static\style.css.bak'
    $sv = if (Test-Path $SaipenviewPath) {
        if (Test-Path $svBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'saipenview', 'SAIPENVIEW', $sv, '-')

    $smTheme = Join-Path $SmartVacPath 'wintage-theme.json'
    $sm = if (Test-Path $SmartVacPath) {
        if (Test-Path $smTheme) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'smartvac', 'SMART VAC CLEANER', $sm, '-')

    $wrBak = Join-Path $WildRiftPath 'theme.py.bak'
    $wr = if (Test-Path $WildRiftPath) {
        if (Test-Path $wrBak) { 'themed' } else { 'found, not themed' }
    } else { 'not installed' }
    Say ("  {0,-16} {1,-38} {2,-22} {3}" -f 'wildrift', 'WildRiftAssistant', $wr, '-')'''

text = text.replace(status_old, status_new)

# 4. Update the target list
text = text.replace(
    "@('mpchc', 'saipenview') }",
    "@('mpchc', 'saipenview', 'smartvac', 'wildrift') }"
)

# 5. Update execution loop
loop_old = "if ($name -eq 'saipenview') { Invoke-Saipenview -DoRevert:$Revert -PaletteSlug $Palette; continue }"
loop_new = "if ($name -eq 'saipenview') { Invoke-Saipenview -DoRevert:$Revert -PaletteSlug $Palette; continue }\n    if ($name -eq 'smartvac') { Invoke-SmartVac -DoRevert:$Revert -PaletteSlug $Palette; continue }\n    if ($name -eq 'wildrift') { Invoke-WildRift -DoRevert:$Revert -PaletteSlug $Palette; continue }"
text = text.replace(loop_old, loop_new)

with open('desktop/install.ps1', 'w', encoding='utf-8') as f:
    f.write(text)
