# OUTBOX

## SAIT-001: prepare saitranslate - force-fresh package bound to current source identity
- **status:** stale
- **superseded_by:** SAIT-003 (source_head fad7d717 -> ffc13fd at v1.30.0 ship; kitchen payload moved to canonical .saipen/extensions/subs/saitranslate/kitchen/)
- **summary:** historical v1.28-era translation package; superseded by SAIT-003.
- **producer:** saitranslate
- **source_head:** fad7d717954001708eb770648b12599e604c019f
- **source_tree_fingerprint:** git-delta-v1:a610142112f29edfbf58698415bd9141285860fd3c01040b183c586c05815671
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:** Documentation (root README + 3 Core siblings ru/et/ded; 32 desktop/README.*.md; 32 browser-theme/README.*.txt) and in-app UI strings (29 locale JSONs).
- **payload:** .saipen/extensions/subs/saitranslate/kitchen/
- **verified:** PASS -- legacy run verified
- **instructions:** Superseded by SAIT-003.
- **details:** Historical entry retained for audit log continuity.

## SAIT-002: prepare saitranslate - force-fresh rebind at current HEAD; backfill done
- **status:** stale
- **superseded_by:** SAIT-003 (source_head a9399dc -> ffc13fd at v1.30.0 ship)
- **summary:** historical v1.29-era translation package; superseded by SAIT-003.
- **producer:** saitranslate
- **source_head:** a9399dc9d053b0cd333e0c343fbe6eed26d40185
- **source_tree_fingerprint:** git-delta-v1:76aaeeb7ee6a8e936f6593d61009741fbc85e1777753ce05fcd3dc16d0e96836
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:** Documentation and in-app UI strings (29 kitchen locale JSONs with LanguageLabel backfill).
- **payload:** .saipen/extensions/subs/saitranslate/kitchen/
- **verified:** PASS -- legacy run verified
- **instructions:** Superseded by SAIT-003.
- **details:** Historical entry retained for audit log continuity.

## SAIT-003: prepare saitranslate - force-fresh package bound to v1.30.0 HEAD (ffc13fd)
- **status:** ready
- **summary:** FORCE-FRESH regenerated + verified full translation package; bound to v1.30.0 HEAD ffc13fd, canonical kitchen payload location, 29/29 locale key parity vs en.json (50 keys), 32 desktop + 32 browser-theme README translations, 3 root siblings.
- **main_project_refs:** [README.md, README.ru.md, README.et.md, README.ded.md, desktop/README.md, desktop/locales/en.json, wintage.user.js]
- **critical:** false
- **severity:** P2
- **producer:** saitranslate
- **source_head:** ffc13fd5065855239642a6d479806e6c14956814
- **source_tree_fingerprint:** git-delta-v1:4605ede04378860b4c00db84428fb515311cf102266b154adc7c6531f8161049
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:** Documentation (root README + 3 Core siblings ru/et/ded; 32 desktop/README.*.md; 32 browser-theme/README.*.txt) and in-app UI strings (29 locale JSONs in canonical kitchen/locales/, key-parity verified against desktop/locales/en.json = 50 keys).
- **payload:** .saipen/extensions/subs/saitranslate/kitchen/README.{ru,et,ded}.md; .saipen/extensions/subs/saitranslate/kitchen/desktop/README.*.md (32); .saipen/extensions/subs/saitranslate/kitchen/browser-theme/README.*.txt (32); .saipen/extensions/subs/saitranslate/kitchen/locales/*.json (29)
- **verified:** PASS -- 29/29 locale JSONs pass exact 50-key parity vs en.json; 32 desktop + 32 browser-theme READMEs present; 3 root siblings present with 6/6 palette markers each; source_head == ffc13fd; role_revision matches saitranslate.md charter.
- **instructions:** For ee (Core saipen collect saitranslate then ship): copy kitchen payloads to main tree destinations, reconcile Core-owned ru/et/ded files, commit and push.
- **details:**
  - Re-bound post-v1.30.0 ship to new source_head ffc13fd and source_tree_fingerprint.
  - Payload relocated from legacy .saipen/saitranslate/kitchen/ to canonical .saipen/extensions/subs/saitranslate/kitchen/ per charter write_scope.
  - 29 kitchen locale JSONs carry all 50 keys including LanguageLabel.
  - Boundary clean: all writes inside .saipen/extensions/subs/saitranslate/.
