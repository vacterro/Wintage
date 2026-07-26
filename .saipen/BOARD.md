# BOARD

## DOING

## TODO

## DONE
- [x] T-001 Tame animations: animation-duration/-delay 0.001s, global+shadow, verified safe, shipped v1.2.0
- [x] T-002 Kill style-recalc thrash: process() reads only, writes batched into one flush per sweep | verify: force tick 250ms -> 19-42ms, 996-element pixel diff vs v1.2.1 = 0
- [x] T-003 Sub-frames get CSS + observer + 3 bounded settling sweeps, no interval (@noframes rejected: would leave embeds unthemed)
- [x] T-004 Force sweeps demand-driven (new DOM / changed sheet / tab return / 30s heartbeat), not blind every 4.5s | verify: settled-page tick 1.3ms, 0 long tasks
- [x] T-005 Mutation batch de-dup: skip records whose ancestor is in the same batch, skip already-detached nodes

## BLOCKED
