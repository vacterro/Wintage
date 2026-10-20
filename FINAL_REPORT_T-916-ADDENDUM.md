# FINAL_REPORT_T-916 ADDENDUM (T-917)

This addendum corrects operator-facing guidance in the historical report
`FINAL_REPORT_T-916.md`. The report itself is preserved byte-for-byte as
evidence of what was claimed at the time; nothing in it is rewritten.

## What was wrong

`FINAL_REPORT_T-916.md` §6 "P2 Live Acceptance Honesty" described the
operator procedure for live acceptance with:

> Steps: open authenticated tab, apply theme, run inspect-web CLI, verify
> accept=true, run 3 Chromium gates live, record computed-style assertions,
> clear browser artifacts, record verdict with operator initials.

Two defects in that sentence, both productive of false live-acceptance
claims:

1. **"verify accept=true" named no command.** The literal command
   `node tools/inspect-web.js watch chatgpt.com 900` was never documented
   anywhere in the report, and the operator checklist it points to carried
   the same route-scoped command. The CLI's default watch is a
   ROUTE_SCOPED_DIAGNOSTIC: it returns `fullSession: false` and `accept:
   true` on a conversation-only pass that never visited the Settings family
   (or vice versa). An operator following the old wording would record a
   green run and reasonably conclude they held a completed live-product
   acceptance. They did not: the checklist's own requirement #4 demanded both
   route families, and the CLI tool that judges that demand only enforces it
   under `--full-session`.

2. **"clear browser artifacts" was destructive and unsafe.** Deleting browser
   artifacts on the authenticated profile destroys evidence and proves
   nothing about the product. It is now explicitly forbidden; the checklist
   states the invariant in its "Operator safety boundaries" section.

## What the correct procedure is

The live acceptance pass is:

```
node tools/inspect-web.js watch chatgpt.com 900 --full-session --attribute --json
```

The final machine-readable report must satisfy every predicate below before
a verdict of LIVE_PRODUCT_VERIFIED may be recorded:

- `finished === true`
- `fullSession === true`
- `accept === true`
- `conversationRouteVisited === true`
- `settingsRouteVisited === true`
- `notAcceptingBecause` is empty
- no unresolved required acceptance surfaces
- the observed context is a real authenticated chatgpt.com tab (URL, host,
  routes and observed surfaces are the product's), and the single-capture
  (`surface`) and `opaque` checks are also clean

A successful run without `--full-session` is a ROUTE_SCOPED_DIAGNOSTIC:
legitimate work, recorded as such, never a live acceptance.

## Verdict classes (superseding the report's four-row table)

- ROUTE_SCOPED_DIAGNOSTIC — bounded watch/capture on whatever routes were
  open; the CLI's default mode; accepts on the routes it covered.
- BROWSER_FIXTURE_VERIFIED — real Chromium against local fixture HTML, no
  authentication; evidence about CSS, never about the live tab.
- LIVE_PRODUCT_VERIFIED — real authenticated chatgpt.com session judged by
  the full-session contract above, plus operator confirmation.
- NEEDS_OPERATOR_LIVE — automated proof exists, live product unreachable or
  unauthenticated.

## Status of the T-916 historical claims

All T-916 claims remain valid exactly as far as they went: they were
offline and fixture evidence, and were reported as such. The report's §6
"Current Verdict" line — LIVE: not performed, NEEDS_OPERATOR_LIVE is the
correct current verdict — was and remains true. Live acceptance is still
unperformed; this addendum changes only how the operator is told to perform
it, not what has been proven.

## Enforcement

`tools/test-operator-checklist-live-contract.js` gates this contract: it
checks the documented command against the real CLI flag parser, the
documented predicates against the final report the CLI actually emits, and
refuses fixture-only and route-scoped evidence as LIVE_PRODUCT_VERIFIED,
with RED controls that break the gate if `--full-session` is removed, an
unsupported flag is named, fixture evidence is promoted, or a route-scoped
run is promoted. It is wired into `tests/Run-Tests.ps1`.
