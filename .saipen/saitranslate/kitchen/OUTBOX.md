# OUTBOX

## SAIT-001: Wintage translation bundle — Core share (EN/RU/ET/Дед), 29 languages pending

- **status:** draft
- **producer:** saitranslate
- **source_head:** 3e1e77a09d79ee64255ef62c8c254a24cc1b6cb5 (project HEAD)
  (drafted at 6e18ec1; re-verified at 71f9852 and 3e1e77a — README.md byte-identical
  across both re-verifies (blob 071b4c1), so the RU/ET/Дед payload is still
  faithful; desktop/README.md gained FreeBuff ad-removal + sound sections since,
  but that surface stays EN-only pending the dedicated instance (T-102))
- **coverage:** real surfaces inventoried in kitchen/surface.md —
  docs: README.md (translated), desktop/README.md + browser-theme/README.txt
  (surfaces exist, EN only, translation pending the dedicated instance);
  UI strings: WintageInstaller.ps1 / install.ps1 / wintage.user.js have real
  user-visible strings but **no i18n loader exists**, so no fabricated JSON
  bundle was built (T-103). No hand-maintained per-language siblings; no root
  README mirrors exist yet.
- **payload:**
  - kitchen/README.ru.md — Russian
  - kitchen/README.et.md — Estonian
  - kitchen/README.ded.md — Дед voice
  (English source = README.md at source_head; no file to ship for EN)
- **verified:** RU/ET/Дед drafted against README.md at source_head: heading
  structure, code fences, hex tokens, commands, the donation link and the
  Changelog link preserved; prose translated; UTF-8 clean; no placeholders.
  The five screenshot `<img>` tags are deliberately omitted from translations
  (heavy image content, not text) -- noted, not a silent gap.
- **instructions:** (1) When T-102 (dedicated instance) completes the 29-language
  bundle AND T-103 (UI i18n loader) lands, re-run `ee` to refresh this OUTBOX to
  status: ready. (2) `eee` refuses while draft — by design. (3) Integration of a
  ready handoff: add README.<lang>.md siblings + root README mirrors, wire any UI
  bundle through the loader from T-103, then normal VERIFY/REVIEW/SHIP.
- **details:**
  Per TRANSLATE hard split, Core owns EN/RU/ET/Дед only. The 29 remaining
  languages are subSaipen work — ticketed T-102, deliberately not grinded here.
  The UI surface is real but loader-less: a JSON bundle would translate strings
  nothing consumes, so it is ticketed (T-103) as a feature, not fabricated as
  pretend coverage. Honest partial > rounded-up 100%.

  UPDATE (E-388, `ee inject`): the Core-share payload was injected into the
  main project at repo root as README.ru.md / README.et.md / README.ded.md.
  These root copies are now the live integration; the kitchen copies here are
  the archived payload. A future collect must push/refresh the repo-root files,
  not these — do not re-inject from kitchen without a freshness re-check.

  UPDATE (E-392, `ee` re-verify): source_head refreshed to 71f9852 (post
  v1.24.0 ship). README.md diff since 6e18ec1 = new screenshot img tags
  (omitted by design) + CRLF normalization, no heading/text/token/command
  changes. Payload unchanged and still faithful; status stays draft until
  T-102 completes the 29-language bundle.

  UPDATE (E-450, `ee` re-verify): source_head refreshed to 3e1e77a (post
  v1.26.0 ship). README.md blob byte-identical to 71f9852 (071b4c1), payload
  still faithful. desktop/README.md gained FreeBuff ad-removal + sound-button
  sections — surface stays EN-only pending the dedicated instance (T-102);
  no loader exists yet (T-103). Status stays draft; `eee` remains a no-op.
