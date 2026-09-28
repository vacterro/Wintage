# Board

## DOING

## TODO

## DONE

- [x] SAIT-004 prepare saitranslate -- v1.36.0 (82178cd): 29 owned locale JSONs 50 -> 68 keys (18 new BetterDiscord strings, exact parity with en.json) and 29 owned desktop READMEs through the qBittorrent + Fonts prose delta with restamped digest b77c16d423936045; both re-verified from disk (4495 + 232 checks, 0 failures); browser-theme surface re-checked fresh (32/32, untouched). The package stays `blocked` on the root-mirror surface below. | producer: saitranslate
- [x] SAIT-003 prepare saitranslate -- force-fresh package bound to v1.30.0 HEAD (ffc13fd), canonical kitchen payload location, 29/29 locale key-parity vs en.json, 32 desktop + 32 browser README translations, 3 core doc siblings; OUTBOX status: ready | producer: saitranslate
- [x] SAIT-002 prepare saitranslate -- force-fresh rebind at a9399dc9 (superseded by SAIT-003) | producer: saitranslate
- [x] SAIT-001 prepare saitranslate -- force-fresh package bound to fad7d717 (superseded by SAIT-003) | producer: saitranslate

## BLOCKED

- [ ] SAIT-005 open surface -- root README mirrors `locales/README.<code>.md` are stale 32/32 (marker 886c5e27060e7b30 vs README.md normalised 3e0623c938fcd514) and `ja` belongs to this role while the canonical kitchen holds no ja mirror. Next package: translate the current README.md into ja, re-check uk, then re-flip SAIT-005 to ready. Reported-only alongside it: Core's ru/et/ded drift and the unsatisfiable digest check in validate.py 1b11. | producer: saitranslate
