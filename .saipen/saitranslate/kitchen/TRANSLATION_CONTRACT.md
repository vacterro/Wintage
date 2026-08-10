# saitranslate batch contract — Wintage 29-language bundle (FORCE-FRESH, ee 08.08.26)

You are a translation worker for the Wintage project's saitranslate bundle.
Read this file first, then read the source files, then produce the output
files listed below for YOUR assigned language codes only. Do not touch any
file that is not in your output list. Do not write outside the kitchen tree.

## Project root

The project root is the git repository that contains this contract file
(the checkout holding `wintage.user.js`). Resolve it with
`git rev-parse --show-toplevel` from inside this checkout.

## Source files (read these)

- `README.md` — main English doc (~9 KB)
- `desktop/README.md` — desktop subsystem doc (~18 KB)
- `browser-theme/README.txt` — browser theme notes (small)
- `desktop/locales/en.json` — English UI strings (49 keys)
- `desktop/locales/ru.json` — existing Russian UI strings (style reference)
- `.saipen/saitranslate/kitchen/README.et.md` — existing Estonian README
  translation (structure convention reference)

## Output files, one set per assigned language `<code>`

1. `README.<code>.md` in `.saipen/saitranslate/kitchen/` — translation of `README.md`
2. `desktop/README.<code>.md` in `.saipen/saitranslate/kitchen/desktop/` — translation of `desktop/README.md`
3. `browser-theme/README.<code>.txt` in `.saipen/saitranslate/kitchen/browser-theme/` — translation of `browser-theme/README.txt`
4. `locales/<code>.json` in `.saipen/saitranslate/kitchen/locales/` — translation of `desktop/locales/en.json`

All paths relative to the project root. Create files with UTF-8, no BOM.

## Mandatory rules

- Translate every natural-language sentence faithfully and fluently into the
  target language. Keep ALL technical content byte-identical: code, inline
  code, commands (`.\install-themes.ps1 -Latest`, `.\release.ps1 -Message "..."`,
  `node tools/build-desktop.js`, etc.), hex colour tokens (`#1A0F05`,
  `#D4B87A`, ...), file names, URLs, paths, and the `:hover` / `attachShadow`
  / `border-radius: 0` style technical terms.
- Keep the markdown structure exactly parallel to the source: same headings
  (translated), same lists, same tables, same code fences (language tag
  preserved), same inline emphasis.
- Keep this language-switcher line VERBATIM in the README translation
  (translate nothing inside it):
  `[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)`
- Keep the support link (translate only the link text if it reads better):
  `[🤍 Support Developer](https://buymeacoffee.com/vacuum34)`
- OMIT all `<img>` screenshot tags from the README translation (deliberate,
  documented project decision — do not render them, do not replace them).
- Palette token names in the table stay as-is (Canvas, Soft, Surface, Raised,
  Alt, Bevel highlight, Bevel shadow, Text, Muted, Accent); translate only the
  "Used for" column.
- Add the source-digest marker as the FINAL line of every doc translation
  (a newline before it if the file does not already end with one):
  - for `README.<code>.md`:
    `<!-- source-digest: README.md sha256:11d88239959a8c00 -->`
  - for `desktop/README.<code>.md`:
    `<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->`
  - for `browser-theme/README.<code>.txt`:
    `<!-- source-digest: browser-theme/README.txt sha256:8656b29d0e5629e9 -->`
- JSON rules (`locales/<code>.json`): preserve the EXACT 49 keys from
  `en.json` in the same order, same quoting, same `{0}` placeholders, and the
  same embedded `\r\n` sequences in multi-line strings. Translate only the
  string VALUES. In values that contain command fragments (e.g.
  `.\install.ps1 -Target freebuff -Palette klite`), translate only the prose
  part, keep the command byte-identical. The file must be valid JSON.
- RTL languages (ar, he): write plain RTL text, no bidi control characters
  needed.

## Verification (run these before you report)

- For each doc file: exists, non-empty, ends with the correct
  `source-digest` line.
- For each JSON: `python -c "import json;json.load(open(r'<path>',encoding='utf-8'))"`
  parses and the loaded object has exactly 49 keys.
- If python is unavailable, use `node -e "JSON.parse(require('fs').readFileSync('<path>','utf8'))"`.
- Report the exact list of files you wrote and the verification outcome for
  each, compressed (one line per file).
