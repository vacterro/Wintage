# Third-party notices

Wintage itself is MIT licensed (see `LICENSE`). This file records what the
repository ships that is not first-party, and the status of each item's
redistribution terms:

| Item | Origin | License | Status |
|---|---|---|---|
| `fonts/terminal/files/*.ttf` (20 families) | google/fonts, pinned per family in `fonts/terminal/sources.json` | SIL OFL 1.1 / Apache 2.0 / MIT / Bitstream Vera, one per family | **CONFIRMED** |
| `fonts/terminal/licenses/*.txt` | the upstream license artifact of each family, pinned by SHA-256 in `sources.json` | as above | **CONFIRMED** |
| `Verdana_m1.ttf` | Microsoft Corporation (Verdana), modified with FontForge 2.0 | Microsoft's font terms (name ID 13); OS/2 `fsType` 8 | **NEEDS_REVIEW** |

## The terminal fonts — CONFIRMED

Every bundled terminal face is an open-source family, pinned to an immutable
upstream reference (a google/fonts commit, or a release tag plus asset URL)
together with the SHA-256 of the exact file and of its license artifact, in
`fonts/terminal/sources.json`. `fonts/terminal/catalog.json` is the canonical
catalog, and `tools/sync-terminal-fonts.ps1 -VerifyOnly` re-verifies every
hash **offline**, with no network and no download: a mismatch is a hard
refusal. Wintage never downloads a font at runtime; it ships the verified
`files/` tree and reads it from disk.

System families that Wintage only *names* (Consolas, Terminus) are listed in
the catalog with `bundled: false` — the project neither ships nor owns them.

## `Verdana_m1.ttf` — NEEDS_REVIEW

`Verdana_m1.ttf` is a copy of Microsoft's Verdana (font name ID 0: "© 2016
Microsoft Corporation. All Rights Reserved."; version 5.33), modified with
FontForge 2.0 on 2026-05-20 to carry pre-rendered 1bpp bitmap strikes so that
the face renders without antialiasing. Its own name ID 13 carries Microsoft's
embedding terms ("You may use this font to create, display, and print content
as permitted by the license terms …"), and its OS/2 `fsType` is 8 (editable
embedding).

Those terms grant **use**, and the product stays inside that grant: the
installer only *probes* for the face (`desktop/modules/targets.ps1`) and the
user installs it themselves, deliberately, the way they would install any
font. The repository's own font policy (T-228) says exactly that — "Wintage
never installs or uninstalls a font".

What the terms do not grant is **redistribution**, and the repository is
public: publishing the modified file in a public repository is redistribution.
That is a licensing question about the artifact, not a code defect, so it is
recorded here rather than silently changed. The decision belongs to the
project owner and is tracked as **T-986**; the options are:

1. keep shipping the file and accept the exposure;
2. keep the file out of the public repository (it stays in the tree locally and
   in the history) and let the installer point the user at a copy they already
   own;
3. replace the face with a redistributable bitmap-strike substitute.

Until that decision is taken, treat this file as the one bundled asset whose
redistribution status is not positively verified — every other bundled binary
in the repository is covered by a pinned, hash-verified license artifact. The
product still references the face (`desktop/modules/targets.ps1`), so the
choice is visible in the installer's behaviour, not only in this file.
