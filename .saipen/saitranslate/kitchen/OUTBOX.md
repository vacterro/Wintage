# OUTBOX

## SAIT-001: Wintage translation bundle — Core share (EN/RU/ET/Дед), 29 languages pending

- **status:** draft
- **producer:** saitranslate
- **source_head:** c88ad1265b34c2a47aae56642846e4b86eb14ccb (project HEAD)
  (drafted at 6e18ec1; re-verified at 71f9852, 3e1e77a, cd6df0b, c88ad12 —
  README.md unchanged since cd6df0b, payload still faithful)
- **coverage:** real surfaces inventoried in kitchen/surface.md —
  docs: README.md (translated), desktop/README.md + browser-theme/README.txt
  (surfaces exist, EN only, translation pending the dedicated instance);
  UI strings: **i18n loader SHIPPED (T-103, 85d5053)** — 4 locale JSONs in
  desktop/locales/ (en/ru/et/ded.json). GUI being wired (T-144 in DOING,
  claude-code-5). Non-en locales stale: missing 5 keys vs en.json (T-152
  MARKHUNT). CLI output (Say calls) still hardcoded English (T-150 proposed).
- **payload:**
  - kitchen/README.ru.md — Russian (updated for v1.26.1 doc drift)
  - kitchen/README.et.md — Estonian (updated for v1.26.1 doc drift)
  - kitchen/README.ded.md — Дед voice (updated for v1.26.1 doc drift)
  (English source = README.md at source_head; no file to ship for EN)
  (Repo root copies at README.ru.md / README.et.md / README.ded.md also updated)
- **verified:** RU/ET/Дед updated against README.md at source_head: heading
  structure, code fences, hex tokens, commands, the donation link and the
  Changelog link preserved; prose translated; UTF-8 clean; no placeholders.
  The five screenshot `<img>` tags are deliberately omitted from translations
  (heavy image content, not text) -- noted, not a silent gap.
- **instructions:** (1) When T-102 (dedicated instance) completes the 29-language
  bundle, re-run `ee` to refresh this OUTBOX to status: ready. (2) `eee` refuses
  while draft — by design. (3) T-152 (non-en locale gap) should be resolved before
  declaring the UI translation surface ready. (4) Integration of a ready handoff:
  README.<lang>.md siblings are already injected at repo root; refresh them from
  kitchen on `eee collect`.
- **details:**
  Per TRANSLATE hard split, Core owns EN/RU/ET/Дед only. The 29 remaining
  languages are subSaipen work — ticketed T-102, deliberately not grinded here.
  The UI surface now has a real loader (T-103) and locale files, but non-en
  locales are behind en.json by 5 keys. Honest partial > rounded-up 100%.

  UPDATE (E-388, `ee inject`): the Core-share payload was injected into the
  main project at repo root as README.ru.md / README.et.md / README.ded.md.
  These root copies are now the live integration; the kitchen copies here are
  the archived payload.

  UPDATE (E-505, `ee` re-verify): source_head refreshed to cd6df0b (post
  T-145/T-148/T-149). README.md diff since 3e1e77a: language switcher bar,
  NomadCode→CodeNomad, "Dark golden"→"Golden Default", 10-of-21 palette note.
  All three translations updated. T-103 i18n loader exists with 4 locale JSONs;
  T-144 GUI wiring in progress. Non-en locales 5 keys behind (T-152). Status
  stays draft — T-102 29 languages + T-152 locale gap pending.
