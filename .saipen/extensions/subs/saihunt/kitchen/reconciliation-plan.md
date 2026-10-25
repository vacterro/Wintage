# Read-only reconciliation plan — divergent publication channels

**Status:** PLANNING (not a deployment)
**Date:** 2026-10-25
**Owner:** project operator
**Publication:** DISABLED — this plan is analytical only; no push is performed.

## Context

Two live public remotes serve the Wintage userscript:

| Remote | Repository | `main` HEAD | Serves |
|---|---|---|---|
| `origin` (GitLab) | `gitlab.com/vacuum34/wintage` | `d775325` | 1.36.10 |
| `github` | `github.com/vacterro/Wintage` | `f750202` | 1.36.9 |

The canonical `@updateURL`/`@downloadURL` in the working tree points at GitLab
(`https://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js`). Installs
made before 1.36.10 still carry the old GitHub update URL inside their
metadata and will not self-update from GitLab.

## 1. Common ancestor

```
git merge-base origin/main github/main
→ 60496e734109208135cd3adc20a5c4eeafba87b8
```

The two branches diverged from `60496e7` (the GitLab seed commit from T-980).
The working tree (`HEAD` = `3b6c2e1`) sits **6 commits ahead of `origin/main`**
(`origin/main..HEAD`), none of which have been pushed.

## 2. Commits unique to each destination

### Commits unique to GitLab (`github/main..origin/main`)

```
d775325 merge(T-980): graft the GitLab seed commit so main publishes by fast-forward
a121bfb publish(T-980): move the release channel to GitLab, republish the project
d43b698 Initial commit
```

These are the T-980 migration commits that established GitLab as the canonical
distribution channel.

### Commits unique to GitHub (`origin/main..github/main`)

```
f750202 chore(docs): restamp README source digests after the freebuff docs fix
052f416 fix(freebuff): keep the chosen sound out of the checkout, drop a game wav
76e4f4f docs: add newer screenshots under spoiler
6aabc23 docs: add fresh Wintage showcase screenshots
04a7f09 docs: expand Wintage screenshot showcase
86fddf5 docs: redesign Wintage README
```

These are the operator's own repair (`052f416`, ported into this tree by T-982)
and the 7 October README redesign (`86fddf5`, `04a7f09`, `6aabc23`, `76e4f4f`).

### Commit ancestry

```
git merge-base --is-ancestor 052f416 origin/main
→ exit 1 (NOT an ancestor)
```

`052f416` is **not** an ancestor of `origin/main`. The freebuff repair exists on
the GitHub side but is not reachable from GitLab `main`. The working tree has
been ported separately (T-982).

## 3. Assets unique to each destination

### Assets unique to GitHub (present in `github/main`, absent from `origin/main`)

```
docs/showcase/more-screenshots-2026-10.webp  (webP images, README showcase)
sounds/freebuff.wav                          (game-derived WAV, 524,288 bytes)
```

- `sounds/freebuff.wav`: the GitHub side **does not** have the `sounds/`
  gitignore rule that this tree now carries. The file is still tracked there.
  This tree has already removed it from the index (T-982 / `50302de`).
- `docs/showcase/more-screenshots-2026-10.webp`: restorable from the GitHub
  commit: `git checkout f750202 -- docs/showcase/more-screenshots-2026-10.webp`.

### Assets unique to GitLab

None structurally unique. The GitLab side carries 6 unpushed local commits
ahead of the last fetch (`d775325`), but those are only in this working tree.

## 4. README differences

The common ancestor README (170 lines) vs `github/main` README (207 lines):

```
git diff $(git merge-base origin/main github/main) github/main -- README.md
→ 163 insertions(+), 114 deletions(-)
```

Key differences on the GitHub side:

- Badges section (not in GitLab `main`)
- "Showcase" section with screenshots (not in GitLab `main`)
- "Why Wintage" section (not in GitLab `main`)
- Features table (not in GitLab `main`)
- Project network section (not in GitLab `main`)
- Support block pointing at GitHub (GitLab `README.md` repoints at GitLab)
- Migration note for pre-1.36.10 installs (in GitLab, absent on GitHub)

Neither README is a superset of the other.

## 5. Legacy updateURL compatibility

| Install cohort | Stored `@updateURL` | Current remote | Will auto-update? |
|---|---|---|---|
| Pre-1.36.10 installs | `https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js` | GitHub (`f750202` = 1.36.9) | **No** — still serves 1.36.9; no further updates published to GitHub |
| 1.36.10+ installs | `https://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js` | GitLab (`d775325` = 1.36.10) | Yes, from GitLab |

**This is a user-visible break.** Pre-1.36.10 Tampermonkey installs will never
self-update again unless 1.36.11 is pushed to GitHub, because the update URL
lives inside the installed script's metadata, not in the repository.

## 6. Fast-forward feasibility

```
git merge-base --is-ancestor origin/main HEAD
→ (not applicable: origin/main is remote)
git merge-base --is-ancestor github/main origin/main
→ exit 1
```

Neither remote's `main` is an ancestor of the other's. A **direct push is not a
valid reconciliation strategy** — both sides have commits the other lacks.
A true merge requires a merge commit and an owner decision about which content
wins when the two sides conflict.

## 7. Reconciliation options (owner decision)

### Option A: Push current working tree to GitLab (no GitHub sync)

- Push `HEAD` to `origin/main`. GitLab becomes the sole canonical distribution.
- Pre-1.36.10 installs on GitHub stay stranded at 1.36.9 forever.
- GitHub side keeps its divergent README, screenshots, and `sounds/freebuff.wav`.
- **Risk:** split documentation and stranded users.

### Option B: Fast-forward merge — push to both sides

- Merge the two `main` branches (manual resolution of README conflicts).
- Push the merge base to both GitLab and GitHub.
- Both channels converge at one commit.
- **Requires:** owner to pick README content (neither is a superset), decide on
  `sounds/freebuff.wav` (remove per T-982, or keep), and decide on
  `docs/showcase/more-screenshots-2026-10.webp` (restore or drop).
- **Risk:** README conflicts require manual resolution; `052f416` on GitHub
  must be reconciled with `50302de` in this tree (same fix, different commit).

### Option C: GitHub becomes read-only archive

- Leave GitHub at `f750202` (1.36.9).
- All new releases go to GitLab only.
- Add a deprecation notice to GitHub README.
- **Risk:** stranded pre-1.36.10 installs; documentation drift.

## 8. What the campaign can do (local-only, no push)

- **Preserve:** The working tree already carries the ported `052f416` repair
  (`50302de`). No data from either side is lost by keeping it.
- **Offer:** The GitHub-only assets (`docs/showcase/more-screenshots-2026-10.webp`,
  the GitHub README) are restorable via `git checkout f750202 -- <path>` if the
  owner chooses Option B.
- **Warn:** `sounds/freebuff.wav` on GitHub violates the T-982 invariant this
  tree already enforces (gitignored, removed from index). If Option B merges
  GitHub into GitLab, the file must be explicitly excluded.

## Conclusion

**A direct push to both destinations is not a valid reconciliation strategy.**
The two branches have independent commits since their common ancestor
(`60496e7`), neither is an ancestor of the other, and their READMEs are not
supersets. The owner must choose which content to preserve, which users to
strand or migrate, and whether to merge or archive. This plan is analytical;
no push, tag, or publication is performed.
