[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Palette = 'goldendefault',
    [switch]$ListJson,
    [switch]$Revert,
    [string]$PortableRoot = '',
    [string]$StageRoot = (Join-Path $env:LOCALAPPDATA 'Wintage\browser-theme'),
    [string]$Catalog,
    [switch]$NoLaunch,
    [scriptblock]$ClipboardWriter = { param([string]$Value) Set-Clipboard -Value $Value }
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tampermonkeyId = 'dhdgffkkebhmkfjojejmpbldmpobfkfo'
$userscriptUrl = 'https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js'
$tampermonkeyUrl = "https://chromewebstore.google.com/detail/tampermonkey/$tampermonkeyId"
$script:browsers = @()

function Add-Browser([string]$name, [string]$exe, [string]$userData) {
    if (-not $exe -or -not $userData) { return }
    $exe = $exe.Trim('"')
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $userData)) { return }
    $fullData = [System.IO.Path]::GetFullPath($userData).TrimEnd('\')
    if (@($script:browsers | Where-Object { $_.UserData -ieq $fullData }).Count) { return }
    $script:browsers += [pscustomobject]@{
        Name = $name
        Exe = [System.IO.Path]::GetFullPath($exe)
        UserData = $fullData
    }
}

function Get-Browsers {
    $script:browsers = @()
    if ($Catalog) {
        $items = @(Get-Content -LiteralPath $Catalog -Raw | ConvertFrom-Json)
        foreach ($item in $items) { Add-Browser $item.Name $item.Exe $item.UserData }
        return $script:browsers
    }

    $known = @(
        @('Google Chrome', 'C:\Program Files\Google\Chrome\Application\chrome.exe', (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')),
        @('Google Chrome', 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe', (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')),
        @('Microsoft Edge', (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')),
        @('Microsoft Edge', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')),
        @('Brave', (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe'), (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')),
        @('Brave', 'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe', (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')),
        @('Vivaldi', (Join-Path $env:LOCALAPPDATA 'Vivaldi\Application\vivaldi.exe'), (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data')),
        @('Vivaldi', 'C:\Program Files\Vivaldi\Application\vivaldi.exe', (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data')),
        @('Chromium', (Join-Path $env:LOCALAPPDATA 'Chromium\Application\chrome.exe'), (Join-Path $env:LOCALAPPDATA 'Chromium\User Data')),
        @('Opera', (Join-Path $env:LOCALAPPDATA 'Programs\Opera\launcher.exe'), (Join-Path $env:APPDATA 'Opera Software\Opera Stable')),
        @('Opera GX', (Join-Path $env:LOCALAPPDATA 'Programs\Opera GX\launcher.exe'), (Join-Path $env:APPDATA 'Opera Software\Opera GX Stable'))
    )
    foreach ($item in $known) { Add-Browser $item[0] $item[1] $item[2] }

    if ($PortableRoot -and (Test-Path -LiteralPath $PortableRoot)) {
        $exeNames = @('chrome.exe', 'brave.exe', 'msedge.exe', 'vivaldi.exe', 'opera.exe')
        $files = Get-ChildItem -LiteralPath $PortableRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $exeNames } | Sort-Object { $_.FullName.Length }
        foreach ($file in $files) {
            try { $product = $file.VersionInfo.ProductName } catch { $product = '' }
            if ($product -notmatch '(?i)(Chrome|Chromium|Brave|Cent Browser|Vivaldi|Opera|Microsoft Edge)') { continue }
            $dir = $file.Directory.FullName
            $parent = Split-Path $dir -Parent
            $candidates = @(
                (Join-Path $dir 'User Data'), (Join-Path $dir 'data'),
                (Join-Path $parent 'User Data'), (Join-Path $parent 'data'),
                (Join-Path $parent 'profile\data')
            )
            if ($product -match '(?i)Opera') {
                $candidates = @((Join-Path $env:APPDATA 'Opera Software\Opera Stable')) + $candidates
            }
            $data = $candidates | Where-Object {
                (Test-Path -LiteralPath $_) -and
                ((Test-Path -LiteralPath (Join-Path $_ 'Local State')) -or
                 @(Get-ChildItem -LiteralPath $_ -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }).Count)
            } | Select-Object -First 1
            if ($data) { Add-Browser $product $file.FullName $data }
        }
    }
    $script:browsers
}

function Get-BrowserProfiles {
    $profiles = @()
    foreach ($browser in @(Get-Browsers)) {
        $dirs = @(Get-ChildItem -LiteralPath $browser.UserData -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        if (-not $dirs.Count -and (Test-Path -LiteralPath (Join-Path $browser.UserData 'Preferences'))) {
            $dirs = @([pscustomobject]@{ Name = ''; FullName = $browser.UserData })
        }
        foreach ($dir in $dirs) {
            $tm = (Test-Path -LiteralPath (Join-Path $dir.FullName "Extensions\$tampermonkeyId")) -or
                  (Test-Path -LiteralPath (Join-Path $dir.FullName "Local Extension Settings\$tampermonkeyId"))
            $preferences = @((Join-Path $dir.FullName 'Preferences'), (Join-Path $dir.FullName 'Secure Preferences'))
            $escapedStage = $StageRoot.Replace('\', '\\')
            $themeLoaded = $false
            foreach ($pref in $preferences) {
                if (-not (Test-Path -LiteralPath $pref)) { continue }
                $raw = [System.IO.File]::ReadAllText($pref)
                if ($raw.Contains($escapedStage) -or $raw.Contains($StageRoot.Replace('\', '/'))) { $themeLoaded = $true; break }
            }
            $profiles += [pscustomobject]@{
                Browser = $browser.Name
                Exe = $browser.Exe
                UserData = $browser.UserData
                Profile = $dir.Name
                ProfilePath = $dir.FullName
                Tampermonkey = $tm
                ThemeLoaded = $themeLoaded
            }
        }
    }
    $profiles
}

function Get-Summary {
    $profiles = @(Get-BrowserProfiles)
    $marker = Join-Path $StageRoot '.wintage-palette'
    $paletteNow = if (Test-Path -LiteralPath $marker) { ([System.IO.File]::ReadAllText($marker)).Trim() } else { '-' }
    [pscustomobject]@{
        BrowserCount = @($profiles | Select-Object Browser, UserData -Unique).Count
        ProfileCount = $profiles.Count
        TampermonkeyCount = @($profiles | Where-Object Tampermonkey).Count
        ThemeLoadedCount = @($profiles | Where-Object ThemeLoaded).Count
        Palette = $paletteNow
        StageRoot = $StageRoot
        Profiles = $profiles
    }
}

function Open-Profile($profile, [string[]]$urls) {
    # A real browser executable is always > 100 KB. A stub (empty fixture file,
    # a corrupt install) must never be "launched": Start-Process on it can pop
    # the shell's own error UI or, worse, be caught silently - so a launch that
    # is clearly pointless is refused with a warning instead (T-191).
    try { $len = (Get-Item -LiteralPath $profile.Exe -ErrorAction Stop).Length } catch { $len = 0 }
    if ($len -lt 102400) {
        Write-Warning "Open-Profile: refusing to launch $($profile.Exe) - it is only $len bytes and cannot be a real browser executable."
        return
    }
    $arguments = @("--user-data-dir=`"$($profile.UserData)`"")
    if ($profile.Profile) { $arguments += "--profile-directory=`"$($profile.Profile)`"" }
    $arguments += $urls
    Start-Process -FilePath $profile.Exe -ArgumentList $arguments | Out-Null
}

function Assert-SafeStageRoot([string]$path, $profiles) {
    $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
    $forbidden = @(
        [System.IO.Path]::GetPathRoot($full).TrimEnd('\'),
        ([System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')),
        ([System.IO.Path]::GetFullPath($root).TrimEnd('\'))
    )
    if ($full -in $forbidden -or (Split-Path $full -Leaf).Length -lt 3) {
        throw "Unsafe browser theme staging path: $full"
    }
    foreach ($profile in @($profiles)) {
        $profilePath = [System.IO.Path]::GetFullPath($profile.ProfilePath).TrimEnd('\')
        if ($full -ieq $profilePath -or $full.StartsWith($profilePath + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
            $profilePath.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Browser theme staging path must stay outside browser profiles: $full"
        }
    }
}

$before = Get-Summary
if ($ListJson) {
    $before | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
if (-not $before.ProfileCount) {
    Write-Host 'Chromium browsers: no installed or portable profiles found.' -ForegroundColor DarkYellow
    exit 0
}
Assert-SafeStageRoot $StageRoot $before.Profiles

if ($Revert) {
    if (Test-Path -LiteralPath $StageRoot) {
        if ($PSCmdlet.ShouldProcess($StageRoot, 'Remove staged Wintage browser theme')) {
            Remove-Item -LiteralPath $StageRoot -Recurse -Force
        }
    }
    if (-not $NoLaunch) {
        foreach ($profile in $before.Profiles) {
            $urls = @('chrome://extensions')
            if ($profile.Tampermonkey) { $urls += "chrome-extension://$tampermonkeyId/options.html#nav=dashboard" }
            if ($PSCmdlet.ShouldProcess("$($profile.Browser) / $($profile.Profile)", 'Open browser removal pages')) {
                try { Open-Profile $profile $urls } catch { Write-Warning $_.Exception.Message }
            }
        }
    }
    Write-Host "Chromium browsers: staged theme removed; remove Wintage/Tampermonkey from the opened browser pages if wanted." -ForegroundColor Green
    exit 0
}

$source = Join-Path $root "desktop\out\browser\$Palette"
if (-not (Test-Path -LiteralPath (Join-Path $source 'manifest.json'))) {
    throw "Built browser theme missing: $source"
}
if ($PSCmdlet.ShouldProcess($StageRoot, "Stage Wintage $Palette browser theme")) {
    if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'manifest.json') -Destination (Join-Path $StageRoot 'manifest.json') -Force
    [System.IO.File]::WriteAllText((Join-Path $StageRoot '.wintage-palette'), $Palette, (New-Object System.Text.UTF8Encoding($false)))
}

if ($WhatIfPreference) {
    Write-Host ("Chromium browsers: would stage {0} and open setup for {1} profile(s), Tampermonkey in {2}." -f $Palette, $before.ProfileCount, $before.TampermonkeyCount) -ForegroundColor Cyan
    exit 0
}

$clipboardCopied = $false
if (-not $NoLaunch) {
    try {
        & $ClipboardWriter $StageRoot
        $clipboardCopied = $true
    } catch {
        Write-Warning "Browser theme staged at $StageRoot, but the path could not be copied to the clipboard: $($_.Exception.Message)"
    }
    foreach ($profile in $before.Profiles) {
        $urls = @('chrome://extensions')
        if ($profile.Tampermonkey) { $urls += $userscriptUrl }
        else { $urls += @($tampermonkeyUrl, $userscriptUrl) }
        if ($PSCmdlet.ShouldProcess("$($profile.Browser) / $($profile.Profile)", 'Open theme and Tampermonkey installation pages')) {
            try { Open-Profile $profile $urls } catch { Write-Warning $_.Exception.Message }
        }
    }
}

$finish = if ($NoLaunch) {
    "Chromium browsers: staged $Palette; $($before.ProfileCount) profile(s), Tampermonkey in $($before.TampermonkeyCount); browser launch suppressed."
} elseif (-not $clipboardCopied) {
    "Chromium browsers: staged $Palette; $($before.ProfileCount) profile(s), Tampermonkey in $($before.TampermonkeyCount). Theme path: $StageRoot; Load unpacked once and confirm userscript Install/Update."
} else {
    "Chromium browsers: staged $Palette; $($before.ProfileCount) profile(s), Tampermonkey in $($before.TampermonkeyCount). Theme path copied to clipboard; Load unpacked once and confirm userscript Install/Update."
}
Write-Host $finish -ForegroundColor Green
