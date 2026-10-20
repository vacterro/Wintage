# Operator Checklist: Live Acceptance Honesty (T-359)

This checklist is the only place T-359 is satisfied. It is NOT a rewrite of
test-inject-wintage-web.js or any existing gate -- it is an operator procedure
that must be performed before any live acceptance claim is published.

## When to use

Every time a live acceptance claim is made against a signed-in chatgpt.com tab,
run through this list. If any step cannot be completed, the verdict is
`NEEDS_OPERATOR_LIVE`, not `LIVE_PRODUCT_VERIFIED`.

## Verdict classes -- what each one is and is not

| Class | Meaning | Who decides |
|---|---|---|
| ROUTE_SCOPED_DIAGNOSTIC | A bounded watch or single capture run by the operator on whatever routes were open. The CLI's default mode is route-scoped on purpose: a Settings-only or conversation-only run is legitimate work and is NOT failed for routes it never claimed to cover. It says "the surfaces that applied where the operator actually went were judged"; it says nothing about a route family the operator never opened. | Default CLI verdict; any exit code |
| BROWSER_FIXTURE_VERIFIED | Real Chromium launched against local fixture HTML, no product authentication. Evidence about the theme's CSS, never about the live tab. | Automated gate exit code |
| LIVE_PRODUCT_VERIFIED | Real browser on chatgpt.com WITH an authenticated session, judged by the explicit full-session acceptance contract through the inspect-web CLI, with the machine-readable predicates below all satisfied and operator confirmation. | Operator, via this checklist |
| NEEDS_OPERATOR_LIVE | Automated proof exists but the live product is unreachable or unauthenticated. | Default state when LIVE_PRODUCT_VERIFIED cannot be produced |

**A successful ROUTE_SCOPED_DIAGNOSTIC is never a completed live-product
acceptance.** The CLI contract makes the two states machine-distinguishable:
without `--full-session` the tool reports `fullSession: false` and accepts a
route-scoped run that never touched one of the two required route families.
With `--full-session` the same run refuses and names the family it never saw.
That distinction exists so that an ordinary "the tool worked today" diagnostic
cannot be pasted into a report as if the full acceptance contract had passed.
A ROUTE_SCOPED_DIAGNOSTIC stays exactly that: a diagnostic.

## Checklist

- [ ] 1. A signed-in chatgpt.com tab is open in a real browser.
- [ ] 2. The Wintage theme is applied (check `html[data-w95-chatgpt="1"]`).
- [ ] 3. The tab is listed: `node tools/inspect-web.js targets`.
- [ ] 4. The bounded full-session acceptance pass runs and the final report's
      predicates (below) all hold:
      `node tools/inspect-web.js watch chatgpt.com 900 --full-session --attribute --json`
      During the pass, navigate BY HAND through at least one conversation and
      the Settings family (`/settings`). The aggregation is route-aware, so
      surfaces are only judged on routes where they apply, and the verdict
      names any requested surface or route family the operator never opened.
      A pass run WITHOUT `--full-session` produces a legitimately accepting
      ROUTE_SCOPED_DIAGNOSTIC and does NOT satisfy this step.
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
2. Wintage applied in that session.
3. A complete bounded CDP watch under the FULL-SESSION contract:
   `node tools/inspect-web.js watch chatgpt.com 900 --full-session --attribute --json`
4. The final machine-readable report's predicates, every one of them:
   - `finished === true`
   - `fullSession === true`
   - `accept === true`
   - `conversationRouteVisited === true`
   - `settingsRouteVisited === true`
   - `notAcceptingBecause` is empty
   - no unresolved required acceptance surfaces (no requested surface both
     never opened and never proven; no surface observed-but-UNPROVEN)
   - the observed context is a real authenticated chatgpt.com tab -- the
     report's URL, host, routes and observed surfaces are the product's, not
     a fixture's, and the performed checks 5 and 6 above are also clean
5. Real computed-style evidence recorded in the acceptance report.
6. No unresolved required surfaces in the machine-readable report.
7. Operator confirmation (initials and timestamp).

A final report with `fullSession: false`, or `accept: true` from a
route-scoped diagnostic that never visited one of the two families, is a
ROUTE_SCOPED_DIAGNOSTIC. Record it as such. It is not a live acceptance and
must not be summarized as one.

Never claim live acceptance from the Chromium fixture gates alone, and never
produce it by destructive browser profile cleanup.

## Operator safety boundaries

These hold for every run of this procedure, without exception:

- Never read, copy, print or export cookies, session tokens or any
  authentication material. The inspector reports computed styles and layout
  facts only, and its output is sanitized; keep it that way and never widen
  the probe to capture credentials.
- Never type the account password into the tool, a terminal or a report. The
  tool does not ask for one and the operator must not supply one.
- Never clear, reset or recreate the browser profile as a "verification
  shortcut". A wiped profile destroys evidence and proves nothing about the
  authenticated product.
- Keep the CDP endpoint local (loopback only). The browser is launched with
  `--remote-debugging-port=9222` on 127.0.0.1 and pointed at pages the
  operator already owns; nothing is exposed to a network.
- Preserve the existing report sanitization. Conversation text, tokens and
  node contents are never emitted.
- LIVE_PRODUCT_VERIFIED evidence is created only by a real authenticated
  session plus operator confirmation. No fixture run, no mocked session and
  no "the fixture passed so the product will" inference may produce it.

## If any step fails

Set verdict = `NEEDS_OPERATOR_LIVE`. Document which step blocked. Do NOT
downgrade to ENGINEERING_VERIFIED, do NOT relabel a ROUTE_SCOPED_DIAGNOSTIC as
live acceptance, and do NOT claim live acceptance from offline gates alone.
