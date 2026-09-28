agent: antigravity-01
role: core
model_or_runtime: unknown
project: vacterro-wintage
saipen_version: 8.0.1
protocol_fingerprint: sha256:9936e341299eadd408cf76057b2bcd72b274345afae59f34419e48594f24c11c
source_head: 82178cdfb124ad55f9dccc7cd55ce3a633d51a6c
source_tree_fingerprint: git-delta-v1:ff051012348454e2792583e36adee4ffea89c203dbc85aeebdd89dc4ab81d0c7
discovery_model: git-delta-v1
context_scope: SAIPEN audit, phase DONE
context_available: partial
report_status: complete

## RUN 1

Scope: current uncommitted Vintage product/protocol changes plus installed SAIPEN conformance remediation. Independent full regression matrix passed when run without overlapping fixture processes. Findings below are independently reproduced or mechanically proven.

IMP-001 [P1] [PROJECT_VIOLATION] [reproduced] [ticket]
Preset GUI calls nine translation keys that no locale defines, including all preset controls and dialogs.
expected: Every T 'key' consumed by WintageInstaller.ps1 exists in en.json and every locale has exact key parity, so no UI surface renders a raw key.
actual: Static extraction finds 61 consumed keys and nine absent from en.json: PresetDelete, PresetDeleteAsk, PresetLabel, PresetModified, PresetNamePrompt, PresetOverwriteAsk, PresetRename, PresetSave, PresetUpdate. i18n.ps1 T() returns the missing key verbatim.
evidence: desktop/WintageInstaller.ps1:1106,1112-1121,3588,3634,3638,3655,3688; desktop/i18n.ps1:40-43; tools/test-locale-parity.ps1 compares locale files only and misses GUI-used keys.

IMP-002 [P1] [PROJECT_VIOLATION] [reproduced] [ticket]
WINTAGE_APPDATA override splits GUI/CLI persistence: language and FreeBuff sound still use %APPDATA%\Wintage while paths, manifest and generation locks use the override.
expected: All Wintage-owned persistence uses WINTAGE_APPDATA when set, otherwise %APPDATA%\Wintage.
actual: With APPDATA=A and WINTAGE_APPDATA=B, Set-I18nLocale writes A\Wintage\language.txt; B\language.txt is absent. Get-FreeBuffPatchArgs reads A\Wintage\freebuff-sound.txt and ignores B. WintageInstaller Save-FbSound also writes the A path.
evidence: desktop/i18n.ps1:51; desktop/modules/targets.ps1:238; desktop/WintageInstaller.ps1:361-362,668; desktop/install.ps1:96; tools/test-wintage-appdata-root.ps1 tests only paths.json/lock, not every preference.

IMP-003 [P2] [PROJECT_VIOLATION] [reproduced] [ticket]
MPC-HC listing contradicts the canonical themed state and can report an applied target as unthemed.
expected: -List uses the same Get-WintageFontFace rule as Invoke-MpcHc and health.
actual: Invoke-MpcHc writes OSDFont=Get-WintageFontFace (Verdana_m1 when installed), health expects the same, but -List hardcodes equality to Verdana. A registry containing the values written by Invoke-MpcHc with OSDFont=Verdana_m1 is classified 'found, not themed'.
evidence: desktop/install.ps1:565-568; desktop/modules/targets.ps1:161-163,677,2663-2667.

IMP-004 [P2] [PROJECT_VIOLATION] [reproduced] [ticket]
ded, et and ru locale InfoText values contain literal backslash-r-backslash-n text instead of paragraph line breaks.
expected: InfoText carries actual newline characters like en.json, so the GUI renders paragraphs.
actual: JSON parses successfully, but each affected value has zero actual CRLF and repeated literal '\\r\\n' sequences visible to the UI.
evidence: desktop/locales/ded.json InfoText; desktop/locales/et.json InfoText; desktop/locales/ru.json InfoText; independent JSON inspection found 0 actual CRLF and six literal sequences per value.

IMP-005 [P2] [PROJECT_VIOLATION] [observed] [ticket]
All 32 non-English locale files copy all 16 new terminal-font strings verbatim from en.json, and translated desktop READMEs omit the newly documented Process Explorer and terminal-font surfaces.
expected: New user-visible terminal-font labels are translated for each shipped locale, and translated desktop READMEs cover the target/feature matrix they mirror.
actual: TabFonts plus 15 Tf* values equal en.json in 32/32 non-English files. desktop/README.md now documents Process Explorer, Notepad++, Cinema 4D and terminal fonts, while every desktop/README.<locale>.md lacks the new sections/headings.
evidence: desktop/locales/*.json; desktop/WintageInstaller.ps1:1191-1279,1955-1971; desktop/README.md:68-100,203-242; no translated-doc value/parity gate exists.

IMP-006 [P1] [PROTOCOL_VIOLATION] [reproduced] [ticket]
AD-000002 was modified in place through a generic journal operation after canonical registration, contrary to the accepted-debt registration-only immutable evidence contract.
expected: Accepted legacy debt is created by accepted_debt.register with domain validation; subsequent evidence movement uses a registered semantic writer or a new record, not a generic CAS rewrite.
actual: accepted_debt.register-182bffb57859 registered AD-000002 at hash b8a28828fdaddb43. accepted-debt-rebind-003 then rewrote the same path to 0ce8734c57b86f9e with verification_policy=none, while journal_op_id still names the registration operation. The registration receipt no longer matches the live target bytes.
evidence: _SAIPEN/tools/saipen_engine/accepted_debt.py:26-27,302-317,471-499; .saipen/recovery/settled/accepted_debt.register-182bffb57859/operation.json; .saipen/recovery/settled/accepted-debt-rebind-003/operation.json; live AD-000002 begins with hash 0ce8734c57b86f9e.

IMP-007 [P2] [PROTOCOL_VIOLATION] [reproduced] [ticket]
The saitranslate canonical OUTBOX contains fields outside the closed producer schema and fails its collect gate.
expected: A consumable saitranslate OUTBOX parses under extensions/subs/PROTOCOL.md closed field grammar.
actual: OUTBOX.md adds deprecated_note and _old_status; validate.py --gate collect:saitranslate exits 1 with unknown field errors, while core downgrades this producer-gate failure to WARN because the producer is not being consumed.
evidence: .saipen/extensions/subs/saitranslate/kitchen/OUTBOX.md:33-35; python _SAIPEN/tools/validate.py --project-root . --gate collect:saitranslate -> exit 1.

IMP-008 [P2] [PROTOCOL_VIOLATION] [reproduced] [ticket]
The post-remediation canonical validator PASS was not durably recorded in canonical LOG form.
expected: VALIDATE logs 'RUN: validate.py -> PASS conf: high -- 0 FAIL, <warnings>, <evidence>' in the active canonical record.
actual: After sealing history, active .saipen/LOG.md contains only '# Log'. The validator therefore emits no-conformance-record despite exit 0; transient receipts alone do not satisfy the durable record contract.
evidence: _SAIPEN/saipen/phases/validate.md:20-30; .saipen/LOG.md; .saipen/recovery/conformance/latest-after-rebind.txt; .gitignore excludes .saipen/recovery/conformance/.

Verification context: tests/Run-Tests.ps1 completed ALL TESTS PASSED in isolation. Earlier first-touch, Windows-theme and reapply-intent failures were reproduced only while overlapping focused suites shared generation locks/temp state; isolated suites passed. Canonical core validator exit 0 after conformance remediation, with accepted legacy-debt and sealed hunt-mark warnings.
