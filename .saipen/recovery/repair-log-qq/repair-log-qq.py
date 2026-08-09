#!/usr/bin/env python3
"""RECOVER: renumber active LOG's trailing E-220..E-224 (colliding with sealed
LOG-001.md) to E-378..E-382, repair mangled control bytes, re-chain parents,
append DEC lines. Preserves lines 1-89 byte-for-byte."""
import io, os, sys

LOG = os.path.join(os.path.dirname(__file__), "..", "LOG.md")

with open(LOG, "rb") as f:
    data = f.read()

marker = b"- 01.08.26 22:38 [E-220]"
pos = data.rfind(marker)
assert pos != -1, "marker not found"
# walk back to start of line (after previous \n)
line_start = data.rfind(b"\n", 0, pos) + 1
head = data[:line_start]

TS_NOW = b"01.08.26 20:47"

new_lines = [
    b"- 01.08.26 22:38 [E-378] [parent: E-377] [T-080] H: The first fix attempt failed due to a combination of PowerShell encoding corruption when rewriting the user script, and manually forcing -Palette claudecode which overrode the user's preferred goldendefault base theme.",
    b"- 01.08.26 22:38 [E-379] [parent: E-378] [T-080] RUN: BUILD -- Safely moved the transparency CSS rule to GLOBAL_CSS without corrupting UTF-8, and re-ran the installer without a forced palette so it gracefully falls back to the user's existing goldendefault preference.",
    b"- 01.08.26 22:42 [E-380] [parent: E-379] [T-080] RUN: Added live CSS hot-reloading for Electron apps. Patched shim.cjs to use fs.watch and wc.removeInsertedCSS/wc.insertCSS. Created tools/watch-claude.ps1 to rebuild and sync CSS into app.asar live on file changes.",
    b'- 01.08.26 22:46 [E-381] [parent: E-380] [T-080] H: Popups are transparent because they don\'t have standard role="menu" or menu/popup classes, so the GLOBAL_CSS transparency wipe catches them, but the Wintage re-solidify whitelist misses them. runSweeper adds the bevel because it sees the native border, resulting in a floating transparent bevel. Need the exact Claude Code container classes to add to the whitelist.',
    b"- 01.08.26 22:54 [E-382] [parent: E-381] [T-080] H: The popup lacks a bevel entirely, confirming it is fully missed by Wintage and only stripped by the global transparency wipe. Since DevTools is disabled in Claude Desktop, requested the user to inspect the identical popup on claude.ai in a standard browser to extract the custom classes needed for the whitelist.",
    b"- 01.08.26 20:47 [E-383] [parent: E-382] DEC: RECOVER -- the active LOG's trailing events reused sealed IDs E-220..E-224 (LOG-001.md) and carried control-byte-mangled text from an earlier session's broken escape handling; renumbered to E-378..E-382, parents re-chained, and fs.watch/app.asar/role=\"menu\"/runSweeper restored. The events describe the Claude transparency/hot-reload maintenance work committed locally as 69d3094..6e18ec1 (5 commits, unpushed, unticketed).",
    b"- 01.08.26 20:47 [E-384] [parent: E-383] [T-101] DEC: RECOVER -- T-101 shipped as v1.23.3 (7b79fd6, on origin) and its VERIFY passed (E-373/E-376), but the board kept it in DOING and STATE stayed SHIP/RUN release.ps1; closing T-101 to DONE and rebuilding STATE from evidence.",
]

tail = b"\r\n".join(new_lines) + b"\r\n"
out = head + tail

with open(LOG, "wb") as f:
    f.write(out)

# verify
with open(LOG, "rb") as f:
    chk = f.read()
assert chk.startswith(data[:100]), "head corrupted"
assert b"[E-378]" in chk and b"[E-384]" in chk, "renumber missing"
assert b"[E-220]" not in chk, "old ID still present"
print("OK lines:", chk.count(b"\n"), "bytes:", len(chk))
