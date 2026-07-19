---
phase: BUILD
task: T-001
next_action: "Edit wintage.user.js: add animation-duration:0.001s + animation-delay:0s to motion rule (GLOBAL_CSS + SHADOW_CSS), rewrite stale comment"
blocker: none
agent: claude-opus-4-8
mode: full
updated: 2026-07-19T00:00:00Z
---

# Wintage — animation taming (saipen)

Goal: make site animations instant/invisible (vintage no-motion) WITHOUT
breaking event-driven component libraries (the qwen rc-motion regression class).

Key verified fact this session: blanket `animation-duration:0.001s` does NOT
break Ant Design rc-motion dropdowns — proven live (hit-test clickable). The
v1.0.9 revert was based on an UNVERIFIED hypothesis; real culprit was always
transition top/left/width (fixed v1.1.1, height-only scope).
