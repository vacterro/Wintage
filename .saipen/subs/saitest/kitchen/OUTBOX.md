# OUTBOX

## ST-001: REPRODUCED -- stale "NomadCode" product name in user-facing docs
- **status:** reviewed
- **summary:** After the nomadcode -> codenomad rename, six live user-facing docs still say "NomadCode": README.md:33, README.ru.md:41, README.et.md:46, README.ded.md:44, wiki/Palettes.md:4, tools/derive-palette.js:142 comment. Grep proves presence.
- **main_project_refs:** [README.md, README.ru.md, README.et.md, README.ded.md, wiki/Palettes.md, tools/derive-palette.js]
- **critical:** false
- **severity:** P3
- **producer:** saitest
- **source_head:** 82aabf7b65f6cdb32f41dc30157d83d0a77c00e1
- **coverage:** grep -rn "NomadCode" across *.md/*.js/*.json/*.ps1, excluding gitignored desktop/backup/ historical snapshots
- **verified:** REPRODUCED -- grep returns the stale name in all six listed files; themes/codenomad.json carries slug "codenomad", label "CodeNomad" (16/16 packs), so "NomadCode" is the old name
- **instructions:** Core: fix the six live references to "CodeNomad", leave desktop/backup/ snapshots untouched (gitignored history). Translated mirrors (README.ru/et/ded, kitchen copies) must keep in sync with README.md.
- **details:**
  Reproduction (minimal input):
  ```
  grep -rn "NomadCode" README.md README.ru.md README.et.md README.ded.md wiki/Palettes.md tools/derive-palette.js
  ```
  Observed: all six hit. The theme registry (themes/*.json, 16 packs) labels the palette "CodeNomad"; the docs' palette list is the only surface still carrying the pre-rename product name.
