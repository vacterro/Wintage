# i18n loader — shared between install.ps1 (CLI) and WintageInstaller.ps1 (GUI).
# Both dot-source this file; it has no param block, so it leaks nothing into the
# caller's scope and never runs any installer logic. The GUI loading only the
# language machinery without importing install.ps1's whole target pipeline was
# the T-157 defect; this file is the fix.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Read-Utf8([string]$path) { [System.IO.File]::ReadAllText($path, $script:Utf8NoBom) }

$script:LocalesDir = Join-Path $PSScriptRoot 'locales'

function Read-I18n($locale) {
    $file = Join-Path $script:LocalesDir "$locale.json"
    if (-not (Test-Path $file)) { return @{} }
    $ht = @{}
    try {
        $obj = (Read-Utf8 $file) | ConvertFrom-Json
        foreach ($prop in $obj.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
    } catch { }
    return $ht
}

function Load-I18n($preferredLocale) {
    $script:i18n = Read-I18n 'en'
    if ($preferredLocale -and $preferredLocale -ne 'en') {
        $overlay = Read-I18n $preferredLocale
        foreach ($k in $overlay.Keys) { $script:i18n[$k] = $overlay[$k] }
    }
}

function T($key) {
    if ($script:i18n -and $script:i18n.ContainsKey($key)) { return $script:i18n[$key] }
    return $key
}

Load-I18n ((Get-Culture).TwoLetterISOLanguageName)
