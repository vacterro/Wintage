# Operator Checklist: Live Acceptance Honesty (T-359)

This checklist is the only place T-359 is satisfied. It is NOT a rewrite of
test-inject-wintage-web.js or any existing gate -- it is an operator procedure
that must be performed before any live acceptance claim is published.

## When to use

Every time a live acceptance claim is made against a signed-in chatgpt.com tab,
run through this list. If any step cannot be completed, the verdict is
`NEEDS_OPERATOR_LIVE`, not `LIVE_PRODUCT_VERIFIED`.

## Verdict classes

| Class | Meaning | Who decides |
|---|---|---|
| ENGINEERING_VERIFIED | Offline proof only (RED controls, fixture assertions, computed-style parity). No live product reached. | Automated gate exit code |
| BROWSER_FIXTURE_VERIFIED | Real Chromium launched, local fixture HTML, no product authentication. | Automated gate exit code |
| LIVE_PRODUCT_VERIFIED | Real browser on chatgpt.com WITH an authenticated session, theme applied and judged via the inspect-web CLI. | Operator, via this checklist |
| NEEDS_OPERATOR_LIVE | Automated proof exists but live product is unreachable/unauthenticated. | Default state when LIVE_PRODUCT_VERIFIED cannot be produced |

## Checklist

- [ ] 1. A signed-in chatgpt.com tab is open in a real browser.
- [ ] 2. The Wintage theme is applied (check `html[data-w95-chatgpt="1"]`).
- [ ] 3. The tab is listed: `node tools/inspect-web.js targets`.
- [ ] 4. The bounded watch pass runs and returns `accept === true`:
      `node tools/inspect-web.js watch chatgpt.com 900`
      Navigate by hand through at least one conversation AND `/settings` during
      the pass; the aggregation is route-aware, so surfaces are only judged on
      routes where they apply, and the verdict names any requested surface the
      operator never opened.
- [ ] 5. A single capture cross-checks the composer surface:
      `node tools/inspect-web.js surface chatgpt.com --attribute`
- [ ] 6. The opaque viewport-ownership audit is clean:
      `node tools/inspect-web.js opaque chatgpt.com`
- [ ] 7. The 3 Chromium fixture gates pass. They are BROWSER_FIXTURE_VERIFIED:
      real Chromium launched against local fixture HTML, no product
      authentication. They are evidence about the theme's CSS, never about the
      live tab -- they cannot execute against chatgpt.com and are NOT proof of
      live acceptance:
      - [ ] test-chatgpt-assistant-content.js
      - [ ] test-chatgpt-viewport-coverage.js
      - [ ] test-provider-image-preservation.js
- [ ] 8. Computed-style assertions are recorded (viewport owner color, sidebar,
      composer, prompt-editor) in the acceptance report.
- [ ] 9. The verdict is recorded as LIVE_PRODUCT_VERIFIED with the operator's
      initials and timestamp.

## LIVE_PRODUCT_VERIFIED requires all of

1. An authenticated user-owned chatgpt.com browser session.
2. Witage applied in that session.
3. A complete bounded CDP watch (`node tools/inspect-web.js watch chatgpt.com 900`).
4. Required route coverage: the conversation family AND the Settings family both
   visited (the `--full-session` mode names any required route never opened).
5. Real computed-style evidence recorded in the acceptance report.
6. No unresolved required surfaces in the machine-readable report.
7. Operator confirmation (initials and timestamp).

Never claim live acceptance from the Chromium fixture gates alone, and never
produce it by destructive browser profile cleanup.

## If any step fails

Set verdict = `NEEDS_OPERATOR_LIVE`. Document which step blocked. Do NOT
downgrade to ENGINEERING_VERIFIED or claim live acceptance from offline gates
alone.
