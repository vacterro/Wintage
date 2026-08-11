# Wintage release helper: bumps @version, commits everything, pushes to main.
# Usage:  .\release.ps1 -Message "fix reddit hovercards"
#         .\release.ps1 -Message "new palette" -Bump minor
param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('patch', 'minor', 'major')][string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'wintage.user.js'
# Read/write explicitly as UTF-8 (no BOM). PS 5.1's Get-Content defaults to the
# ANSI codepage and mojibakes every non-ASCII character in the file.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($script, $utf8)

if ($content -notmatch '// @version\s+(\d+)\.(\d+)\.(\d+)') {
    throw "Could not find a semver @version line in wintage.user.js"
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]
switch ($Bump) {
    'major' { $maj++; $min = 0; $pat = 0 }
    'minor' { $min++; $pat = 0 }
    'patch' { $pat++ }
}
$new = "$maj.$min.$pat"
$changelog = Join-Path $PSScriptRoot 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $changelog) -or
    [System.IO.File]::ReadAllText($changelog, $utf8) -notmatch "(?m)^## \[$([regex]::Escape($new))\]") {
    throw "CHANGELOG.md needs a ## [$new] entry before release"
}
$content = $content -replace '(// @version\s+)\d+\.\d+\.\d+', "`${1}$new"
# The file carries the version TWICE: the @version header Tampermonkey reads, and
# const W95_VERSION, which is stamped onto every injected <style> so a console can
# say which build is live. Bumping only the header made that stamp lie -- it read
# 1.4.7 on a 1.5.0 build, and a version stamp that lies is worse than none, because
# the one question it exists to answer ("am I looking at a stale install?") gets a
# confident wrong answer. Both move together now, and check-css.js fails if they
# ever disagree again.
$content = $content -replace "(const W95_VERSION = ')\d+\.\d+\.\d+(')", "`${1}$new`${2}"
[System.IO.File]::WriteAllText($script, $content, $utf8)

node --check $script
if ($LASTEXITCODE -ne 0) { throw "Syntax check failed - release aborted, version line already bumped, fix and rerun" }

# node --check cannot see inside the CSS template literals - to JavaScript they
# are just strings. A stray '*/', an unbalanced brace or an off-palette colour in
# there passes --check, loads fine, and then the browser's CSS parser silently
# discards rules while recovering. That exact failure shipped once and was only
# caught by measuring computed styles on a live page, so it gates releases now.
node (Join-Path $PSScriptRoot 'tools/check-css.js')
if ($LASTEXITCODE -ne 0) { throw "CSS check failed - release aborted, version line already bumped, fix and rerun" }

# The theme switch is resolved at document-start from GM storage, with fallbacks
# that only matter when something is wrong (no GM API, a slug whose pack was
# removed, a failed write). None of those paths is exercised by opening a page in
# a healthy browser, so they get a real test instead of an assumption.
node (Join-Path $PSScriptRoot 'tools/test-theme-switch.js')
if ($LASTEXITCODE -ne 0) { throw "Theme switch test failed - release aborted, version line already bumped, fix and rerun" }

# Every luminance threshold in the repainter was written against one dark palette.
# This pins that the polarity layer is a no-op on golden and actually inverts on a
# light one -- a "generalisation" that silently re-grades the shipped theme is a
# regression wearing a feature's clothes.
node (Join-Path $PSScriptRoot 'tools/test-repainter-polarity.js')
if ($LASTEXITCODE -ne 0) { throw "Repainter polarity test failed - release aborted, version line already bumped, fix and rerun" }

# Electron targets share one shim, but Claude alone carries a foreground repair
# for its nested Epitaxy view. Pin both halves: Claude receives it, every other
# Electron app keeps the common stylesheet byte-for-byte.
node (Join-Path $PSScriptRoot 'tools/test-electron-shim.js')
if ($LASTEXITCODE -ne 0) { throw "Electron shim regression test failed - release aborted, version line already bumped, fix and rerun" }

# The palettes live in themes/*.json and are generated INTO the script, so a
# release must never ship a script whose block drifted from the packs. --check
# only reports; regenerating is a deliberate act, not something a release does
# behind the author's back.
# Palettes are DERIVED from golden (UI.md's structure rotated to another hue), so
# a hand-edited pack would silently break the structural guarantee. --check reports;
# regenerating stays a deliberate act.
# The desktop themes are generated from the same packs, and the extension's version
# is read from the header line this script just bumped -- so a --check here would
# fail on EVERY release by construction, which is what happened the first time.
# Build instead of checking: the version bump is the reason it is stale, and the
# fix for that is deterministic, not something the author needs to review.
node (Join-Path $PSScriptRoot 'tools/build-desktop.js')
if ($LASTEXITCODE -ne 0) { throw "Building the desktop themes failed - release aborted, version line already bumped, fix and rerun" }

# The FastPrompter-imported packs are generated too; a hand-edited one would drift
# from its source the same way a hand-edited derived palette does.
node (Join-Path $PSScriptRoot 'tools/import-fastprompter.js') --check
if ($LASTEXITCODE -ne 0) { throw "An imported FastPrompter pack is out of date - run 'node tools/import-fastprompter.js', review the diff, then rerun" }

node (Join-Path $PSScriptRoot 'tools/derive-palette.js') --check
if ($LASTEXITCODE -ne 0) { throw "A derived palette is out of date - run 'node tools/derive-palette.js', review the diff, then rerun" }

node (Join-Path $PSScriptRoot 'tools/apply-themes.js') --check
if ($LASTEXITCODE -ne 0) { throw "Theme block is out of date with themes/*.json - run 'node tools/apply-themes.js', review the diff, then rerun" }

node (Join-Path $PSScriptRoot 'tools/test-theme-packs.js')
if ($LASTEXITCODE -ne 0) { throw "Theme pack test failed - release aborted, version line already bumped, fix and rerun" }

# The repo wiki/ mirror is copied from the saiwiki kitchen and only ever differs
# by .md link adaptation. A hand edit on one side drifts silently until someone
# reads both — the exact failure the qq run caught at T-145, when Installation.md
# still carried a command desktop/README.md had already fixed. This pins that the
# two stay in lockstep.
node (Join-Path $PSScriptRoot 'tools/check-wiki-mirror.js')
if ($LASTEXITCODE -ne 0) { throw "Wiki mirror drifted from the saiwiki kitchen - re-run prepare saiwiki (qq) and collect before release" }

# Every string the shim hands to executeJavaScript must be valid JavaScript, and
# node --check cannot see inside template literals -- the same blind spot
# check-css.js exists for, on the CSS side. Pin that the shipped payloads parse.
node (Join-Path $PSScriptRoot 'tools/test-shim-payloads.js')
if ($LASTEXITCODE -ne 0) { throw "Shim payload test failed - release aborted, version line already bumped, fix and rerun" }

# The console font is named in TWO places (conhost registry vs Windows Terminal
# settings.json). A machine with both installed must not render its two terminals
# in different faces. Pin that they agree and are not proportional Verdana.
node (Join-Path $PSScriptRoot 'tools/test-terminal-font.js')
if ($LASTEXITCODE -ne 0) { throw "Terminal font test failed - release aborted, version line already bumped, fix and rerun" }

# Desktop target dispatch, PowerShell parsing and -WhatIf isolation live in the
# repository suite. A release that skips it can still mutate an app during a dry
# run -- exactly the regression this gate now pins.
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests/Run-Tests.ps1')
if ($LASTEXITCODE -ne 0) { throw "Repository tests failed - release aborted, version line already bumped, fix and rerun" }

# git writes "LF will be replaced by CRLF" to STDERR, and PowerShell 5.1 turns any
# native-command stderr line into a NativeCommandError -- which, even under
# ErrorActionPreference='Continue', still aborts the script the moment the whole
# release is invoked through a pipe (`.\release.ps1 ... | ...`). safecrlf did not
# silence it because the conversion itself is what warns. Two belts:
#   1. -c core.autocrlf=false stops the conversion, so there is no warning to emit.
#   2. Run each git call inside a helper that merges stderr into stdout and decides
#      success by $LASTEXITCODE alone, so a stray line can never be fatal.
# Verified by an actual release run finishing commit+push with no manual finish.
function Git-Safe {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git -c core.autocrlf=false -C $PSScriptRoot @args 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $output | ForEach-Object { Write-Host $_ }
    return $code
}

if ((Git-Safe add -A) -ne 0) { throw "git add failed" }
if ((Git-Safe commit -m "v${new}: $Message") -ne 0) { throw "git commit failed (nothing to commit, or a hook rejected it)" }
if ((Git-Safe push origin main) -ne 0) { throw "git push failed - commit is local; fix the remote and 'git push' by hand" }
# T-191 P1#15: a release must be published WHOLE or not at all. Tagging a commit
# the remote never received creates a half-published version (branch live, tag
# pointing at an unpushed sha). Verify the remote actually converged to the local
# HEAD before the tag exists.
if ((Git-Safe fetch origin main) -ne 0) { throw "git fetch failed - the commit is pushed but the release is NOT tagged; verify the remote state and tag by hand" }
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$remoteSha = (& git -C $PSScriptRoot rev-parse "origin/main" 2>$null).Trim()
$localSha = (& git -C $PSScriptRoot rev-parse "HEAD" 2>$null).Trim()
$ErrorActionPreference = $prevEap
if (-not $remoteSha -or $remoteSha -ne $localSha) {
    throw "remote main is not at the local HEAD ($remoteSha != $localSha) - the branch push is NOT verified, so the release is NOT tagged. Push 'origin main' by hand, verify, then run: git tag -a v$new -m 'Wintage v$new' && git push origin refs/tags/v$new"
}
if ((Git-Safe tag -a "v$new" -m "Wintage v$new") -ne 0) { throw "git tag failed - branch is already pushed" }
if ((Git-Safe push origin "refs/tags/v${new}:refs/tags/v${new}") -ne 0) { throw "git tag push failed - branch and local tag already exist; run 'git push origin refs/tags/v$new' by hand" }
Write-Host "Released Wintage v$new - Tampermonkey clients will pick it up on their next update check." -ForegroundColor Green
