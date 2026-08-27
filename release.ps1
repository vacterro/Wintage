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

# git writes "LF will be replaced by CRLF" to STDERR, and PowerShell 5.1 turns any
# native-command stderr line into a NativeCommandError -- which, even under
# ErrorActionPreference='Continue', still aborts the script the moment the whole
# release is invoked through a pipe (`.\release.ps1 ... | ...`). safecrlf did not
# silence it because the conversion itself is what warns. Two belts:
#   1. -c core.autocrlf=false stops the conversion, so there is no warning to emit.
#   2. Run each git call inside a helper that merges stderr into stdout and decides
#      success by $LASTEXITCODE alone, so a stray line can never be fatal.
function Git-Safe {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git -c core.autocrlf=false -C $PSScriptRoot @args 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $output | ForEach-Object { Write-Host $_ }
    return $code
}

# ─── PREFLIGHT: every feasible NON-MUTATING gate runs before any file changes ──
# W2-007: the release publishes refs/heads/main + the version tag as ONE atomic
# unit, so the branch being committed on MUST be main and HEAD MUST equal the
# local main ref that will be pushed. A release run from a feature branch used to
# push the tag (feature commit) while remote main stayed behind - atomicity only
# proves both refs moved together, never that they name the same commit.
$currentBranch = ((& git -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null) -join '').Trim()
if ($currentBranch -ne 'main') {
    throw "release must run on 'main' (current branch: '$currentBranch') - the release publishes refs/heads/main and the version tag as one unit; committing on any other branch would split them. NOTHING was changed."
}
$headCommit = ((& git -C $PSScriptRoot rev-parse HEAD 2>$null) -join '').Trim()
$mainCommit = ((& git -C $PSScriptRoot rev-parse 'refs/heads/main' 2>$null) -join '').Trim()
if (-not $headCommit -or $mainCommit -ne $headCommit) {
    throw "HEAD ($headCommit) does not equal refs/heads/main ($mainCommit) - the release would publish a different commit than it pushes. NOTHING was changed."
}

# T-201: `git add -A` publishes EVERY untracked file sitting in the tree. Refuse
# BEFORE anything is mutated (W2-009) so a refused release leaves the tree
# byte-identical and the next run retries at the same version.
$untracked = @(& git -C $PSScriptRoot ls-files --others --exclude-standard)
if ($untracked.Count -gt 0) {
    Write-Host "release aborted: $($untracked.Count) untracked file(s) would ride along in 'git add -A':"
    $untracked | ForEach-Object { Write-Host "  $_" }
    throw "git add -A would publish untracked file(s) - commit, delete or gitignore them, then rerun. NOTHING was changed."
}

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
$tagRef = "refs/tags/v$new"
$branchRef = 'refs/heads/main'

# ─── PREPARED-VERSION TRACKING (W2-009) ───────────────────────────────────
# A failed release is restartable: $prepared stays $false until the release
# COMMIT exists. Any failure before that restores every tracked file to HEAD, so
# a rerun recomputes the SAME version instead of skipping one or failing against
# a changelog entry the user never intended to create.
$prepared = $false
try {
    # The changelog entry for the TARGET version must exist BEFORE the bump (a
    # rerun after a failed release retries the same version, so the entry is
    # already there - this check is then idempotent).
    $changelog = Join-Path $PSScriptRoot 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $changelog) -or
        [System.IO.File]::ReadAllText($changelog, $utf8) -notmatch "(?m)^## \[$([regex]::Escape($new))\]") {
        throw "CHANGELOG.md needs a ## [$new] entry before release - NOTHING was changed."
    }
    # Tag availability is checked BEFORE any mutation too: a tag collision must
    # abort with the tree untouched, not after the version was bumped and committed.
    $tagExists = ((& git -C $PSScriptRoot tag -l "v$new") -join '').Trim()
    if ($tagExists) { throw "local tag v$new already exists - release aborted BEFORE publishing anything. NOTHING was changed." }
    if ((Git-Safe ls-remote --exit-code origin $tagRef) -eq 0) { throw "remote already has $tagRef - release aborted BEFORE publishing anything. NOTHING was changed." }

    # Bump: the file carries the version TWICE - the @version header Tampermonkey
    # reads, and const W95_VERSION, which is stamped onto every injected <style>
    # so a console can say which build is live. Bumping only the header made that
    # stamp lie -- it read 1.4.7 on a 1.5.0 build, and a version stamp that lies is
    # worse than none, because the one question it exists to answer ("am I looking
    # at a stale install?") gets a confident wrong answer. Both move together now,
    # and check-css.js fails if they ever disagree again.
    $content = $content -replace '(// @version\s+)\d+\.\d+\.\d+', "`${1}$new"
    $content = $content -replace "(const W95_VERSION = ')\d+\.\d+\.\d+(')", "`${1}$new`${2}"
    [System.IO.File]::WriteAllText($script, $content, $utf8)

    node --check $script
    if ($LASTEXITCODE -ne 0) { throw "Syntax check failed - release aborted" }

    # node --check cannot see inside the CSS template literals - to JavaScript they
    # are just strings. A stray '*/', an unbalanced brace or an off-palette colour in
    # there passes --check, loads fine, and then the browser's CSS parser silently
    # discards rules while recovering. That exact failure shipped once and was only
    # caught by measuring computed styles on a live page, so it gates releases now.
    node (Join-Path $PSScriptRoot 'tools/check-css.js')
    if ($LASTEXITCODE -ne 0) { throw "CSS check failed - release aborted" }

    # The theme switch is resolved at document-start from GM storage, with fallbacks
    # that only matter when something is wrong (no GM API, a slug whose pack was
    # removed, a failed write). None of those paths is exercised by opening a page in
    # a healthy browser, so they get a real test instead of an assumption.
    node (Join-Path $PSScriptRoot 'tools/test-theme-switch.js')
    if ($LASTEXITCODE -ne 0) { throw "Theme switch test failed - release aborted" }

    # Every luminance threshold in the repainter was written against one dark palette.
    # This pins that the polarity layer is a no-op on golden and actually inverts on a
    # light one -- a "generalisation" that silently re-grades the shipped theme is a
    # regression wearing a feature's clothes.
    node (Join-Path $PSScriptRoot 'tools/test-repainter-polarity.js')
    if ($LASTEXITCODE -ne 0) { throw "Repainter polarity test failed - release aborted" }

    # Electron targets share one shim, but Claude alone carries a foreground repair
    # for its nested Epitaxy view. Pin both halves: Claude receives it, every other
    # Electron app keeps the common stylesheet byte-for-byte.
    node (Join-Path $PSScriptRoot 'tools/test-electron-shim.js')
    if ($LASTEXITCODE -ne 0) { throw "Electron shim regression test failed - release aborted" }

    # The palettes live in themes/*.json and are generated INTO the script, so a
    # release must never ship a script whose block drifted from the packs. --check
    # only reports; regenerating is a deliberate act, not something a release does
    # behind the author's back.
    node (Join-Path $PSScriptRoot 'tools/test-theme-packs.js')
    if ($LASTEXITCODE -ne 0) { throw "Theme pack test failed - release aborted" }

    # The desktop themes are generated from the same packs, and the extension's
    # version is read from the header line this script just bumped -- so a --check
    # would fail on EVERY release by construction. Build instead: the version bump
    # is the reason it is stale, and the fix is deterministic.
    node (Join-Path $PSScriptRoot 'tools/build-desktop.js')
    if ($LASTEXITCODE -ne 0) { throw "Building the desktop themes failed - release aborted" }

    # Regeneration contracts: a hand-edited derived/imported/theme block drifts
    # from its source and is only ever fixed deliberately.
    node (Join-Path $PSScriptRoot 'tools/import-fastprompter.js') --check
    if ($LASTEXITCODE -ne 0) { throw "An imported FastPrompter pack is out of date - run 'node tools/import-fastprompter.js', review the diff, then rerun" }
    node (Join-Path $PSScriptRoot 'tools/derive-palette.js') --check
    if ($LASTEXITCODE -ne 0) { throw "A derived palette is out of date - run 'node tools/derive-palette.js', review the diff, then rerun" }
    node (Join-Path $PSScriptRoot 'tools/apply-themes.js') --check
    if ($LASTEXITCODE -ne 0) { throw "Theme block is out of date with themes/*.json - run 'node tools/apply-themes.js', review the diff, then rerun" }

    # The repo wiki/ mirror is copied from the saiwiki kitchen and only ever differs
    # by .md link adaptation. A hand edit on one side drifts silently until someone
    # reads both. This pins that the two stay in lockstep.
    node (Join-Path $PSScriptRoot 'tools/check-wiki-mirror.js')
    if ($LASTEXITCODE -ne 0) { throw "Wiki mirror drifted from the saiwiki kitchen - re-run prepare saiwiki (qq) and collect before release" }

    # Every string the shim hands to executeJavaScript must be valid JavaScript, and
    # node --check cannot see inside template literals -- the same blind spot
    # check-css.js exists for, on the CSS side. Pin that the shipped payloads parse.
    node (Join-Path $PSScriptRoot 'tools/test-shim-payloads.js')
    if ($LASTEXITCODE -ne 0) { throw "Shim payload test failed - release aborted" }

    # The console font is named in TWO places (conhost registry vs Windows Terminal
    # settings.json). A machine with both installed must not render its two terminals
    # in different faces. Pin that they agree and are not proportional Verdana.
    node (Join-Path $PSScriptRoot 'tools/test-terminal-font.js')
    if ($LASTEXITCODE -ne 0) { throw "Terminal font test failed - release aborted" }

    # Desktop target dispatch, PowerShell parsing and -WhatIf isolation live in the
    # repository suite. A release that skips it can still mutate an app during a dry
    # run -- exactly the regression this gate now pins.
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests/Run-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Repository tests failed - release aborted" }

    if ((Git-Safe add -A) -ne 0) { throw "git add failed" }
    if ((Git-Safe commit -m "v${new}: $Message") -ne 0) { throw "git commit failed (nothing to commit, or a hook rejected it)" }
    $prepared = $true

    # T-192 P1#25: a release is published WHOLE or NOT AT ALL. The branch and the tag
    # are pushed in ONE `git push --atomic` refspec: if either ref is rejected the
    # remote receives NEITHER, so no half-published version can ever exist. The tag
    # is created locally first.
    if ((Git-Safe tag -a "v$new" -m "Wintage v$new") -ne 0) { throw "git tag failed - release aborted BEFORE publishing anything." }

    # W2-007: prove the annotated tag dereferences to the EXACT branch commit being
    # published - a tag on a different commit is a branch/tag split even when the
    # push is atomic.
    $tagOid = ((& git -C $PSScriptRoot rev-parse "${tagRef}^{commit}" 2>$null) -join '').Trim()
    $mainOid = ((& git -C $PSScriptRoot rev-parse 'refs/heads/main^{commit}' 2>$null) -join '').Trim()
    if (-not $tagOid -or $tagOid -ne $mainOid) {
        throw "tag v$new dereferences to $tagOid but the published branch is $mainOid - branch/tag split detected; nothing was pushed."
    }
    if ((Git-Safe push --atomic origin "${branchRef}:${branchRef}" "${tagRef}:${tagRef}") -ne 0) {
        throw "atomic push FAILED - the remote received NEITHER the branch NOR the tag (git push --atomic). The local commit and annotated tag are ready; fix the remote and re-run: git push --atomic origin refs/heads/main refs/tags/v$new"
    }
    # Post-push invariant: origin/main must now BE the release commit.
    $remoteMain = ((& git -C $PSScriptRoot ls-remote origin $branchRef 2>$null) -join '').Trim() -split '\s+' | Select-Object -First 1
    if ($remoteMain -ne $mainOid) {
        throw "post-push verification failed: origin/main is $remoteMain, expected $mainOid - the remote may need manual repair."
    }
    Write-Host "Released Wintage v$new - Tampermonkey clients will pick it up on their next update check." -ForegroundColor Green
} catch {
    if (-not $prepared) {
        # W2-009: restore every tracked file the preparation mutated so a rerun
        # retries the SAME version (untracked files were refused at preflight, so
        # restoring tracked files returns the tree to its exact pre-release state).
        & git -C $PSScriptRoot checkout -- . 2>$null | Out-Null
        Write-Host "release aborted before the release commit: the versioned files were restored to their pre-release state - fix the cause and rerun (it will bump the SAME version)." -ForegroundColor Yellow
    }
    throw
}