---
phase: DONE
task: T-001
next_action: "none — T-001 shipped + verified. Next saipen run: HUNT."
blocker: none
agent: claude-opus-4-8
mode: full
updated: 2026-07-19T00:30:00Z
---

# Wintage — animation taming (saipen)

T-001 DONE + VERIFIED + SHIPPED as v1.2.0.

Verified fact (durable): blanket `animation-duration:0.001s` does NOT break Ant
Design rc-motion dropdowns — live hit-test on chat.qwen.ai (itemClickable=true,
7 items) + scan of 1757 real elements showed 0 content hidden by snapback. The
v1.0.9 revert of animation forcing was on an UNVERIFIED hypothesis; real culprit
was always transition top/left/width (fixed v1.1.1, height-only). See
KNOWLEDGE/ADR-001.md.
