# Changelog

## [Unreleased]

### Added

- **Suite files must be tracked (T-416).** `tests/Run-Tests.ps1` now asserts that
  every tool file its entries run is carried by git -- in `HEAD`, or in the index
  of the commit being written: the T-413 wave ran ten test files that had zero
  commits and existed only in that working tree, so a fresh clone ran a suite
  whose structural check was satisfied by strings while the files it named were
  absent from the repository. The assertion also covers absence from disk, since
  neither is shipped, and a second assertion proves the predicate non-vacuous by
  flagging `package.json`, which exists here and is in neither. The check is
  falsifiable on demand (`git rm --cached tools/<a suite file>` turns it red with
  the file named, proved against a private index), and it immediately found six
  more suite gates shipped by no commit -- `tools/test-build-desktop-publish.js`,
  `test-chatgpt-viewport-coverage.js`, `test-generation-handover.js`,
  `test-inject-wintage-web.js`, `test-manifest-forward-compat.ps1` and
  `test-release-rollback-split.ps1`, referenced from `$toolSuites` at
  `tests/Run-Tests.ps1` lines 633, 639, 647, 828, 844 and 853 -- which are now
  committed. Both halves of the predicate are needed: this wave commits through a
  private index so the checkout's own pre-staged set is never disturbed, and a
  HEAD-only rule would report the files this repository has already shipped.

- **Commit-scope gate (T-418).** `tools/test-commit-scope.ps1` refuses a commit
  whose scope is wider than one ticket: product paths plus the standard memory
  surfaces plus only the per-event `LOG.md` journals that commit's own lines
  attribute to that ticket. The 2026-10-05 T-413 commit `c528ef3` carried 256
  unrelated journals beside its 102 product paths; that commit is now a
  regression clause in `tests/Run-Tests.ps1`, and the gate's `-RedControl`
  proves in a scratch repository that it names a foreign journal and a foreign
  `LOG.md` line.

- **Delivery-claim resolver (T-417).** `tools/check-delivery-claims.ps1` reads the
  delivery text (`.saipen/kitchen/digest.md` by default) and resolves every
  path-shaped token in it against the artifact — present in `HEAD`, or staged for
  the commit being written — naming the ones that resolve nowhere, with the
  `git check-ignore` rule for a file that exists only in the working copy. The
  2026-10-05 T-413 report claimed an npm `test` script repair in `package.json`,
  which `.gitignore:60` excludes and no archive carries; that claim now scores
  unverifiable, and the gate's `-RedControl` proves the same in a scratch
  repository.

### Removed

- **Duplicated BetterDiscord plugin distribution (T-413).** The standalone plugin
  payloads formerly under `desktop/targets/betterdiscord/plugins/` and
  `updated_discord_plugins/` are deleted; the installer BetterDiscord tab is now a
  navigation page linking the canonical repository
  https://github.com/vacterro/BetterDiscord_vac34_plugins, where those plugins are
  maintained. The BetterDiscord theme target (`template.css`) is untouched, and
  `tools/test-bd-architecture.ps1` fails the suite if a payload or a removed manager
  symbol returns.

ChatGPT Web viewport-owner coverage, plus the BetterDiscord media-control
repair + HideEmbeds from the previous pass. The main Wintage version is
deliberately NOT bumped here: it moves only once this wave and the full
repository regression suite are green.

### Fixed

- **Three red controls that no suite entry ever ran.** Seventeen gates under
  `tools/` declare a `-RedControl` mode; thirteen had a suite entry exercising it
  and four did not. Three of those four — `test-log-append-bound.ps1`,
  `test-totalcmd-recovery.ps1` and `test-windows-theme-boundary.ps1` — declare
  the mode and nothing in `tests/Run-Tests.ps1` invoked them, so on every
  full-suite pass those controls were inert. Each now has its own suite entry:
  the bounded-log one prints `RED CONTROL PROVEN`, the TotalCommander one
  `RED CONTROL PASS: 4 of 4 mandatory + 5 of 5 extra critical failures
  reproduced`, and the theme-boundary one runs its control (see the entry below —
  its original control measured nothing). All 17 red-control modes are now
  exercised by the single entrypoint.

- **The Windows theme boundary gate's red control could not fail.**
  `test-windows-theme-boundary.ps1 -RedControl` claimed to prove that pre-fix
  code orphans theme files when the accent write fails, but it never loaded any
  pre-fix code and never injected any accent failure. It ran the shipped
  `tools/install-windows-theme.js` helper directly and then appended a bare
  `throw 'simulated accent write failure'` to the same command line — the helper
  had already exited and written every file it was supposed to write, so the
  throw rolled nothing back. The assertion then counted leftover scratch files,
  which a scratch replay showed was byte-identically true with the failure and
  without it: the control could not distinguish a defective tree from a healthy
  one. It now copies the product tree, cuts `Restore-WindowsPreState`'s phase-A
  file removal in the copy, and runs the real installer under the same
  `WINTAGE_TEST_FAIL_WIN_ACCENT_WRITE` injector green Case 2 uses — in both
  directions, so the cut is shown to remove what it claims and keep what it
  claims to keep (`red cut tree: exit=1 orphaned theme files=1`, `shipped tree:
  exit=1 orphaned theme files=0`). The gate also proves its own switch is read in
  both directions now, the same guard the BetterDiscord installer gate got.

- **`test-tf-apply-results.js --red-control` never injected the defect it
  claimed to detect.** Its two RED assertions were negative regex matches against
  the *shipped* source, and the second — `/Say-TfLog 'apply done\.';/` — is
  strictly weaker than the first, since the semicolon variant's match set is a
  subset of the unsuffixed one. So the pair could never disagree: green on a
  clean build, red together on a broken one. A comment claimed they proved the
  old unconditional `apply done.` emit was caught; no mutant was ever built. The
  mode now splices that emit back into a copy of `Invoke-TfApply`, writes the
  mutant to disk, re-reads it, and runs the same predicate on the file — plus an
  assertion that the mutant kept the qualified emit it was spliced next to, so a
  vacuous pass would be caught.

- **Ten release gates ran only at release.** `tests/Run-Tests.ps1` derived every
  gate `release.ps1` invokes, asserted each one exists as a file, and then
  executed nine fewer of them than it had just proved present — so
  "Run-Tests.ps1 exits 0" said nothing about the theme-switch, terminal-font,
  shim-payloads, repainter-polarity, electron-shim, diag-counters, fs-retry,
  theme-packs and wiki-mirror gates. All ten now have suite entries (1.9s
  combined), and a new derived assertion requires every gate the block extracts
  from `release.ps1` to be executed by the suite, so the eleventh cannot repeat
  it. The assertion resolves one level of transitive invocation, which is why
  `test-electron-repaint-probe.cjs` needs no entry of its own: it is reached
  through `test-electron-repaint.ps1`, and that edge is read from the file's
  source rather than trusted from a comment.

- **The `wiki/` mirror had drifted for six releases.** Wiring
  `check-wiki-mirror.js` into the suite immediately turned red: five mirror
  pages — `Desktop.md`, `Development.md`, `Home.md`, `Installation.md`,
  `_Footer.md` — still carried v1.30.0 content while the saiwiki kitchen had
  moved to v1.36.0. The gate is release-only, so nothing in the test path was
  reading it. The mirror was resynced by extracting `adaptForRepo()` verbatim
  out of the gate's own source and calling it, so every byte written is by
  construction the byte the gate accepts; `node tools/check-wiki-mirror.js` now
  prints PASS.

- **`test-perf-lanes.js` printed a ToS-compliance PASS that measured nothing.**
  The retired-AD_BLOCK section carried
  `check('PERF-002 shim: AD_BLOCK retired for FreeBuff ToS compliance', true, true)` —
  the literal `true` compared with itself, so it passed for any content of any
  file. The property was not unverified: `R012 static: AD_BLOCK is not
  reintroduced into the shim` asserts it for real. Reinserting
  `const AD_BLOCK = /ads|doubleclick/;` into `shim.cjs` proved it — the gate went
  red on the static check while still printing the compliance PASS, two lines
  away. The vacuous line is gone; the static check is the single source of truth.

- **`test-perf-suspend.js` asserted its WeakMap-preservation check with a
  permanently-vacuous comparison.** The check read
  `t.ctx.sheetSeen === t.owners.sheetSeen || true`, whose `|| true` makes the
  expression true whatever the left side says, so it reported PASS on every run
  including one where suspension had replaced both caches. Two further faults sat
  underneath it: the `owners` object never captured `sheetSeen` or
  `attrCooldown` at all, so the left side was false on every run; and the check
  was passed in the `(got, want)` form, which the gate compares with
  `JSON.stringify` — and two distinct WeakMaps both stringify to `{}`, so even
  with the comparison intact the form could never go red on a replacement. All
  three are fixed: `owners` now carries both caches, and the identity check is
  passed as a predicate, verified green on the shipped tree and red on a mutant
  that substitutes `new WeakMap()` for the ctx-side pair.

- **`test-batch-streaming-gui.ps1` carried a 34-line probe dispatcher nothing
  called.** `Run-RedProbe` was a `switch` over the five `-Probe` values, defined
  once and referenced zero times; the code that actually ran was a separate
  `if`/`elseif` chain with no `else`. So an unrecognised `-Probe` name fell
  through every branch, ran no probe, printed no assertion and exited 0. The
  dead dispatcher is deleted and its `default { throw }` guard now sits on the
  live chain as an `else`: an unknown probe name exits 1, while all five
  recognised probes still run with the same assertion labels.

- **`test-batch-generation.ps1 -RedControl` had never actually run.**
  `common.ps1` dot-sources two siblings — `generation-lock.ps1` and
  `json-doc.ps1`. The red-control staging rewrote and copied only the first, so
  every probe that loaded the red copy died on `CommandNotFoundException` for
  `json-doc.ps1` before reaching a single assertion — and the gate then exited 1
  printing `RED CONTROL FAILED: a gate stayed green on defective source`, a claim
  about probes that had never executed. A control that cannot run is not a
  control that cannot bite. `json-doc.ps1` is now staged unmodified beside both
  red copies (it is not part of the defect being reproduced), the owner-identity
  and age-steal probes both report `True`, and the mode exits 0 with
  `RED CONTROL OK: all gates reproduce their defects`. Because the control only
  started working, its suite entry is new: `tests/Run-Tests.ps1` now runs
  `test-batch-generation.ps1 -RedControl` alongside the default pass.

- **`test-betterdiscord-plugin-installer.ps1` had a `-RedControl` switch it
  never read.** The switch was declared, the header comment promised a second
  mode, and the red-control block ran unconditionally in the default path — so
  `-RedControl` and a plain run were the same run, and a control that judges the
  harness was being judged by a product gate. It was the only one of the fifteen
  PowerShell gates declaring that switch without guarding on it. The block is now
  guarded, `tests/Run-Tests.ps1` gained its own `-RedControl` suite entry so the
  control still runs on every full pass, and the file asserts in both directions
  that the switch selected the mode: dropping the guard turns the default run
  red, deleting the control turns the `-RedControl` run red. Default mode reports
  42 checks, `-RedControl` reports 44, and the difference is exactly the two
  `RED CONTROL` assertions.
- **ChatGPT: the central viewport stayed stock charcoal while every themed
  parent was present.** The current shell paints
  `[data-testid="mobile-app-shell-scroll-container"]` with its own opaque
  background. That element is a CHILD of `#web-mobile-root`,
  `[data-testid="desktop-app-shell"]`, `main[aria-label="ChatGPT"]` and
  `[role="region"][aria-label="Conversation"]` — all four of which were themed
  correctly. Theming an ancestor does not theme the area you look at, so the
  page was visibly wrong while every October contract still matched and every
  existing gate stayed green. The scroll container now carries its own
  `background-color: ${T.backgroundSoft}` / `color: ${T.textPrimary}`
  declaration. The parent rules stay: they remain the fallback for rollouts
  that have no scroll container.
- **ChatGPT: page header and footer fades.** The shell draws both as a stock
  charcoal `background-image` gradient over the scroll container, which no
  surface rule could reach. They are now stripped to
  `background-image: none` and repainted with `${T.backgroundSoft}`. The scope
  is a direct-child combinator off `main[aria-label="ChatGPT"] [data-testid="desktop-app-shell"]`
  and the scroll container, plus the stable `#page-header` id. A message
  embed's header or footer is nested inside the conversation region and can
  never be a direct child, so this is what keeps "do not affect headers/footers
  inside message embeds" true without `:has()`, without a class fragment and
  without a universal selector. A gradient was deliberately not used: UI.md
  law 2 is zero gradients, and the runtime gradient killer already strips
  gradient `background-image`s on any repaint.
- **`test-inspect-web-mutations.js` was running a third of its controls.** Of
  its 34 mutation anchors, the multi-line ones are written with `\n`, and this
  repository checks out on Windows with CRLF, so eight of them could never be
  found. Each of those eight reported "mutation anchor not found", incremented
  a counter, and still exited 0 — a harness skipping a control is not the same
  as the control biting. The source is now normalised to LF before any anchor is
  matched: all 34 controls run, and all 34 go red.
- **`tools/inspect-web.js` named a colour token for the prompt editor that
  `vintage.user.js` never paints.** The surface's expectation was
  `'prompt-editor': '--composer-background-color'`, justified in a comment as no
  longer being a guess. It was: the element the selector actually matches on the
  current shell, `[data-testid="prompt-textarea"]`, receives `color` and
  `caret-color` and no background, and the one variant that is painted,
  `#mobile-composer-prompt`, is a different element carrying `T.surface`. Because
  `prompt-editor` is an acceptance surface, the phantom mismatch did not just add
  noise — `mismatchedEver` was non-empty, `accept` was false, and the operator's
  live acceptance pass could never go green on a page whose composer renders
  correctly. `prompt-editor` is back on `DECLARED_UNPROVEN_ACCEPTANCE`, where it
  stays non-accepting and honestly unexamined until a live run names its token —
  the same rule the tool already applies to the other nine. This repairs a red
  gate: `tools/test-inspect-web-cdp-live.js` was failing in `tests/Run-Tests.ps1`.
- **The BetterDiscord locale gate checked one plugin out of four.** The gate
  derives which plugins ship and requires each to have a
  `Get-BdPluginDescription` case — then, for the locale check immediately below,
  it tested the frozen literal `BdHideEmbedsDesc` and no other. The case regex
  accepts any `Bd\w+Desc`, so a fifth plugin pointing at `BdFooDesc` passed the
  derived half while `BdFooDesc` existed in zero of the 33 locales: 33 silent
  English fallbacks, gate green at exit 0. The key is now read out of each
  installer's case and required in all 33 locales, so the check covers every
  plugin that ships rather than the one that happened to be named. The shipped
  tree was already correct; this closes the gap for the next plugin.

### Added

- **`tools/test-chatgpt-viewport-coverage.js`** — the gate the two existing
  ChatGPT gates structurally cannot be. `test-chatgpt-2026.js` and
  `test-chatgpt-perf-css.js` read RULES; they prove the October contracts are
  present in the sheet ChatGPT actually receives. The defect above is not a
  missing selector, so both stayed green straight through it. This gate drives
  real Chromium, injects the Golden Default sheet AFTER a stock sheet that
  reproduces the shell with an opaque `#000000` scroll container, and asks
  what colour a user actually sees in the centre of the viewport by walking to
  the first ancestor that paints something opaque. It covers five viewport
  states (empty new chat, populated, composer focused, sidebar expanded, and
  the band below a short conversation region), asserts the stock build
  reproduces the defect before asserting the themed build fixes it, and asserts
  that message embed chrome is identical themed and unthemed. Four red
  controls: remove only the scroll-container rule (every parent contract
  survives), remove only the fade scope, replace the palette token with
  `inherit`, remove the whole sheet. Each control verifies that its own cut
  removed what it claimed and left standing what it claimed to keep, so a
  control cannot go red by cutting too much.
- **`tools/inspect-web.js` — viewport ownership and an opaque-surface audit.**
  Every probed surface now reports its bounding rect, viewport coverage ratio,
  computed `background-color` / `background-image`, and its nearest opaque
  ancestor. A new `opaque` command walks the tree and lists every opaque node
  covering at least `WINTAGE_OPAQUE_MIN` (default 10%) of the viewport, exiting
  non-zero when any remain — which is the "large opaque stock area in the
  centre of the viewport" acceptance condition, measured rather than asserted.
  Colour attribution is gated on Wintage actually being live (host stamp plus
  injected sheets); when attribution is off the report says so and credits
  nothing to Wintage, because switching the theme off is the only thing that
  can prove the cascade. It emits structural identity only — never text,
  conversation titles, message content or URLs.
- `tools/inspect-web.js` gains an `app-scroll-container` surface
  (`CONTRACT.ALWAYS`) bound to `--chat-background-color`, so the viewport owner
  is a first-class row in the existing matrix rather than an ad-hoc probe.

### Fixed (BetterDiscord media-control repair + HideEmbeds)

- **RemoveStickers 1.1.0** and **RemoveGIFS 1.1.0** were silent no-ops against
  current Discord. Both matched generated hashed class substrings
  (`[class*="stickerNode-"]`, `[class*="messageContent-"]`,
  `[class*="gifButton-"]`, and seven more) that no longer exist. The selectors
  stayed syntactically valid, so every check passed while the plugins hid
  nothing. RemoveGIFS additionally swallowed its own failures with empty
  `catch {}` blocks in `start()`, in observer processing and in the DOM checks,
  so a broken probe reported healthy.
- Both plugins now resolve media through a three-tier contract ladder, in this
  order: stable semantic DOM contracts (the message list and item roles, the
  `message-content-` / `message-reference-` / `components-` id prefixes, URL
  shape and content), then `BdApi.Webpack` module discovery that reads a live
  class token out of Discord's own module source at runtime, then a narrowly
  scoped structural fallback. The generated-token tier exists only after
  discovery — no current hash suffix is hardcoded anywhere, which is what
  would have recreated the same defect at the next Discord hash.
- RemoveStickers no longer hides accessibility UI that merely mentions
  "sticker" in an `aria-label`, and a message row now collapses only when the
  plugin itself owns hidden media in it. Previously any sibling plugin's hidden
  media could collapse the row, so in reverse start order stopping HideEmbeds
  left a restored image inside a collapsed row.
- A Discord-proxied animated GIF is identified from `?animated=true` and
  `?originalUrl=...gif`, not from a literal `.gif` suffix on the visible URL.
  Provider hosts (Tenor, Giphy) are corroboration only and can never classify a
  node on their own.
- Plugin startup failure now emits exactly one concise console warning and marks
  the settings panel DEGRADED. Health reporting names which contract tier is
  live (semantic / runtime module / fallback) and how many items were hidden.
  No message text, attachment URL or user ID is logged.
- Wintage uninstall disabled plugins by three hardcoded names, so the fourth
  plugin shipped enabled in BetterDiscord after an uninstall. Discovery is now
  dynamic over `desktop/targets/betterdiscord/plugins/*.plugin.js`, so plugin
  number five is covered too. Unrelated third-party plugin state, including
  nested objects, is preserved byte-for-byte in `plugins.json`.

### Fixed

- **HideEmbeds 1.0.0 hid Discord's own interface.** This is the screenshot
  regression, and 1.0.0 is the version that introduced it — not 1.1.0, which is
  the version that fixes it. Its `classify()` ruled out stickers, GIFs,
  `/emojis/` URLs and `/avatars/`+`/icons/` URLs, and then returned
  `inline-preview` for everything else, with `hidePreviews` defaulting to true.
  Two whole classes of image fell into that remainder:
  - **Role icons and badges.** The identity rule required a slash before
    `icons`, and Discord serves role icons from `/role-icons/`, so it never
    matched.
  - **Every emoji GoodEmoji had rewritten.** GoodEmoji moves emoji `<img>`
    sources onto `cdnjs.cloudflare.com/.../twemoji/`. That is not Discord's
    `/emojis/` path, so a rewritten emoji stopped looking like an emoji to
    every sibling classifier at once.

  Both were then hidden, and the placeholder was inserted as a sibling of the
  leaf `<img>` — inline — so one ordinary message produced a run of
  `IMAGE HIDDEN  Show  Open original` fragments through its own text.
- Classification is now **positive and fails open**. HideEmbeds hides a node
  only when it is positively identified as `ATTACHMENT_IMAGE` (Discord's own
  `/attachments/` path), `EMBED_IMAGE` (the media body of a link to an external
  source), `VIDEO` (carrying that same evidence, and only with *Hide videos* on)
  or `RICH_EMBED` (opt-in). `UNKNOWN` is never hidden. Nothing is inferred from
  a hashed Discord class, an alt string, a pixel size, or "it is somewhere in a
  message row". Explicit vetoes cover avatars, reply avatars, avatar
  decorations, role/clan icons, bot and application icons, badges, server and
  channel icons, forum/thread icons, provider and favicon icons, inline and
  reaction emoji, GoodEmoji output, stickers, GIFs owned by RemoveGIFS, plugin
  UI, and anything inside a button or a header.
- The placeholder now occupies the same **block** the media occupied. The marked
  element is the anchor wrapper (or the bare `<img>`), and the strip is inserted
  as that block's next sibling. It can no longer land inside a text span, the
  username/header row, an inline emoji run or a reaction row.
- **Open original** appears only when a real attachment/media anchor exists. It
  is never manufactured from `img.src`; emoji, avatars, badges and provider
  icons all carry a `src` and none of them has an original.
- The placeholder label is now the filename Discord's own attachment path
  states, and nothing else. v1.0.0 promoted `alt` text and scraped `width`/`height`
  out of the src query string, which is how an accessibility label such as
  *Role icon, Buffy's Lil Helpers* could appear where a filename belongs. No
  real filename means no label.
- **GoodEmoji 1.1.1** stamps `data-w95-owner="emoji"` on every image it
  rewrites, the same contract RemoveStickers (`sticker`) and RemoveGIFS (`gif`)
  already used. Any sibling that sees a foreign owner now leaves the node alone
  before it classifies anything, so HideEmbeds cannot offer a Show button that
  would resurrect a GIF or a sticker another plugin is holding down.
- **RemoveStickers 1.1.1** and **RemoveGIFS 1.1.1** skip anything inside a
  `[data-w95-plugin-ui]` root in both the observer and the row-collapse check.
  A sibling's placeholder is UI, not media, so the four plugins no longer wake
  each other on their own insertions. No detection rule changed in either.
- HideEmbeds no longer polls for the message list. One observer on `#app-mount`
  covers both finding the list and noticing that Discord swapped it on a route
  change, replacing a 1 Hz interval and a second observer. An idle page performs
  no work.
- The installer gate no longer hardcodes HideEmbeds' version: it reads the
  plugin header, so a version bump cannot leave the locale descriptions
  asserting a build that no longer exists.

- **HideEmbeds 1.1.2 — the "Hide rich link preview cards" checkbox did nothing
  with all four plugins on.** The setting panel was built with
  `check('hideRich', s.sHideRich)` while the runtime reads `hideRichCards`, so
  the control was bound to a key that does not exist: toggling it wrote
  `settings.hideRich`, and no rich card was ever hidden. Toggling it off and on
  again now also re-runs the pass, because the row stamp from the first pass is
  cleared first instead of being treated as "already decided".
- **The rich-card pass was silently skipped whenever a sibling had seen the
  row first.** All three plugins stamp the SAME attribute name
  (`data-w95-scoped`) with their own owner value, so `row.hasAttribute(...)`
  read a `RemoveStickers` or `RemoveGIFS` mark as "HideEmbeds already handled
  this row" and returned before classifying anything. Each plugin now compares
  the attribute VALUE to its own owner token, so a sibling's mark no longer
  decides another plugin's verdict.
- **A typed hyperlink inside message text was classified as a rich card.** The
  old test was "an external link plus some text", which every ordinary message
  containing a URL satisfies. A card must now be positively identified and is
  never taken from inside `[id^="message-content-"]`; an ordinary hyperlink
  never qualifies and `UNKNOWN` stays visible.
- **Blurred-preview mode was inert.** Its CSS selected the media through a
  previous-sibling combinator, but the placeholder strip is inserted AFTER the
  media block, so the rule never matched. The visual state is now an explicit
  `data-w95-visual="blurred"` attribute on the marked block, which the DOM state
  exposes directly and is therefore independently testable.
- **RemoveStickers 1.1.2** and **RemoveGIFS 1.1.2** no longer run a 1 Hz
  `setInterval` route poll. Both use the same low-idle architecture HideEmbeds
  already had: one observer that finds the message list and notices a route
  change on its own, with no per-timer work on an idle page. Neither plugin adds
  an independent full-body observer.
- **RemoveStickers 1.1.2** and **RemoveGIFS 1.1.2** collapse a message row only
  when ALL intentionally hidden meaningful media in it belongs to that same
  plugin. A row that also holds a sibling's hidden media is left as a visible
  shell rather than being collapsed out from under it. The ownership guard is
  load-bearing only when the remover starts last — with the live start order a
  plugin evaluates the row before its siblings have hidden anything — so the
  regression matrix covers both.
- **HideEmbeds 1.1.2** re-runs the per-message media bar reconciliation after a
  single item is revealed or concealed by hand. The bar used to keep a stale
  "Show all" above media the user had already brought back, and never grew a
  second bar.
- **HideEmbeds 1.1.2** session-wide *Reveal all* / *Hide all* skip message-level
  bars. They iterate `[data-w95-ph]`, which also matches the per-message control
  strip; a bar is a control, not a media placeholder, and treating it as one
  made a session action operate on somebody else's media.
- **HideEmbeds 1.1.2** moves the legacy loose classifier behind an Advanced
  two-step arm-and-confirm switch with an explicit warning, and normalises any
  imported or persisted `strict: false` value through that same confirmation.
  A stale value from an older install can no longer silently re-enable the
  destructive catch-all.
- Both removers' settings-panel title read `1.1.1` from a `VERSION` constant that
  had not been kept in step with the `@version` header, so the panel reported a
  build that did not exist.

### Added

- **HideEmbeds: "Strict media classification" (default ON)** with an explicit
  warning that legacy loose detection may hide Discord UI images. Turning it
  off restores the v1.0.0 catch-all as a labelled compatibility escape hatch.
- **HideEmbeds: "Show diagnostics" (default OFF).** Logs classification, owner,
  reason and a structural shape summary only. Message text, usernames, user and
  channel ids and attachment URLs are never logged.
- The settings panel now reports how many images were left visible because they
  could not be positively identified, alongside the hidden count.

- **HideEmbeds 1.0.0** hides image attachments, embedded images and
  link-derived image previews by default, leaving avatars, server and channel
  icons, emoji, reaction emoji, UI icons, profile images, banners and non
  message images alone. Video attachments and rich link preview cards are off
  by default.
- Hidden items get a compact Wintage placeholder offering Show and Open
  original, with filename, media type and dimensions when Discord already
  provided them. Raw URLs are never rendered. Reveal happens in place with no
  message reload and no re-fetch; the blurred-preview mode reuses the existing
  image element through a CSS filter instead of loading the asset twice. A
  per-message "Show all media" control appears only when a message has two or
  more hidden items.
- Per-item reveal state is session-only and is never written to `BdApi.Data`;
  only the settings persist. Settings take effect immediately without a restart.
- Reveal controls are real buttons: keyboard reachable, Enter/Space activated,
  `aria-expanded` where meaningful, visible focus ring, and never hover-gated.
- Ownership between the three plugins is decided by classification, not by start
  order (stickers, then GIFs, then everything else), so media intentionally
  banned by one plugin never gains a Show placeholder from another. Ownership
  markers are deterministic attributes on the media nodes themselves and are
  removed on stop; stopping one plugin never reveals media another still owns.
- `BdHideEmbedsDesc` added to all 33 locale files, so installer locale parity
  holds.

### Tests

- `tools/test-bd-media-contract.js` is the contract gate for this wave: one
  section per repaired defect, driving the four real plugin sources in a real
  Chromium. It carries EIGHT red controls. Each rebuilds the pre-repair source
  with a single anchored string replacement — asserted to differ from, and to
  be present in, the shipped bytes — and then REQUIRES that section's own
  assertions to go red against it. A section that cannot fail is not a gate, so
  the harness exits 0 only after proving each defect still exists in mutated
  form.
  - the settings control is located by its LABEL and clicked through a real DOM
    `change` event, never by index and never by calling `setSetting()`; the
    oracle binds it back to `hideRich` and must be caught red
  - the P1-5 matrix runs every plugin STOP permutation across two START orders
    and six row shapes (sticker+GIF, sticker+image, GIF+image, sticker+GIF+image,
    plus a sole-owner control for each remover). The sole-owner rows must still
    collapse BY THEIR OWN OWNER under the guard mutation, so a green run cannot
    be explained by "stop collapsing rows" instead of "stop stealing rows"
  - a stopped plugin's media must come back somewhere VISIBLE, not merely
    present: a row collapsed by a sibling reports every descendant as hidden, so
    presence alone cannot tell a correct sibling hold from a restored item
    trapped in a dead row
- `package.json` declares Playwright as a pinned dev dependency with a single
  documented bootstrap command (`npm ci`). `node_modules/` is git-ignored and
  never shipped; an end user installing Wintage never needs Node.
- `tools/test-remove-stickers.js`, `tools/test-remove-gifs.js`,
  `tools/test-hide-embeds.js` and `tools/test-bd-coexistence.js` drive the real
  plugin sources in a real Chromium through Playwright rather than a hand-rolled
  fake DOM, because the behaviour under test is browser behaviour: selector
  semantics, `MutationObserver` batching, `classList`, focus and Enter/Space.
  The sticker and GIF suites carry in-process red controls that mutate the
  shipped URL regexes and require the gates to go red.
- `tools/test-betterdiscord-plugin-installer.ps1` extracts the real
  `Get-BdPluginsJsonPaths` / `Get-BdSourcePluginNames` helpers from
  `desktop/WintageInstaller.ps1` by AST and runs them against a scratch
  `%APPDATA%` with the `stable` and `ptb` channels, a fifth plugin, third-party
  plugins and nested state.
- All five suites are wired into `tests/Run-Tests.ps1`. They previously passed
  while being reachable from nothing, which is how the media plugins could have
  shipped broken with every wired gate green.

### Known limits

- Live acceptance against a running Discord + BetterDiscord is still owed: the
  installed Discord renderer bundle (`resources/app.asar`) is absent on this
  machine, so no offline contract verification was possible. Everything above is
  verified against the deterministic harness only.

## [1.36.6] - 2026-10-03

ChatGPT Web October 2026 shell refresh.

- The active ChatGPT stylesheet now binds the current shell's structural
  contracts alongside the September ones: `#web-mobile-root`,
  `[data-testid="desktop-app-shell"]`, `main[aria-label="ChatGPT"]`,
  `[role="region"][aria-label="Conversation"]`, the sidebar accessibility
  landmark (`role="complementary"` / `aside[aria-label="Sidebar"]`) and
  `#mobile-composer-prompt`. The central workspace, the sidebar and the prompt
  editor matched nothing on the current shell and fell back to stock #000 while
  Wintage's own overlays stayed themed.
- The September contracts stay as rollout fallbacks: a ChatGPT account can carry
  both generations in one document.
- Generated `x*` atomic class names are deliberately NOT bound. They are build
  output and are rehashed on every rollout, so binding to them would trade the
  static-CSS theme for a repaint loop. No `:has()`, no class-fragment and no
  universal selector was added; the lean CSS-only ChatGPT path is unchanged.
- `tools/test-chatgpt-2026.js` now validates `CHATGPT_FAST_CSS`, the sheet
  ChatGPT actually receives. It previously read `GLOBAL_CSS`, which the runtime
  never sends to ChatGPT, so the gate stayed green while the live theme was
  stock. `GLOBAL_CSS` keeps its compatibility copy and its presence can no
  longer make the gate pass. The gate carries a RED control that strips the
  October contracts out of the active sheet and requires the verdict to fail.
- `tools/test-chatgpt-perf-css.js` now requires the October contracts in the
  fast sheet, and bans generated atomic classes and `:has()` from both ChatGPT
  sheets.
- `tools/inspect-web.js` matrix updated: current contracts are primary and
  September contracts are rollout fallbacks. The current prompt editor and the
  current workspace surfaces carry proven token expectations; the unproven
  September composer container hooks became optional, because the current shell
  exposes no stable container hook and demanding it would make every live pass
  report a false failure.
- `tools/test-inspect-web.js` R7 now reads the active ChatGPT stylesheet, for
  the same wrong-sheet reason.

## [1.36.3] - 2026-09-29

ChatGPT typing and idle-performance hotfix.

- ChatGPT now receives a dedicated lean stylesheet instead of the universal all-sites stylesheet. The current semantic ChatGPT tokens, sidebar/composer/message/code hooks and Win95 surface treatment remain, while hundreds of global class-substring and universal typography selectors no longer participate in ChatGPT style invalidation on every React/editor update.
- ChatGPT shadow roots use a matching lean shadow stylesheet, preventing the universal shadow theme from reintroducing the same selector cost.
- Added `test-chatgpt-perf-css.js` to lock the fast-path selection, current ChatGPT hooks, and the absence of class-substring, `:has()` and universal all-element selectors from the ChatGPT fast sheets.
- The page diagnostic now reports `data-w95-perf-reason="chatgpt-lean-css"` when this path is active.

## [1.36.2] - 2026-09-28

ChatGPT Web September 2026 interface refresh.

- Rebuilt the ChatGPT host override around the current semantic surface contract
  instead of broad Tailwind/class-fragment selectors. The theme now maps the
  current chat, panel, sidebar, composer, message, code-block, text and border
  tokens directly to the active Wintage palette.
- Added current shell hooks for `#app-shell-sidebar`, `data-composer-*`,
  `data-user-message-bubble`, `data-markdown-copy`, the prompt editor and the
  redesigned pressed-state header controls. The new full-page settings and
  reorganized sidebar inherit the same palette rather than leaking stock ChatGPT
  charcoal surfaces.
- Kept the older `stage-*` sidebar and legacy semantic aliases as rollout
  fallbacks. ChatGPT frequently mixes old and new surfaces while an account is
  being migrated, so the theme now handles that state deliberately.
- Removed the old broad composer/bottom-bar strategy from the ChatGPT override.
  The thread footer fade is also pinned to the themed conversation background so
  long chats do not end in an unthemed dark strip.
- Added `test-chatgpt-2026.js`, a static regression gate that requires the current
  semantic hooks/tokens and rejects the retired broad ChatGPT selectors.

## [1.36.1] - 2026-09-28

Host-exclusion and installer-locking fixes, plus the generated test surface that
now covers them.

- The exclusion list no longer treats bot challenges and anti-fraud token
  providers (Arkose Labs, FunCaptcha, Cloudflare Turnstile, Kasada, PerimeterX)
  as heavy web apps, so form and reply submissions on X/Twitter and elsewhere are
  no longer broken by the theme. Five flipbook/reader hosts (Publuu, Issuu,
  FlipHTML5, Yumpu, Heyzine) join the same list, where a repaint destroys the
  canvas UI.
- A local dev server is no longer classified as a high-churn chat SPA. Folding
  `IS_LOCAL` into `HIGH_CHURN_HOST` silently disabled surface remapping, the
  floating-panel solidification and the hover surgery on exactly the host most
  likely to be inspected. `chatgpt.com` and `openai.com` now match by domain
  rather than by substring.
- W2-002 (audit/7 T-269): inherited ownership of the cross-runtime build
  generation lock is now proven rather than declared. The inheritance marker
  carries the owning acquisition's token and is honoured only while that live
  holder still owns the lock; a forged, stale or leaked marker acquires normally
  instead of short-circuiting the lock.
- W2-005: `processexplorer` is a remembered portable folder (procexp can live
  anywhere), so it joins `PATHS_KEYS`, the GUI `PATH_TARGETS_MAP` and the single
  `-ProcessExplorerPath` argument. The two `paths.json` writers now share one
  strict reader, so a present-but-unreadable document fails closed in both
  instead of being normalized away in one of them.
- 33 locale files and the generated Electron payload carried through unchanged.
- New test surface: `test-transaction-boundary.ps1`, `test-reapply.ps1`,
  `test-spa-exclude.js`, `test-terminal-font.js`, `test-theme-packs.js`,
  `test-theme-switch.js`, `test-repainter-budget.js`.

## [1.36.0] - 2026-09-16

Audit wave: `audit/5.md` (SRC-007) fully executed — all 15 clauses verified
(T-246) — plus the Total Commander recovery migration (T-245).

- PERF-002: the renderer repainter no longer re-walks the document and every
  pierced shadow root without bounds. It keeps a persistent incremental root
  cursor, separates the style lane from the DOM element budget (own root, sheet
  and rule budgets), walks CSSOM iteratively with a resumable stack, treats
  dirty style work as scheduler debt instead of a synchronous scan, and
  invalidates STYLE owner text lazily. Pages with many shadow roots stop paying
  an unbounded synchronous sweep on every mutation.
- PERF-004: portable browser detection and profile enumeration are cached. A
  remembered portable browser root is walked once and afterwards served from a
  persisted candidate cache — re-validated cheaply, invalidated when the root
  changes, when a cached browser has disappeared, or on an explicit rescan
  (`install-browsers.ps1 -Rescan`, `install.ps1 -RescanBrowsers`) — so opening
  the installer and every Apply/Revert refresh no longer rescans an arbitrary
  subtree. Chromium `Preferences` files are matched with a bounded chunked
  search instead of being read whole, and an unchanged profile is never
  reopened.
- PERF-003: an Electron palette repaint no longer performs archive-sized
  recovery I/O at both transaction layers.
- PERF-001: the legacy wide-push, intake and test-hook branches are gone from
  the generated Electron shim, and its instrumentation is lazy.
- CORE-003: Windows theme mutation is encapsulated in one rollback boundary,
  and the Total Commander recovery format is transactional and schema-strict.
- R009/R010/R011: one cross-runtime build-generation lock (the PowerShell side
  now lives in `desktop/modules/generation-lock.ps1`), deterministic red
  controls for the batch GUI, and explicit portable-root path-preference
  ordering before any mutation.
- BetterDiscord: optional `RemoveGIFS` plugin template.
- Tests: dedicated suites for the repainter budgets
  (`tools/test-repainter-budget.js`), the browser cache
  (`tools/test-browser-cache.ps1`) and the generation lock, all wired into
  `tests/Run-Tests.ps1`.

## [1.35.1] - 2026-09-11

- ZCode usage popup (user request): the "5 hours" quota label is now bold light
  orange so the everyday-quota column reads as distinctly as Weekly (green) and
  ZCode MCP (red). CSS cannot match text, so the column is picked by its inline
  `--color-usage-chart-1` bar marker (Weekly is chart-2, MCP chart-5); the colour
  is a palette color-mix (borderHighlight/dangerText), so every theme derives its
  own warm highlight with zero hardcoded hex.

## [1.35.0] - 2026-09-11

- Audit repair & feature convergence (T-242/T-243): SRC-006 audit layer executed with all 10 findings terminal VERIFIED; SRC-006 closed and archived.
- BetterDiscord plugin support in Wintage Installer:
  - New dedicated tab for BetterDiscord plugins with live discovery, description panel, install, and uninstall capabilities.
  - Added GoodEmoji plugin: transforms negative, crying, sad, and toxic emojis into cheerful, funny, and neutral ones across chat, reactions, and tooltips (75+ replacement rules including innuendos, feces, crosses, and weapons).
  - Added RemoveStickers plugin: completely removes sticker rendering from Discord to eliminate clutter.
  - Tab navigation overhaul: replaced native Windows SysTabControl32 with pure Win95 flat tab buttons and panels, eliminating unskinnable OS visual-styles white frames and borders.
  - Themed language ComboBox: owner-drawn with FlatStyle to strictly obey Golden Default tokens without white-background bleed.
- Targets & tooling:
  - Added ZCode support to installer targets.
  - Added Notepad++ and Cinema 4D templates and targets.
  - Fixed installer batch timer null safety and completion handler wrapping.
  - Added force-sweep root budget and persistent traversal cursors (SRC-006:R010).
  - Bounded Electron repaint I/O proportional to mutation sets (SRC-006:R007).
  - Added logon-task checkbox init/reentrancy guard (SRC-006:R006).
  - Reapply intent revalidation under target lock (SRC-006:R005).
  - VS Code-family recovery epoch with pristine tombstone restore (SRC-006:R004).

## [1.34.0] - 2026-09-10

- Audit repair: the external audit inbox layer audit/3.md (SRC-005, 17 findings) is executed as T-241. All 17 findings are terminal VERIFIED with evidence; SRC-005 is closed and archived (E-882).
- Fixed (userscript, R001/CORE-001): a cancelled `beforeunload` during a theme switch left the old palette painted while GM storage already held the new one, with no warning and no way forward. A pending-theme probe now detects the refused navigation and surfaces it.
- Fixed (userscript, R002/CORE-002): the route-guard latch was one boolean committed before any hook installed, so one transient `pushState`/`replaceState`/listener failure permanently suppressed reinjection repair and same-document SPA navigation could enter OAuth/captcha/payment routes unguarded. The latch is now a per-hook state object that installs each component independently and retries only what is missing.
- Fixed (installer, R003/CORE-003): `Restore-DirPreState` returned success when its snapshot was missing, and deleted the authoritative snapshot from an unconditional `finally` on materialization failure. It now fails closed and consumes the snapshot only on a known-good restore.
- Fixed (release gate, R004/CORE-004): `import-fastprompter.js --check` exited 0 printing "freshness check skipped" when no upstream checkout was available, so a hand-edited imported theme pack passed the release freshness gate that exists to catch it. Every imported pack's import-derived content is now recorded as a sha256 fingerprint (`tools/fastprompter-fingerprints.json`); `--check` without a source reproduces-and-compares each pack and fails closed on drift or a missing fingerprint file. New gate `tools/test-import-freshness.js` (11 assertions) wired into `tests/Run-Tests.ps1`.
- Fixed (installer, R005/W2-001): a multi-vault Obsidian Apply/Revert rolled back only the currently failing vault, leaving earlier vaults themed with an unadvanced manifest and swallowed per-vault errors. The operation now captures pre-state for every vault up front, breaks at first failure, and restores every touched vault with aggregated rollback errors.
- Fixed (installer, R006/W2-002): nine handler groups still mutated live state AFTER the snapshot but BEFORE `Invoke-TargetCommit`, so a throw in that window left the target half-changed with an unchanged manifest and the rollback callback never ran. All live mutations now sit inside the commit scriptblock; a new structural guard (w2002) scans every Save-*PreState -> Invoke-TargetCommit window for mutation primitives.
- Fixed (installer, R007/W2-003): SmartVac/WildRift/Saipenview Revert removed the manifest entry before the fallible backup deletion; a failure after the removal restored the target while the entry was permanently gone. The retire-first tombstone protocol renames to a tombstone before the commit, garbage-collects after, and restores on manifest failure.
- Fixed (installer, R008/W2-004): recovery artifacts and provenance were written directly to final names and later gated by existence, so a crash mid first-touch/rebase poisoned the authoritative recovery state. `Write-Utf8Atomic`/`Copy-FileAtomic` now stage through unique same-dir temps; orphan temps are swept at first-touch and are never authority. New gate `tools/test-atomic-recovery.ps1` (19 assertions) wired into `tests/Run-Tests.ps1`.
- Fixed (installer, R009/W2-005): `Restore-WindowsPreState` suppressed registry/file removal failures with `SilentlyContinue`, never verified the `CurrentTheme` restoration, and its caller then reported exact pre-operation state unverified. It is now a top-level verified rollback primitive: checked mutations, read-back verification, a bounded CurrentTheme convergence poll, and an aggregated throw naming every failing resource. New gate `tools/test-windows-prestate.ps1` (45 assertions) wired into `tests/Run-Tests.ps1`.
- Fixed (installer, R010/W2-006): the Obsidian `cssTheme` recovery conflated explicit JSON null with an absent property, and Revert parsed recovery JSON without schema validation, so a wrong-shape payload like `{}` followed the false branch and deleted a live `cssTheme` value. The serializer now writes `{present,value}` and every reader validates strictly.
- R011-R017 (PERF-001..007) were repaired in v1.32.0/v1.33.0 under T-234/T-240 and carry their evidence there.
- Terminal (shared with the next audit layer): `install-terminal.js` finalize now consumes marker + backup/created together after the committed manifest transition, and `revert --dry-run` answers the same fail-closed preconditions as the real revert.
- New release gates, wired into `tests/Run-Tests.ps1`: tools/test-import-freshness.js, tools/test-windows-prestate.ps1, tools/test-atomic-recovery.ps1; grown: test-theme-switch.js, test-spa-exclude.js, test-dir-prestate.ps1, test-recovery-consumption.ps1, test-terminal-recorded-set.ps1, test-transaction-boundary.ps1. tests/Run-Tests.ps1: ALL TESTS PASSED.

## [1.33.0] - 2026-09-05

- Fixed (PERF-005, SRC-004:R017, T-240): the installer GUI spawned one BLOCKING install.ps1 child per checked target on the WinForms thread, re-ran `node tools/build-desktop.js --check` once per target, and re-scanned every Electron executable for the fuse sentinel on each listing. install.ps1 now takes a `-Selected "a,b,c"` batch set that feeds the same `$names` dispatcher in ONE worker process with ONE shared build verification (explicit StrictTarget semantics, de-duplicated, validated against the known set); the fuse verdict is cached on disk keyed on exe path+size+mtime and fail-closed (any change or doubt rescans); the GUI runs ONE async batch worker per Apply/Revert via Start-Job plus a Forms.Timer so the window stays responsive, with per-target failure parsing preserved. Single-target CLI and `-Target all` behaviour are unchanged.
- SRC-004 closes with this release: all 19 findings terminal VERIFIED with evidence (18 in v1.32.0 under T-234, PERF-005 here under T-240).

## [1.32.0] - 2026-09-04

- Audit repair: the external audit inbox layer audit/2.md (SRC-004, 19 findings) is executed as T-234. 18 of 19 findings are terminal and VERIFIED with evidence. PERF-005 (R017) is split to T-240 with its own verify bar: it is the installer GUI dispatch model (one blocking install.ps1 child per checked target on the WinForms thread, one redundant build-desktop --check per target, an uncached fuse rescan of every Electron executable), whose repair can only be verified by process count and UI responsiveness during a live multi-target Apply -- a fixture would measure the fixture.
- Fixed (CORE): Revert could not reconstruct the pre-Apply Windows Terminal document (R001/CORE-001). The owned-state snapshot encoded each profile VALUE but not its PRESENCE, never captured the legacy profiles-array shape, and Revert permanently deleted a pre-existing user scheme named Wintage instead of restoring it. The snapshot now records presence separately from value (schema 2), understands both config shapes, and Revert restores a user's own same-named scheme byte-for-byte.
- Fixed (CORE): an Electron relocation Revert still left the root app.asar.unpacked rename undone on rollback (R002/CORE-002): the revert pre-state carried no root-unpacked field and the rollback-complete decision ignored it, so an incomplete rollback could claim exact restoration. The unpacked rename is now captured, restored first, and compared.
- Fixed (CORE): beyond the reload latch, the userscript still repainted an excluded URL (OAuth, captcha, payment, banking) in place (R003/CORE-003). The exclusion guard now quarantines the route per URL and suspends the repainter for the life of that document, and the pending-theme menu predicate is reachable as written.
- Fixed (CORE): a present-but-empty `Key=` in the terminal INI round-tripped as absent (R005/CORE-005). `$null` is now the ONLY absence sentinel in both ownership restorers, so an empty owned value survives Apply and Revert instead of being dropped.
- Fixed (W2, installer lifecycle): the windows-theme epoch now finalizes only on success (R006/W2-001); OBS recovery parses robustly with the correct case handling (R007/W2-002); the install-epoch first-create path is race-free when two processes claim it at once (R008/W2-003); the transaction boundary covers preflight for the VS Code-family extension, OBS and qBittorrent Apply/Revert paths (R009/W2-004); every rollback step reports its own failure and an incomplete rollback says so (R010/W2-005); first-touch recovery creation moved INSIDE the ShouldProcess gate so -WhatIf performs zero writes (R011/W2-006); and paths.json updates are serialized instead of racing (R012/W2-007).
- Fixed (PERF-001, R013): install-electron recovery stacked whole-binary Buffers across BOTH transaction layers -- the same moved archive resident twice, measured at +192 MiB RSS for a 64 MiB app precisely during Apply/Revert. Recovery is now a durable on-disk vault plus in-memory identity (size + streamed SHA-256 through a 64 KiB window), so peak RSS stays approximately FIXED as the recovery set grows (16/64/256 MiB fixtures: 47.1/48.0/48.3 MiB) and recovery evidence survives an incomplete rollback, named in every INCOMPLETE message.
- Fixed (userscript, PERF-002/003/004/006/007, R014/R015/R016/R018/R019): every advertised repaint/injection budget is now enforced at the moment it is named. Mutation intake stops the instant the budget is spent instead of iterating on; the light lane consults the budget before materialising the whole not-done NodeList and no longer costs two sweeps for one isolated request; detached shadow roots leave the shared observer; resize events no longer queue one full layout scan each; and same-document SPA navigation carries a document epoch plus a CSS key so stylesheets can never stack.
- New release gates, wired into tests/Run-Tests.ps1 and release.ps1: tools/test-perf-recovery.js (56 assertions, builds the audit's own fixture sizes and reads the child's peak RSS), tools/test-perf-lanes.js (44 assertions, slices the real userscript and counts primitives), tools/test-transaction-boundary.ps1 (77 assertions, drives the REAL installer and helpers as child processes), plus tools/test-recovery-lifecycle.js and tools/test-terminal-ownership.js. tests/Run-Tests.ps1: ALL TESTS PASSED, 14 of 14 tool suites.


## [1.31.0] - 2026-09-03

- Fixed: **data loss** in the Electron relocation revert (T-235). Reverting a relocated install deleted `app/` before rolling back, then wrote into the now-missing directory and removed the live root archive, so a failed rollback could leave neither `app.asar` nor `app/app.asar` on disk - while the tool printed "restored the exact pre-operation state". The snapshot never captured the archive itself, and the PowerShell side classified a themed-relocated target as repaint-only, so the parent snapshot omitted it too. The archive and its `.unpacked` directory are now snapshotted recursively and compared byte-for-byte, the lightweight snapshot path is opt-in rather than inferred, every rollback step reports its own failure, and an incomplete rollback says so and names the surviving recovery locations instead of claiming success.
- Fixed: one refused reload permanently disarmed the URL exclusion guard (T-235). `window.__wintageExcludedReload` was set before `location.reload()` and never cleared when the navigation was refused, so the theme kept mutating OAuth, captcha, payment and banking UI for the rest of that document - the same defect class as the palette-switch split brain fixed in 1.30.0, in the place it matters most.
- New: Google Search and Material 3 surface coverage (T-236), behind a `data-w95-google` host flag - the Material tokens (`--color-surface*`, `--m3c-*`, `--g-*`) and the AI Overview surfaces now follow the active palette instead of staying white. Also broadened: Tailwind `prose` and `text-token-*` text variables, Reddit post titles, overlays and stretched click-catchers, and heading/bold/small colour on ordinary pages.
- Fixed: the repainter solidified overlays sitting on top of video, canvas and images, and repainted SVG interior nodes and icon glyphs (T-236). Icons inside buttons keep `currentColor`, media-stack overlays are left alone, and click-catchers that share a card with their target no longer get a bevel painted over the text.
- Changed: the generic mutation circuit breaker now allows 10,000 records / 600 ms per 2 s window (was 3,500 / 300 ms), so heavy SPAs stop tripping it during ordinary navigation; the light sweep lane is bounded by the same global budget as the force lane and re-arms when it runs out of budget instead of leaving dirty nodes unpainted.
- Fixed: the release-wired theme-switch gate was **red on the tree** (T-236). It slices the real userscript and evaluates it under stubbed globals, and the new `IS_GOOGLE` host flag was used inside the slice while the harness context never declared it, so every case died with a `ReferenceError` before the first assertion - `release.ps1` could not have released this tree at all. Harness contract repaired and three host-attribute assertions added; 44 assertions now run.
- Docs: the 32 translated READMEs moved to `locales/`, with a collapsible language table in the root README, and the wiki mirror is stamped 1.30.0.
- Protocol hygiene, no user-visible effect (T-237): the superseded 41-ticket audit receipt SRC-001 recorded an uppercase digest while every gate hashes the body, so the conformance gate had been failing on it since 2026-08-25. Routed through the normal close/archive lifecycle with the body retained.

## [1.30.0] - 2026-09-02

- New desktop target: **qBittorrent** (T-228). Installs an unpacked Qt UI theme into `%APPDATA%\qBittorrent\themes\wintage` — a `config.json` carrying the `Palette.*` roles plus qBittorrent's own context colours (all 18 transfer-list states, the 6 log severities) and a `stylesheet.qss` carrying the Win95 geometry — then points `General\CustomUIThemePath` at it and sets `General\UseCustomUITheme=true`. Unpacked rather than a packed `.qbtheme` on purpose: a `.qbtheme` is a Qt Resource Collection file and would need a matching-major-version `rcc` binary on the machine, i.e. a compiler dependency for two text files. Revert restores both INI keys to their exact pre-Wintage values (or removes them if they were absent) and puts back any same-named theme folder byte-for-byte; unrelated `qBittorrent.ini` edits made after Apply survive. The target refuses to run while qBittorrent is open, because it rewrites the whole INI on exit and would discard the selection.
- New font policy, stated rather than implied (T-228): `qbittorrent` and `obs` name `Verdana_m1, Verdana` in their stylesheets and `mpchc` names whichever of the two the machine actually resolves — but **Wintage never installs or uninstalls a font**. A font family resolves by (family, style), so deregistering one member re-points every consumer at a surviving member; on a machine that aliases `MS Shell Dlg 2` onto that family through `FontSubstitutes`, removing Regular turns the entire desktop italic until a logoff. Installing the face stays a one-time explicit user action, and the targets say so once when it is missing.
- Fixed: the SPA safety guard was not idempotent (T-225). A second run in the same document — an in-place Tampermonkey update, a manual re-inject, a manager re-evaluating on same-document navigation — wrapped the first `history.pushState` wrapper, so the guard fired twice per transition and stacked one extra `popstate`/`hashchange` listener per pass, invisibly and permanently.
- Fixed: a refused reload left the theme switcher in a silent split brain (T-226). The palette is written to GM storage before the reload, so a cancelled `beforeunload` or a host that blocks programmatic navigation left storage on the new palette while the page kept painting the old one, with nothing on screen saying so. The failure is now stated once, and a `⟳ Apply pending theme` menu row appears whenever storage names a palette this document is not painting.
- Fixed: four `catch` blocks in the hover-CSSOM surgery and the shadow-root pierce swallowed real failures silently (T-227). Their visible symptom is "the site's hover highlight is still there", which is indistinguishable from a missing feature. The swallows are now counted and reported through `window.__wintageDiag()`, with the first error retained; there is deliberately no per-throw logging, because a CSS-in-JS page would flood the console.
- Fixed: `install-electron` reported **every** Windows sharing violation as "the application is running - close it completely" (T-230). On Windows a file written milliseconds earlier is routinely still held by the AV scanner or the search indexer: measured on this repo's own fixtures, 1 of 60 isolated clean applies failed that way with no application anywhere. Two consequences — the release gate went red on correct code about one run in twenty, and a real user was told to close an app that was not open. Retriable codes now get a bounded backoff (25–400 ms, six attempts) on every mutating rename/copy in both transactions *and* their rollback steps; a genuinely locked archive still fails with the same correct message.
- Fixed: a release gate was stuck **red** on correct code for a full cycle (T-229). `tools/test-perf-bounded.js` required the `ColorDialog` allocation to sit inside the `try` — which is the defect it should reject, since an allocation there leaves the variable unassigned in `finally`. The earlier triage read that red as a missing fix. Assertion repaired, and the suite is now an actual release gate.
- Fixed: five test suites were reachable from nothing — neither `tests/Run-Tests.ps1` nor `release.ps1` (T-231). The contracts they pin (the directory pre-state snapshot shape, Windows Terminal's recorded-set health probe and its keep/finalize recovery ordering, recovery-consumption ordering, the install epoch, portable-Electron path precedence) could therefore regress through a release with every wired gate green. All five are now wired. One of them, `test-terminal-recorded-set.ps1`, also aborted on its own subject: the `--finalize-recovery` refusal it asserts arrives as a native stderr line, which PowerShell 5.1 promotes to a terminating error under `$ErrorActionPreference = 'Stop'`, so its last four checks had never run.
- Also shipped here, previously unshipped and unattributed in the working tree (found by this release's attribution gate, T-231): **PERF-008** the Electron fuse probe scans in bounded chunks instead of loading a whole multi-hundred-MiB executable into memory on every GUI listing refresh; **PERF-009** the installer GUI disposes its per-draw GDI handles deterministically instead of leaking them until GC; **W2-007** `install-terminal` keeps its recovery artifacts until the caller confirms every recorded item reverted, so a failure on item N leaves the earlier items rollback-able.
- Fixed: `release.ps1` could not release a dirty tree at all (T-232). Nine git calls whose output is read back — including the pre-release `stash create` snapshot — were written as bare `& git ... 2>$null`, bypassing the `Git-Safe` wrapper that exists for exactly this hazard: PowerShell 5.1 promotes a native stderr line to a terminating error under `$ErrorActionPreference = 'Stop'`, and `git stash create` emits one CRLF-conversion warning per converted file. The release died on a warning, before any mutation. All nine now route through a value-returning twin of the same wrapper.
- Three new release gates, each proven able to fail before being trusted: `test-spa-exclude.js`, `test-diag-counters.js`, `test-fs-retry.js`, plus `test-perf-bounded.js` wired in. Full matrix: `tests/Run-Tests.ps1` ALL PASSED with 9 tool suites inside it, 13 Node gates and 4 regeneration contracts green.

## [1.29.0] - 2026-08-29

- Audit repair: third-pass audit (SRC-002, 18 tickets) closed in one ship. Four CORE correctness defects (P0 mutex `WaitOne` timeout, Obsidian cssTheme recovery bytes, Terminal `historySize: 0` round-trip, Terminal/Obsidian effective Reapply state), seven lifecycle/atomicity defects across OBS, Windows theme, TotalCmd, FreeBuff, Electron fuse schema, and seven userscript performance defects (SCROLL_FIX bounded+coalesced, force-sweep global TreeWalker budget, `ADDED_NODE_BUDGET` enforced during collection, same-URL Electron reload doc-epoch reinjection, drainable light/force scheduler, FreeBuff-only AD_BLOCK/THEME_REASSERT, suspend clears `piercedRoots`). Net-new 10 tickets; 8 were already shipped in v1.28.x and verified-not-repaired. Full matrix: tests/Run-Tests.ps1 ALL PASSED (PS5.1), nine Node gates PASS (`shim-payloads`, `electron-state`, `electron-shim`, `repainter-polarity`, `theme-switch`, `theme-packs`, `terminal-font`, `build-desktop --check`, `check-css`).

## [1.28.1] - 2026-08-26

- Fixed: the console scrollbar could silently disappear from a command-line window (T-204). conhost rewrites `ScreenBufferSize` back into the registry whenever the window is resized, so a profile whose screen-buffer height collapsed to its window height had zero scrollback and no scrollbar, while the Wintage palette marker stayed intact and Reapply never noticed. Reapply now probes every console profile's buffer height against the 9001-line floor and re-asserts it when a profile has drifted below it. This also fixes a latent crash: a `Reapply` over a conhost or MPC-HC target used to throw `GetFullPath: format not supported` under Windows PowerShell 5.1, because the recorded `HKCU:\...` registry key is not a filesystem path.

## [1.28.0] - 2026-08-26

- New: the Windows console font is now **Terminus (TTF) for Windows** instead of Verdana (T-202). Proportional glyphs collide on a fixed cell grid; the new face is applied live to `HKCU:\Console` and six profile keys, and a gate pins that conhost and Windows Terminal agree on the same non-Verdana face.
- New: installer language selector (T-202). English is the default (never the system culture), the pick is persisted per machine to `%APPDATA%\Wintage\language.txt`, and the GUI offers a live `Language` combo. `install.ps1 -Language` hard-fails on an unknown code. 33 locales shipped.
- Fixed: `release.ps1` staged with `git add -A`, so any untracked file present at release time (a debug dump, a half-finished harness, a scratch file) would be published with it (T-201). A refuse guard now aborts the release and lists exactly what would have ridden along before anything is pushed; `.gitignore` covers the transient engine receipts that are safe to ignore.

## [1.27.0] - 2026-08-21

- New target: **WorkBuddy AI** (T-196). Electron app, discovered from a running `WorkBuddyAI`/`WorkBuddy`/`CodeBuddy` process or the usual `Programs\WorkBuddy*` locations, overridable with `-WorkBuddyPath` and remembered in `paths.json`. It is grouped with the portable/source apps in the GUI target list.
- Fixed: the GUI deleted every CLI-owned `paths.json` key (`codenomad`, `workbuddy`, `portable`) whenever the user picked a folder for one of its own targets -- the file was rebuilt from the GUI's key list instead of merged, so a remembered portable-browser root vanished on an unrelated save (T-196).
- Fixed: FreeBuff's `/api/ad/slot` orchestrator patch stopped matching after the app moved to `app.ads.slotAd(threadId, recent)`; the matcher is argument-agnostic now (T-197).
- Fixed: every desktop target failed with `manifest schema invalid: <target>.applied: not a string` under PowerShell 7 (T-199). PowerShell 6+ retypes timestamp-looking JSON strings into `[datetime]`, so the installer's own manifest was rejected before any work started. Manifest reads normalise those fields back to ISO-8601 UTC strings on every host; Windows PowerShell 5.1 behaviour is unchanged.
- Fixed two release gates in `tests/Run-Tests.ps1` that were red on correct code and blocked every ship (T-198): the terminal round-trip fixture compared a CRLF here-string against the tool's LF output, and the `$TARGETS`/`$ELECTRON` extraction regex stopped at the first nested brace, so fully wired targets (`workbuddy`, `codenomad`, `antigravity-app`, `vscode`) were reported as having no implementation.

## [1.26.10] - 2026-08-19

- Tampermonkey UI Bugfixes (T-195):
  - Fixed `::selection` highlight background not applying on some sites due to specificity; upgraded to `*::selection, ::selection`.
  - Fixed massive white un-themed blocks on SPAs (like `err.ee`, `tootukassa`) by explicitly applying the transparent background reset to `body` so it properly inherits `html`'s theme color.
  - Increased `MUTATION_RECORD_LIMIT` to 3500 (from 1200) to prevent the JS repainter from crashing/suspending on fast-mutating news and SPA sites.
  - Fixed transparent floating popover menus in ChatGPT (Radix UI) and Cursor/VSCode web (Monaco editor) by adding `[data-radix-popper-content-wrapper] > *`, `[data-radix-portal] > *`, `[data-floating-ui-portal] > *`, `.quick-input-widget`, and `.context-view` to the global solid-popover selector.
  - Fixed dotted focus-rings overlapping `code` tags and headings by removing `h1`-`h6` from the global `focus-visible` rule.
  - Fixed inline `code` blocks overlapping adjacent text lines by setting `line-height: inherit`.

## [1.26.9] - 2026-08-15

- FreeBuff: Updated orchestrator matchers and inline ad blocker for version 0.0.55. Added THEME_REASSERT_FIX to the electron shim to force the repainter sweep when the theme changes (poll + matchMedia/observer logic).
- Discord: Switched to the golden palette, overriding midnight mode, embeds, and server lists. Mapped refresh brand vars and unmasked SVGs for the Golden Default layout.


## [1.26.8] - 2026-08-11

- The browser theme stage is now OWNED, not merely "in a safe location": a directory carrying the Wintage owner marker is the only one Apply replaces or Revert deletes. An unowned stage with user data is never touched - Apply and Revert refuse instead of recursively deleting it, and the stage is swapped atomically through a temp sibling.
- VS Code / Antigravity extension recovery moved to a persistent, non-pruned authority (`WINTAGE_APPDATA/recovery/<target>`): the first apply records whether the folder was created by Wintage or replaced a pre-existing one, a repaint never overwrites that pristine snapshot, and Revert restores the original directory byte-for-byte.
- SAIPENVIEW backup refreshes are now a REBASE, not a wholesale copy: the current CSS's Wintage-owned `--token` values always come from the old pristine, so a themed live file can never become the "pristine" authority and Revert restores stock colours, not Wintage's.
- The manifest is now schema-validated on every read and write: a syntax-valid but semantically broken file (top-level array, non-object entry, wrong-typed fields, non-array or duplicate-path `items`) is rejected like corrupt JSON and never overwritten, while unknown future target keys are preserved.
- Windows theme applies capture the exact owned pre-state (DWM inactive accent + Wintage theme artifacts) before mutating, and an activation failure restores it instead of leaving a half-applied theme. The DWM recovery backup survives until the manifest transition succeeds.
- Windows Terminal, Electron and Total Commander manifest commits are now part of their transactions: a failed commit rolls the target back (or keeps the recovery source for an idempotent retry), so a themed target can never be left with a manifest that does not describe it.
- The release helper now publishes the branch and the tag in ONE atomic push (`git push --atomic`): a rejected ref means neither lands, so a half-published version is impossible. The tag's availability is checked locally and on the remote before anything is pushed.
- The GUI custom theme Save/Delete are transactional: if a generator fails, the previous custom pack is restored and the generated outputs regenerated, so source and generated state never diverge.
- test-reapply now enumerates its full 34-test catalog and adds regressions for every fix above.

## [1.26.7] - 2026-08-11

- A target's mutation and its manifest commit are now ONE transaction: the manifest is validated before any real mutation (a corrupt `installed.json` aborts with zero target changes), and a failed manifest commit rolls every target back to its exact pre-operation state instead of leaving a mutated target with an old manifest. Each target also runs its whole DISCOVER..COMMIT under a named per-target mutex, so two concurrent applies of the same target serialize and can never tear each other's files.
- FreeBuff recovery is tighter: the transaction snapshot now includes the app EXE and its fuse backup (a failed second layer restores a half-defused executable too), and Revert refuses to restore an old-generation baseline over a new app build. A new app generation is detected by content (not just missing patch strings) and re-bases the baseline, which is pruned to the newest three generations.
- Electron repaint and revert are now transactions with their own failure seams: a failed repaint restores the previous palette, a failed revert restores the themed pre-state, and `--status-json` reports fuse health so Reapply can detect and repair a re-fused EXE.
- Reapply never reopens a browser: a browsers re-apply runs with launch suppressed (the theme already loads from a stable stage path), and a stub/empty browser executable is never "launched". This also stops the regression suite from yanking real Edge/Chrome windows open mid-session.
- Windows Terminal and Obsidian health now probe the EFFECTIVE owned state (markers and active-theme values) after the recorded item set passes, so a deleted or drifted marker triggers Reapply rather than being skipped.
- VS Code / Antigravity extension revert restores the apply-time backup instead of deleting the theme dir and leaving the user theme-less, and the browser stage root is snapshotted so a failed commit restores the exact pre-operation stage.
- The single release gate now runs every tool regression suite (reapply, freebuff, ownership, electron state machine) from `tests/Run-Tests.ps1`, and release publishing verifies the remote actually received the commit before tagging, so a half-published version is impossible.
- paths.json is schema-validated and saved atomically; remembered paths outside the known target set or with non-string values are dropped instead of later blowing up a `Join-Path`.

## [1.26.6] - 2026-08-11

- FreeBuff recovery is now a persistent per-generation BASELINE: every Wintage-owned file (renderer bundle, orchestrator, completion sound) is snapshotted as pristine stock, and Revert restores the current generation consistently — a later sound-only or subset Apply can never shadow the earlier recovery source, and an upstream app update starts a fresh generation baseline. The FreeBuff target is also atomic as a whole: both the Electron layer and the ad/sound patch are preflighted before any mutation, and a second-layer failure restores the exact pre-operation Electron state (a repaint rolls back to the old palette, never an uninstall). A configured-but-missing completion sound now fails closed in both `-WhatIf` and Apply, and the Reapply health probe checks the patch layer (renderer/orchestrator/sound) directly instead of assuming it.
- Electron installs are now fully transactional: `--dry-run` performs zero mutations (the fuse restore is never touched on a dry-run), the fuse flip happens only after state classification and preflight and is rolled back on any later failure, and both the relocation and in-place apply paths stage their changes and restore the exact pre-operation state on any injected failure.
- Revert now restores ONLY the fields Wintage owns, merged into the current config, for Obsidian and Windows Terminal too, and multi-item targets record their exact owned SET (`items`) in the manifest so health compares canonical path sets and revert walks the recorded items even when some vanish from today's discovery.
- Source-tree rollback provenance is safer: when the upstream source changes, the rollback base is re-based from the live non-owned content plus the old pristine's owned token values — a themed file can never become the "pristine" backup.
- Health probes now verify owned VALUES (marker == recorded palette, source-tree tokens == palette, generated CSS carries the palette), not just marker existence, so a tampered marker/token/CSS is detected and repaired by `-Reapply`.
- Concurrency hardening: the manifest write cleans up its temp on failure, an abandoned mutex is treated as acquisition (not a timeout), and the duplicate-function static gate is enforced across all installer modules.
- `-Target all` without Node no longer aborts globally: native/source-tree targets still run, absent generated-build targets skip, and present generated-build consumers fail with an aggregated result.

## [1.26.5] - 2026-08-11

- `-Reapply` now decides by TARGET HEALTH, not just the Wintage payload version: an application update or a moved install (same payload, new app version / new path / lost theme) triggers a re-apply, and an unhealthy recorded target is reported instead of skipped. `-Reapply -WhatIf` runs each child's real preflight so a broken helper surfaces as a nonzero exit, and an explicit or manifest-recorded target that cannot be resolved is a hard failure (bulk `-Target all` keeps treating genuine absence as a skip).
- Electron installs are now a real state machine: `stock / themed-relocated / updated-relocated / themed-inplace / updated-inplace / ambiguous` are classified from the actual layout, an app update leaves the NEW archive as the rollback source (Revert restores the current version, never the old one), the relocation move is a rollback-protected transaction, and a machine-readable `--status-json` plus a working `--version` after relocation feed the health probe.
- FreeBuff is one transaction: top-level Revert undoes the shim AND the ad/sound patch, the missing patch helper is a hard failure, `-WhatIf` validates both layers, and the patch is preflight-first with a single complete-transaction backup that Revert refuses to split.
- Revert now restores ONLY the fields Wintage owns, merged into the current config: Windows Terminal, OBS, Obsidian and Total Commander no longer restore whole old files, so unrelated edits made after Apply survive a revert. Obsidian advances/removes its manifest entry only after every vault succeeds.
- Source-tree targets (SMART VAC CLEANER, WildRift) re-base their rollback backup when the upstream source changes, so an update survives repaint and revert never restores an obsolete version.
- Manifest writes are serialized across processes (named lock + unique temp), so a GUI, CLI and logon task can no longer overwrite each other's entries.
- GUI polish: the status line visibly resets its failure colour on a later success, a failed target listing is preserved instead of dropped, and malformed app version directories no longer crash discovery.

## [1.26.4] - 2026-08-11

- Correctness pass over the installer's failure and rollback paths. `-Reapply` now exits nonzero when any target fails (a broken sibling no longer reads as a green run), payload versions are compared semantically (`1.9.0 < 1.26.3` instead of lexically), Electron apply/revert/`-WhatIf` helper failures abort the target instead of printing and continuing, the FreeBuff ad/sound patch runs before the manifest is written, and the GUI reports PASS/FAIL per target and only claims success when every requested operation succeeded. Saving or deleting the custom theme now aborts the Apply when the generators fail, so a stale build can never be installed.
- Rollback integrity: SMART VAC CLEANER keeps its first pre-Wintage backup across repaints (apply A -> apply B -> Revert restores the original byte-for-byte), the source anchors that smartvac/wildrift/saipenview patch must each match exactly once or the install fails without writing anything, MPC-HC refuses to mutate the registry when its backup export fails and refuses to claim a restore when the import fails, and a corrupt `installed.json` is a distinct fatal state that Status and Reapply report and that no mutation will overwrite. Manifest writes are atomic (temp write + readback + rename).
- The theme contract now has one owner. `tools/theme-schema.js` defines the canonical 21-token schema and the WCAG text roles (textPrimary/textSecondary/link), shared by apply-themes, check-css, build-desktop and the GUI; pack validation rejects duplicate slugs/labels and any pack whose filename does not match its slug; the GUI and the build gate warn about exactly the same contrast roles, so a decorative `borderHighlight` no longer produces a false FAIL on light palettes.
- Encoding: double-encoded UTF-8 mojibake removed from `build-desktop.js`, `install-electron.js` and `derive-palette.js`, generated outputs regenerated, and a gate now fails the build on known mojibake signatures.
- Tests: the reapply suite now runs fully isolated from the live `%APPDATA%` manifest and covers semantic versioning, moved-target rediscovery, child-failure aggregation, corrupt-manifest refusal, Electron helper failure propagation and byte-exact revert; the repository suite validates the shared schema, theme identity collisions, WCAG role parity and single-owner target dispatch.

## [1.26.3] - 2026-08-10

- BetterDiscord is now a dedicated target. The generic web stylesheet broke Discord's layout because it never fills Discord's own CSS variables; a dedicated theme maps every Wintage palette token onto Discord's variable surface (dark + light, brand, modifiers, scrollbars, bevels on buttons and inputs, Verdana, status colours) and installs under the BetterDiscord theme directory.
- The whole README/installer/browser-theme surface now ships in 29 languages. Twelve languages were added outright (Ukrainian, Portuguese, Dutch, Polish, Swedish, Danish, Finnish, Norwegian, Turkish, Czech, Slovak, Croatian) and the other seventeen were refreshed to the current palette table; the installer gained 12 new UI locales alongside its existing four.
- Fixed: `install.ps1` died on every launch when no CodeNomad path was configured -- `Join-Path` throws on an empty first argument during target-table construction, so listing and every target failed before this fix.
- The installer monolith was split into shared modules (`desktop/modules/common.ps1` and `desktop/modules/targets.ps1`); behaviour is unchanged, the listing, `-Reapply` and `-Status` flows were re-verified byte-identical.
- A new release gate pins that the repository `wiki/` mirror never drifts from the maintained wiki source.
- Docs corrected: the palette tables now name the real Golden Default tokens, the browser-theme README no longer claims to use the same palette as the userscript, and the Core-share ru/et/ded READMEs carry the same source-digest markers as the translated bundle.

## [1.26.2] - 2026-08-07

- Portable browser root is no longer hardcoded to a personal-machine path. `tools/install-browsers.ps1` defaults to an empty `-PortableRoot` and only scans it when one is supplied (the installer passes the remembered `portable` entry from `paths.json`); the same hardcoded path was removed from prose in `desktop/README.md` and from the FastPrompter importer's default source.
- Corrupt config is no longer silent. `Read-PathsJson` and `Read-Manifest` now warn when `paths.json` or `installed.json` fails to parse, instead of returning an empty table that looks identical to "nothing configured".
- The browsers target now records itself in the install manifest, so `-Reapply` can rediscover it like every other target; the fuse-deflip in `tools/electron-fuses.js` backs up the original EXE before mutating it and `--revert` restores those bytes.
- Installer housekeeping: a stale comment about the removed `FLOAT_FIX` patch was corrected, the GUI's mojibaked section dividers were cleaned, config reads switched to the UTF-8-safe `Read-Utf8`, backup folders are pruned to the eight newest, palette-token reads were consolidated into one helper, and generated `desktop/out/` output is no longer tracked in git (rebuilt with `node tools/build-desktop.js`).

## [1.26.1] - 2026-08-06

- Fixed: Antigravity and FreeBuff would not start at all after 1.26.0. Retiring the old floating-surface payload cut its tail and left its head behind, so the next declaration closed that unterminated string instead of opening its own and the shim died on load with `SyntaxError: Invalid or unexpected token`. The error is thrown in Electron's main process, before any window exists, which is why it presented as the application refusing to launch rather than as a theme problem.
- The repainter is now carried into the shim as an encoded string instead of pasted into a template literal. Pasted, every backslash in its regular expressions was read as an escape -- `\d` became `d`, `\s` became `s` -- so the code still parsed and silently stopped recognising the colours it exists to correct.
- Shadow roots are themed in the desktop apps again. `insertCSS` produces a document stylesheet, which cannot cross a shadow boundary, so those rules travel inside the repainter payload and are injected root by root.
- Three new release gates, because every existing one was green while the above shipped: the build parses each generated shim, refuses an unresolved placeholder, and fails when the repainter starts reading a helper the shim does not provide; the payload suite parses each generated shim and the payload it builds.
- Removed a stale VS Code colour theme left behind when a palette was renamed -- nothing generated or read it.
- Fixed: the installer treated an unreadable FreeBuff sound preference as "no sound set" and said nothing about it.

## [1.26.0] - 2026-08-03

- Floating surfaces are decided by measurement rather than a list of component names. The deciding test is a hit test at the panel's own centre: if what lies under it is only its own ancestors it is an adornment, and anything foreign under it means it covers content it does not own. An earlier "must carry an explicit z-index" rule was wrong on the first application it met -- Claude's Settings dialog is `position: fixed` with `z-index: auto`.
- A viewport-covering backdrop that takes pointer events is dimmed instead of skipped. Erasing its background left an invisible modal that ate every click, which is how CodeNomad's tabs stopped responding.
- Panels are re-measured twice, bounded, after being refused for a reason time can change. A dialog animates in and is not its final size at the instant it is mounted, which is why they were see-through only sometimes.
- Status colours are alive again application-wide. The button-descendant wipe's selector list still opened with an unguarded `button:not(.ytp-button) *,` above the exclusions written for it, in the same comma list, and one unguarded sibling defeats every guarded one. The same shape is now guarded in `SHADOW_CSS`, and `tools/check-css.js` fails on it.
- Idle CPU: `injectLate()` was appending a second complete copy of `GLOBAL_CSS` -- 44 KB parsed and matched twice on every page. Being last in the cascade is a position, not a copy, so the existing sheet is moved instead. Style recalculation on a 3200-element harness dropped from 48ms to 20ms. The floating-surface pass also stopped marking small out-of-flow elements permanently dirty, which had cost a forced layout each, forever.
- Scrolling up means scrolling up: a programmatic scroll aimed at the bottom is dropped when the reader has deliberately scrolled away and no user gesture is behind the call. It fails open -- anything unmeasurable is allowed through.
- Withdrawn after measuring what it hit: the gauge painter marked 234 elements by shape and 111 by inline width, repainting ordinary controls as solid blocks. The problem stays open; nothing paints again until a real gauge is read live.
- New: `tools/inspect-electron.js` reads a live themed Electron app over CDP (targets / rules / eval) -- the tool behind every diagnosis above.

## [1.24.0] - 2026-08-01

- Claude Desktop: buttons transparent by default; the foreground repair moved to targeted floating-surface selectors (the earlier inherit-all approach was reverted); re-solidify specificity bumped to beat the transparency wipe, with Radix UI selectors added; live CSS hot-reloading for Electron targets (tools/watch-claude.ps1).
- Docs: README translated to Russian (README.ru.md), Estonian (README.et.md) and the Дед voice (README.ded.md); an 8-page wiki mirror added under wiki/.
- Tests: shim payload validity and terminal font agreement are now release-gated (tools/test-shim-payloads.js, tools/test-terminal-font.js).

## [1.23.3] - 2026-08-01

- Replace proportional Verdana in Windows Terminal and classic conhost with Consolas 12 so glyphs fit the fixed terminal cell grid.

## [1.23.2] - 2026-08-01

- Restore readable palette foregrounds in Claude Desktop 1.24012.9 while leaving SVG and icon glyphs untouched.

## [1.23.1] - 2026-08-01

- Report clipboard failures with the usable browser-theme path instead of claiming it was copied.
- Surface installer path-preference write failures instead of silently forgetting them.

## [1.23.0] - 2026-08-01

- Added immediate Windows theme installation with muted active/inactive captions and the `___CURRENT___` cursor scheme.
- Added Verdana 12 and matching 16-colour palettes for Windows Terminal and classic conhost profiles.
- Added OBS Studio theme installation and immediate selection.
- Added installed and portable Chromium browser discovery, Tampermonkey detection, stable browser-theme staging, and browser-owned installation pages.
- Reorganized the installer into separate My Apps and Popular Apps groups and added a console-free launcher.
- Restored all sixteen userscript palettes, including the editable Custom palette.
- Restored themed recent-file colour indicators in Total Commander.
- Fixed dry-run isolation, generated token drift, Electron injection coverage, and several installer round-trip defects.
