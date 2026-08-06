$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = "$PSScriptRoot\.."
$watcher.Filter = "wintage.user.js"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

Write-Host "Watching wintage.user.js for changes. Press Ctrl+C to exit."

$action = {
    $path = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    Write-Host "File $path changed. Rebuilding and hot-reloading Claude..."
    
    # Run the build
    Set-Location "$PSScriptRoot\.."
    node tools/check-css.js
    if ($LASTEXITCODE -eq 0) {
        node tools/build-desktop.js
        if ($LASTEXITCODE -ne 0) { Write-Host 'build-desktop.js failed -- not hot-reloading.'; return }
        # Find Claude app path dynamically
        $claudeAppPath = (Get-ChildItem -Path "$env:LOCALAPPDATA\AnthropicClaude\app-*" | Sort-Object Name -Descending | Select-Object -First 1).FullName
        if ($claudeAppPath) {
            $dest = "$claudeAppPath\resources\app.asar\wintage.css"
            if (Test-Path "$claudeAppPath\resources\app.asar") {
                Copy-Item "desktop\out\electron\goldendefault\wintage.css" $dest -Force
                Write-Host "Hot-reloaded to $dest"
            }
        }
    } else {
        Write-Host "CSS check failed. Skipping reload." -ForegroundColor Red
    }
}

Register-ObjectEvent $watcher "Changed" -Action $action > $null

while ($true) {
    Start-Sleep -Seconds 1
}
