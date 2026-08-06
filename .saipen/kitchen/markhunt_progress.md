# markhunt progress

**vectors:** 1,2,3,4,5
**surface:** *.ps1, *.js, *.css, *.json, *.md, themes/*.json, desktop/*.ps1, tools/*.js, .saipen/*.md, wiki/*.md
**findings:** 24 (deduped across vectors → 6 grouped tickets)
**cursor:** done
**head_start:** 23db420
**head_end:** 23db420

## vector 1 — HUNT recap (uncapped)
- **verdict:** 2 LOW — Read-I18n empty catch (install.ps1:115), node --version catch (install.ps1:1492)
- 13 already-gitignored throwaway root files (INFO, no ticket)
- All tests PASS, no unverified commits, no stale TODO/FIXME

## vector 2 — doc consistency  
- **verdict:** 2 HIGH, 1 MEDIUM, 3 LOW
- HIGH: wiki/Home.md:15 + _Footer.md:1 version v1.26.0 stale (actual v1.26.1)
- HIGH: desktop/README.md:21 token count 18, actual 21
- MEDIUM: README palette table shows 10/21 tokens
- LOW: donation link structural drift EN vs TL, `.\install.ps1` path, README golden→goldendefault

## vector 3 — security
- **verdict:** 2 MEDIUM
- MEDIUM: Path traversal — SaipenviewPath/SmartVacPath/WildRiftPath unsanitized
- MEDIUM: Electron fuses defuse irreversible, no EXE backup

## vector 4 — architecture
- **verdict:** 2 HIGH, 4 MEDIUM, 1 LOW
- HIGH: T() function zero callers — entire i18n infrastructure dead
- HIGH: Manifest never read by listing or GUI, only -Reapply
- MEDIUM: browsers target missing manifest recording
- MEDIUM: paths.json never read by install.ps1
- MEDIUM: backup discipline inconsistent (one-shot vs overwrite vs shape-compare)
- MEDIUM: duplicated patterns (writeAtomic x3, backupOnce x2, asar parsing x2)
- LOW: test-reapply.ps1 mutates production manifest

## vector 5 — blindness
- **verdict:** 2 HIGH, 3 MEDIUM, 1 LOW
- HIGH: wiki version stale (same as v2)
- HIGH: Mojibake on install.ps1:283 (double-encoded UTF-8)
- MEDIUM: @name says Dark Golden, default is goldendefault
- MEDIUM: Get-Content used where Read-Utf8 required (encoding policy violation)
- MEDIUM: 11 hardcoded personal-machine V:\ paths
- LOW: convhost typo (consistent)

## ticket grouping
- T-138: doc drift x5 (v1→v2 wiki stale, v2 token count, v2 incomplete palette table, v5 default name, v2 install path)
- T-139: i18n dead (zero callers) + locale keys inconsistent
- T-140: manifest under-utilized (listing, browsers)
- T-141: security (path traversal, electron fuses)
- T-142: encoding debt (mojibake, Get-Content violations)
- T-143: architecture debt (backup inconsistency, duplicated patterns, monolith, hardcoded paths)
