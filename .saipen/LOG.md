# LOG

- 19.07.26 [E-001] [T-001] SCOUT: live-tested blanket animation-duration:0.001s on real qwen — rc-motion dropdown opens, hit-test itemClickable=true, 7 items, page responsive. Old "animations break rc-motion" fear = DISPROVEN. Snapback risk = only hits already-broken sites (no fill-mode reveal). Flood = Chromium coalesces to <=1/frame. Decision: restore animation taming, verified ground.
- 19.07.26 [E-002] [T-001] [parent: E-001] BUILD: added animation-duration/-delay:0.001s to motion rule GLOBAL_CSS+SHADOW_CSS, rewrote stale "animation NOT forced" comment. node --check PASS.
- 19.07.26 [E-003] [T-001] [parent: E-002] SHIP: release.ps1 minor bump -> v1.2.0, pushed origin/main 22a9bae.
- 19.07.26 [E-004] [T-001] [parent: E-003] VERIFY: published 1.2.0 fetched+injected on chat.qwen.ai -> rc-motion "+" dropdown itemClickable=true, 7 items; scan 1757 real els -> 0 hidden-by-snapback. GREEN. T-001 DONE.
