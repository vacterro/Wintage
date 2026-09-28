# saitranslate: render check -- feed the kitchen payload through the REAL installer
# i18n loader (desktop/i18n.ps1) and assert every key resolves to a value, not to its
# own key name. T($key) has no English fallback: a missing key renders the raw key
# name in the GUI, so this is the user-visible failure mode the gate must catch.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$kitchen = Join-Path $PSScriptRoot '..\kitchen\locales'
$en = Get-Content (Join-Path $root 'desktop\locales\en.json') -Raw | ConvertFrom-Json
$keys = @($en.PSObject.Properties.Name)
$new = @('TabThemes', 'TabBetterDiscord', 'BdPlugins', 'BdInstallSelected', 'BdUninstallSelected',
         'BdOpenFolder', 'BdRefresh', 'BdAvailablePlugins', 'BdPluginInfo', 'BdLog', 'BdInstalled',
         'BdAvailable', 'BdStatusReady', 'BdStatusNotFound', 'BdStatusRefreshed', 'BdGoodEmojiDesc',
         'BdRemoveStickersDesc', 'BdRemoveGIFSDesc')
$mine = @('ar','bg','cs','da','de','el','es','fi','fr','he','hi','hr','hu','id','it','ja','ko','nl',
          'no','pl','pt','ro','sk','sv','th','tr','uk','vi','zh')

. (Join-Path $root 'desktop\i18n.ps1')
$script:LocalesDir = (Resolve-Path $kitchen).Path

# Deliberate cognates: the target language genuinely uses the English word, so an
# "still English" hit here is a decision, not a defect. Kept explicit and reviewed.
$cognate = @{
    'da' = @('BdLog')             # Danish 'Log' is the standard word for a log
    'id' = @('BdLog')             # Indonesian uses 'Log' in UI
    'de' = @('TabThemes')         # German Discord says 'Themes & Apps'
}

$pass = 0; $fail = @()
function Check($cond, $msg) { if ($cond) { $script:pass++ } else { $script:fail += $msg } }

foreach ($code in $mine) {
    Load-I18n $code
    Check ($script:i18n.Count -eq 68) "$code loaded $($script:i18n.Count) keys, want 68"
    foreach ($k in $keys) {
        # every key must resolve to something: T has no English fallback, so an empty
        # value renders an empty control
        $v = T $k
        Check ($v -is [string] -and $v.Trim() -ne '') "$code.$k resolved to nothing"
    }
    # the 18 keys THIS package adds must be real translations -- not the key name and not
    # the English source. Pre-existing cognates (Tokens, Info, brand names) are not ours.
    foreach ($k in $new) {
        $v = T $k
        Check ($v -ne $k) "$code.$k unresolved (T returned the key name)"
        if ($cognate[$code] -notcontains $k) {
            Check ($v -ne $en.$k) "$code.$k is still the English source text"
        }
        $want = $k -in @('BdStatusReady', 'BdStatusNotFound')
        Check (($v -match '\{0\}') -eq $want) "$code.$k placeholder state wrong (want={0}: $want)"
    }
    # the two placeholders the code interpolates
    Check ((T 'BdStatusReady') -match '\{0\}') "$code.BdStatusReady lost {0}"
    Check ((T 'BdStatusNotFound') -match '\{0\}') "$code.BdStatusNotFound lost {0}"
    # exactly what the GUI does with a plugin description ($txtBdDetails.Text)
    foreach ($pair in @(@('BdGoodEmojiDesc',14), @('BdRemoveStickersDesc',9), @('BdRemoveGIFSDesc',10))) {
        $text = T $pair[0]
        $lines = $text -split "`r`n"
        Check ($lines.Count -eq $pair[1]) "$code.$($pair[0]) renders $($lines.Count) lines, want $($pair[1])"
        Check ($lines[0] -match 'v1\.0\.0') "$code.$($pair[0]) title line lost its version"
        Check (($lines | Where-Object { $_ -like '  - *' }).Count -eq ($lines | Where-Object { $_ -like '  - *' }).Count -and ($lines | Where-Object { $_ -like '  - *' }).Count -gt 0) "$code.$($pair[0]) lost its bullets"
    }
    Check ((T 'LanguageLabel') -eq 'Language') "$code.LanguageLabel no longer carries SAIT-002's en value"
}

$sw = [System.IO.File]::ReadAllText((Join-Path $kitchen 'ar.json'), (New-Object System.Text.UTF8Encoding($false)))
Check ($sw -notmatch '^\uFEFF') 'locale text is not BOM-free'

"render-check: $pass PASS, $($fail.Count) FAIL over $($mine.Count) locales x $($keys.Count) keys"
$fail | Select-Object -First 12 | ForEach-Object { "  FAIL $_" }
if ($fail.Count -gt 0) { exit 1 }
