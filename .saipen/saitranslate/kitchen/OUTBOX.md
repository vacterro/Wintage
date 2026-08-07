# OUTBOX

## SAIT-001: Wintage translation bundle — Core share (EN/RU/ET/Дед), 29 languages pending

- **status:** draft
- **producer:** saitranslate
- **source_head:** 708bc21c5d86e51fb090183fb67b3d9d81451234 (project HEAD, v1.26.2)
- **coverage:**
  - docs — README.md: RU/ET/Дед translations current (source unchanged since
    ee55770/c88ad12; kitchen payloads re-synced with the language-switcher bar
    that T-107 added to the live root copies, so collection cannot strip it).
  - docs — desktop/README.md: real surface, **EN only**; changed since the last
    OUTBOX (T-153 portable-root prose, T-160 Rebuilding note). Translation
    pending the dedicated instance (T-102).
  - docs — browser-theme/README.txt: real surface, **EN only**, unchanged since
    544fb3f. Translation pending the dedicated instance (T-102).
  - UI strings — desktop/locales/{en,ru,et,ded}.json: **complete**, 49 keys each,
    zero gaps vs en.json (T-152 resolved). Loader (T-103), CLI wiring (T-150) and
    GUI wiring (T-144) all shipped in v1.26.2. Core share of the UI surface is
    done; the 29 remaining languages' UI strings are the dedicated instance's job.
- **payload:**
  - kitchen/README.ru.md — Russian (matches live README.ru.md byte-for-byte)
  - kitchen/README.et.md — Estonian (matches live README.et.md byte-for-byte)
  - kitchen/README.ded.md — Дед voice (matches live README.ded.md byte-for-byte)
  - desktop/locales/ru.json, et.json, ded.json — already live in the main repo
    (shipped with T-103/T-144); no injection needed
  (English source = README.md at source_head; no file to ship for EN)
- **verified:** RU/ET/Дед payloads byte-identical to the live repo-root copies
  (switcher bar included), UTF-8 clean, heading structure / code fences / hex
  tokens / commands preserved; locale JSONs parse and all four carry 49 keys.
  The five screenshot `<img>` tags are deliberately omitted from translations
  (heavy image content, not text) — noted, not a silent gap.
- **instructions:** (1) `eee` refuses while draft — by design. (2) status becomes
  `ready` only when the 29-language bundle (T-102) lands; Core does not grind it
  per the TRANSLATE hard split. (3) On collect of the Core share, refresh the
  repo-root README.ru/et/ded.md from these kitchen copies; the locale JSONs are
  already integrated. (4) desktop/README.md + browser-theme/README.txt enter the
  bundle when T-102's instance covers them.
- **details:**
  Per TRANSLATE hard split, Core owns EN/RU/ET/Дед only; the 29 remaining
  languages are subSaipen work, ticketed T-102. No subSaipen mechanism is
  initialised in this project (.saipen/extensions absent), so T-102 stays
  blocked until that instance runs. Honest partial > rounded-up 100%.

  UPDATE (ee, 07.08.26): source_head refreshed 708bc21 (v1.26.2). README.md
  unchanged since the last kitchen build; kitchen payloads re-synced with the
  T-107 language-switcher bar. UI surface now complete for the Core share —
  all four locales at 49 keys (T-152 resolved), loader + CLI + GUI wired.
  desktop/README.md drifted (T-153/T-160) but is EN-only and outside the Core
  share. Status stays draft — T-102 pending.
