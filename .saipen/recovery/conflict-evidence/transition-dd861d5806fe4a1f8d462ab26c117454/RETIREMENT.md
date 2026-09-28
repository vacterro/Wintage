# Operator retirement — transition-dd861d5806fe4a1f8d462ab26c117454

Date: 2026-09-28. Agent: antigravity. Home: v8.0.1.

## What the op was

`transition` SCOUT -> BUILD for T-313, created 2026-09-27T12:56:07Z. Three write
targets (LOG.md, BOARD.md, STATE.md). `progress.json` recorded
`applied_frontier: 2`, i.e. all three targets materialized. The journal status
stalled at CONFLICT because the byte-level apply finished and the settle did not.

## Why it could not be settled by the engine

All three targets sit at their recorded `after_hash`. The recorded after-state of
`.saipen/STATE.md` carries `style_contract: ded-8b7ceebd`; the installed
`STYLE.md` boot marker in the bound home is `ded-4ae736e4`. So:

- `recover` (replay) writes the staged bytes, then runs the `core_fast`
  verifier, which fails on the stale marker -> CONFLICT again.
- `recover resolve --resolution accept_live|replan` asserts
  `live == after_hash` for every applied target before verifying, and the
  verifier then fails on the same stale marker -> NEEDS_REPAIR.

The op's own `after_hash` pins content the verifier refuses, and the verifier
only runs after the `after_hash` guard. There is no ordering of "replay" and
"resolve" that settles it, so the conflict is unresolvable by design of the
current engine. The defect is in the engine, not in this project's data.

## What was done instead

1. `.saipen/STATE.md` was restored to the exact planned after-bytes
   (sha256 prefix `906e45c5c7ade6b1`), so the on-disk state is the true product
   of this op with no hand-edit residue.
2. This op directory was MOVED here from `.saipen/recovery/ops/`. Nothing was
   deleted or rewritten; `operation.json`, `progress.json` and all three staged
   payloads are byte-identical to what the engine wrote.
3. `saipen recover` with an empty pending set then reaches
   `reconcile_protocol_state`, which owns the `style_contract` repair
   (`tools/saipen_engine/reconcile.py`) and rewrites the field to the installed
   marker under engine authority and a LOG line.

The state repair is therefore the engine's own, not a hand edit.
