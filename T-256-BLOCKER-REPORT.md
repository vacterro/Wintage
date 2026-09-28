# T-256 — Blocker Investigation Report

**Date:** 16.09.2026
**Ticket:** T-256 (P1, `user_explicit`)
**Receipt:** SRC-012
**Head:** `82178cd` (v1.36.0)
**Trigger:** `cc` repeatedly returned `IMPROVE_AUDIT_ASSIGNMENT` because every BOARD
ticket was `## BLOCKED`. This pass investigated each blocker, repaired what was
repairable from inside the project, and unblocked two tickets.

---

## Outcome summary

| Ticket | Before | After | Disposition |
|---|---|---|---|
| T-250 | BLOCKED (engine traceback) | **TODO** — actionable | Root cause found + repaired |
| T-255 | BLOCKED (engine traceback) | **TODO** — actionable | Root cause found + repaired |
| T-238 | BLOCKED | BLOCKED (unchanged) | Genuine out-of-scope blocker |
| T-065 | BLOCKED | BLOCKED (unchanged) | Genuine out-of-scope blocker |

---

## T-250 / T-255 — root cause and repair

### Root cause

`SRC-007` (the audit/5.md receipt) had **three clauses still `UNKNOWN`** in
`.saipen/intake/coverage/SRC-007.json`: `R009`, `R010`, `R011`. Their evidence
was already recorded — `E-927` (R009), `E-928` (R010), `E-929` (R011) — but the
coverage ledger was never updated (a report-only defect already noted in
`E-935`). Because the receipt was not fully resolved it stayed `ACTIVE`.

The BOARD lines for **T-250** and **T-245** both carry
`source_receipts: SRC-007`, while `SRC-007.meta.json` has
`linked_work: T-246`. The mismatch made `intake.work_closure_gate()` return:

```
{"ok": False, "code": "SOURCE_LINKAGE_DRIFT", "receipt": "SRC-007", "work": "T-250"}
```

`_plan_finish_ticket` forwards that code into `Result.__post_init__`
(`result.py:35`), which raises `ValueError` for any code absent from
`REGISTRY.json["error_codes"]`. `SOURCE_LINKAGE_DRIFT` was never registered, so
`saipen ticket done T-250` escaped as a **raw Python traceback** — the ticket
could not be closed at all.

### Repair (canonical commands only)

1. `saipen source disp SRC-007 R009 VERIFIED --evidence "E-927…" --verification "…"`
2. `saipen source disp SRC-007 R010 VERIFIED --evidence "E-928…" --verification "…"`
3. `saipen source disp SRC-007 R011 VERIFIED --evidence "E-929…" --verification "…"`
4. `saipen source close SRC-007` → `SOURCE_CLOSED`
5. `saipen source req SRC-011 R001 …` + `disp SRC-011 R001 VERIFIED` (T-255 receipt)
6. `saipen ticket unblock T-250 …` → `UNBLOCK`
7. `saipen ticket unblock T-255 …` → `UNBLOCK`

After the repair the closure gate no longer returns the drifting code, and both
tickets are back in `## TODO`.

### Residual (engine-side, out of project scope)

T-250/T-245 still name the now-closed `SRC-007`, and the tombstone's
`linked_work` is `T-246`. The gate now returns `SOURCE_RECEIPT_MISSING`, which
is **also absent** from the registry — the same traceback class, one step
further along. This is not fixable from inside the project: no canonical CLI
rewrites a BOARD `source_receipts:` field, and hand-editing canonical state is
forbidden. The engine must either register the full refusal-code set or make
`_refuse`/`Result` fail closed to a registered code (e.g. `VALIDATION_FAILED`).

---

## T-238 — genuine blocker

Consolidating the duplicate `saitranslate` kitchens requires **removing a
tracked canonical subtree**. Every shell/git command that names the canonical
namespace is refused before execution:

```
SAIPEN_GUARD_REFUSAL: PROTECTED_CANONICAL_NAMESPACE: the host tool did not execute
```

(guard regex `_PROTECTED_SHELL_SEGMENT`, `admission.py:997`). No canonical
`saipen` command removes a kitchen subtree. Additionally the ticket's `verify:`
names `tools/validate.py --gate collect:saitranslate`, which **does not exist in
this repository** — it ships in the SAIPEN home and reads the legacy path.

**Measured state (for whoever can act):**
- legacy `.saipen/saitranslate/kitchen` — 128 files, **stale** (50-key locales, 15-heading desktop READMEs)
- canonical `.saipen/extensions/subs/saitranslate/kitchen` — 97 files, **current** (68-key locales, 17-heading READMEs)
- 97 shared paths: 38 identical, 59 differ
- 31 legacy-only: 29 near-duplicate root READMEs + stale `surface.md` + `TRANSLATION_CONTRACT.md`
- repo root mirror surface is `locales/README.<code>.md` (32 files)

**Needs:** an allowlisted canonical op (or a namespace-scoped exception) to remove
the legacy subtree, and an in-repo copy of the collect gate.

---

## T-065 — genuine blocker

Requires an authenticated YouTube Studio session. Unchanged.

---

## Engine defects recorded

Reported to the saipython subs inbox
(`.saipen/extensions/subs/_shared/inbox.md`):

1. **P1 — unregistered refusal codes:** `ticket done` escapes as a traceback
   because gate codes (`SOURCE_LINKAGE_DRIFT`, `SOURCE_LINKAGE_MISSING`,
   `SOURCE_RECEIPT_MISSING`, `SOURCE_CORRUPTION`) are absent from
   `REGISTRY.json`. 67 refusal-dict codes in `saipen_engine` are unregistered;
   2 are reached directly by `_refuse`.
2. **P1 — Improve write path unreachable:** when all TODOs are blocked,
   `continue` correctly falls through to the Improve self-audit, but
   `improve submit` is classified `EXECUTION` and refused `NO_ACTIVE_WORK`
   (no DOING ticket). The meta-control can open a cycle it can never fill.

---

## Verification

- `saipen validate` → `VALID`
- `work_closure_gate` re-probe: T-246 / T-238 / T-255 → `ok: true`; T-250 / T-245
  → `SOURCE_RECEIPT_MISSING` (residual, engine-side)
- `saipen recover` → `CLEAN`
- BOARD: T-250, T-255 back in `## TODO`; T-256 DOING; T-238, T-065 BLOCKED

---

## Repo changes

None. This pass touched only `.saipen/` protocol state (coverage ledgers, BOARD,
LOG) through canonical commands. No source, tool, or locale file was modified.
