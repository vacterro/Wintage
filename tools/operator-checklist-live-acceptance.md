# Operator Checklist: Live Acceptance Honesty (T-359)

This checklist is the only place T-359 is satisfied. It is NOT a rewrite of
test-inject-wintage-web.js or any existing gate -- it is an operator procedure
that must be performed before any live acceptance claim is published.

## When to use

Every time a live acceptance claim is made against a signed-in chatgpt.com tab,
run through this list. If any step cannot be completed, the verdict is
`NEEDS_OPERATOR_LIVE`, not `LIVE` or `ENGINEERING`.

## Verdict classes

| Class | Meaning | Who decides |
|---|---|---|
| ENGINEERING | Offline proof only (RED controls, fixture assertions, computed-style parity). No live product reached. | Automated gate exit code |
| BROWSER_FIXTURE | Real Chromium launched, local fixture HTML, no product authentication. | Automated gate exit code |
| LIVE | Real browser on chatgpt.com WITH an authenticated session, theme applied via inspect-web CLI. | Operator, via this checklist |
| NEEDS_OPERATOR_LIVE | Automated proof exists but live product is unreachable/unauthenticated. | Default state when LIVE cannot be produced |

## Checklist

- [ ] 1. A signed-in chatgpt.com tab is open in a real browser.
- [ ] 2. The Wintage theme is applied (check `html[data-w95-chatgpt="1"]`).
- [ ] 3. The inspector reports `accept === true` via:
      `node tools/inspect-web.js --target <tab> --attribute`
- [ ] 4. No `NEEDS_OPERATOR_LIVE` surfaces remain in the report.
- [ ] 5. The 3 Chromium gates all pass against the live tab:
      - [ ] test-chatgpt-assistant-content.js
      - [ ] test-chatgpt-viewport-coverage.js
      - [ ] test-provider-image-preservation.js
- [ ] 6. Computed-style assertions are recorded (viewport owner color, sidebar, composer, prompt-editor).
- [ ] 7. Browser cache, service-worker, or local-storage artifacts are cleared.
- [ ] 8. The verdict is recorded as LIVE with the operator's initials and timestamp.

## If any step fails

Set verdict = `NEEDS_OPERATOR_LIVE`. Document which step blocked. Do NOT
downgrade to ENGINEERING or claim live acceptance from offline gates alone.
