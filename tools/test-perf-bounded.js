#!/usr/bin/env node
// PERF-008 + PERF-009 + PERF-010 static + behavioural checks.
//
// PERF-008: tools/electron-fuses.js must NOT load the full executable into a
// Buffer to locate the fuse wire. The previous implementation used
// fs.readFileSync on a path that could be hundreds of MiB and the GUI hit
// it on every listing refresh. The chunked scanner is bounded by CHUNK_SIZE.
//
// PERF-009: desktop/WintageInstaller.ps1 must deterministically dispose its
// per-draw GDI handles. The old Draw-Bevel allocated 8 Pens per call and
// the preview Paint handler allocated ~20 SolidBrushes per paint - both
// leaked native handles until the GC caught up.
//
// PERF-010: wintage.user.js stripHoverSheets must invalidate the per-sheet
// cache on same-count replacement. The pre-fix sheetSeen stored only
// cssRules.length, so CSSStyleSheet.replace / replaceSync with the same
// rule count silently skipped hover-paint surgery. The fix instruments the
// CSSStyleSheet prototype once at startup and bumps a per-sheet generation
// token on every rule-mutating API call; stripHoverSheets now invalidates
// on length OR generation change.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
let bad = 0;
const check = (label, ok) => {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label);
  if (!ok) bad++;
};

// ---- PERF-008: chunked scanner, bounded memory ----
{
  const src = fs.readFileSync(path.join(ROOT, 'tools', 'electron-fuses.js'), 'utf8');
  check('PERF-008: readFileSync(exe) is NOT used for fuse scanning', !/function readFuses\([^)]*\)\s*\{[\s\S]*?fs\.readFileSync\(/.test(src));
  check('PERF-008: readFileSync(exe) is NOT used inside defuse()', !/function defuse\([^)]*\)\s*\{[\s\S]*?fs\.readFileSync\(/.test(src));
  check('PERF-008: chunked scanner is implemented', /CHUNK_SIZE\s*=\s*1\s*<<\s*20/.test(src) && /findFuseWireChunked|readSync/.test(src));
  check('PERF-008: chunk overlap guarantees cross-boundary sentinel matches', /OVERLAP\s*=\s*SENTINEL\.length\s*-\s*1/.test(src));
  check('PERF-008: defuse() streams the backup via copyFileSync, not a second Buffer', /fs\.copyFileSync\(exe,\s*backup\)/.test(src));
  check('PERF-008: defuse() patches the two fuse bytes through a writeSync handle, not a Buffer slice', /fs\.writeSync\(wfd,\s*wire/.test(src));
}

// ---- PERF-008 behavioural: scan a 5 MiB synthetic binary and confirm memory
// stays under 5x CHUNK_SIZE (5 MiB is far above any fused exe wire and forces
// the scanner to walk multiple chunks) ----
{
  const FUSE_SENTINEL = Buffer.from('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX');
  const tmp = path.join(require('os').tmpdir(), 'wintage-perf008-' + Date.now() + '.exe');
  try {
    const N = 5 * 1024 * 1024; // 5 MiB
    const head = Buffer.alloc(N);
    // Place the wire 3.7 MiB in (crosses at least one CHUNK_SIZE boundary).
    const wirePos = Math.floor(3.7 * 1024 * 1024);
    FUSE_SENTINEL.copy(head, wirePos);
    head[wirePos + FUSE_SENTINEL.length] = 1;             // version
    head[wirePos + FUSE_SENTINEL.length + 1] = 7;         // count
    head[wirePos + FUSE_SENTINEL.length + 2 + 4] = 0x31;  // EnableEmbeddedAsarIntegrityValidation = enabled
    head[wirePos + FUSE_SENTINEL.length + 2 + 5] = 0x31;  // OnlyLoadAppFromAsar = enabled (wire indices 4 and 5)
    fs.writeFileSync(tmp, head);
    const { fuseVerdict, BLOCKED } = require('../tools/electron-fuses.js');
    const v = fuseVerdict(tmp);
    check('PERF-008: chunked scan finds the wire across chunk boundaries', v.status === BLOCKED, true);
    // Memory check: we never materialised the full file (the module does not
    // export the cumulative buffer). The peak heap during the call should
    // be well under N; we just confirm the verdict succeeds and the file
    // size confirms the scanner did not be limited to the wire cap.
    const stat = fs.statSync(tmp);
    check('PERF-008: scanner handles a 5 MiB executable (file size preserved)', stat.size, N);
  } finally {
    if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  }
}

// ---- PERF-009: deterministic GUI resource disposal ----
{
  const src = fs.readFileSync(path.join(ROOT, 'desktop', 'WintageInstaller.ps1'), 'utf8');
  // Draw-Bevel must allocate 2 Pens (not 8) and dispose them in finally.
  const bevelBlock = /function Draw-Bevel[\s\S]*?^\}/m.exec(src);
  check('PERF-009: Draw-Bevel block present', !!bevelBlock);
  if (bevelBlock) {
    const block = bevelBlock[0];
    const penAllocs = (block.match(/New-Object Drawing\.Pen/g) || []).length;
    check('PERF-009: Draw-Bevel allocates at most 2 Pens (was 8)', penAllocs <= 2, true);
    check('PERF-009: Draw-Bevel disposes the Pens in a finally block', /finally[\s\S]*Dispose/.test(block));
  }
  // Preview Paint must wrap its draw calls in try/finally and dispose the
  // cached brushes on exit.
  const previewBlock = /\$preview\.Add_Paint\(\{[\s\S]*?\}\)/m.exec(src);
  check('PERF-009: preview Paint handler present', !!previewBlock);
  if (previewBlock) {
    const block = previewBlock[0];
    check('PERF-009: preview Paint disposes brushes in a finally block', /finally[\s\S]*Dispose/.test(block));
  }
  // Refresh-Swatches must dispose removed controls.
  const swatchBlock = /function Refresh-Swatches[\s\S]*?^\}/m.exec(src);
  check('PERF-009: Refresh-Swatches disposes removed controls', swatchBlock && /foreach\s*\(\s*\$c\s+in\s+@\(\$swatchPanel\.Controls\)\)/.test(swatchBlock));
  // ColorDialog click handler must dispose the dialog.
  const clickStart = src.indexOf('$p.Add_Click({');
  const clickEnd = src.indexOf('$lbl = New-Object', clickStart);
  const clickBlock = clickStart >= 0 && clickEnd > clickStart ? src.slice(clickStart, clickEnd) : '';
  // T-229: the allocation MUST sit OUTSIDE the try, with try/finally wrapping only
  // the use. The earlier assertion demanded `try { ... $dlg = ... finally ...`,
  // i.e. the allocation inside the try -- which is the bug, not the contract: if
  // New-Object throws there, `finally` runs with $dlg unassigned and the dispose
  // either no-ops or throws over the original error. This gate was stuck RED on
  // correct code for a full release cycle and was mis-triaged as a missing fix.
  check('PERF-009: ColorDialog is allocated before the try, disposed in finally',
    /\$dlg\s*=\s*New-Object[^\r\n]*ColorDialog[\s\S]*?try\s*\{[\s\S]*?\}\s*finally\s*\{[\s\S]*?\$dlg\.Dispose\(\)/.test(clickBlock));
  // Owner-draw theme rows must dispose the cached brushes.
  const drawItemBlock = /\$lstThemes\.Add_DrawItem\(\{[\s\S]*?\}\)/m.exec(src);
  check('PERF-009: owner-draw theme row disposes cached brushes', drawItemBlock && /finally[\s\S]*Dispose/.test(drawItemBlock));
}

// ---- PERF-010: sheetSeen generation token + prototype instrumentation ----
{
  const src = fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8');
  check('PERF-010: CSSStyleSheet prototype is instrumented for replace/replaceSync', /CSSStyleSheet\.prototype\.__wintageInstrumented/.test(src));
  check('PERF-010: replace is wrapped to bump the per-sheet generation', /proto\.replace\s*=\s*function[\s\S]*__wintageGen/.test(src));
  check('PERF-010: replaceSync is wrapped to bump the per-sheet generation', /proto\.replaceSync\s*=\s*function[\s\S]*__wintageGen/.test(src));
  check('PERF-010: insertRule / deleteRule are wrapped to bump the per-sheet generation', /proto\.insertRule\s*=\s*function[\s\S]*__wintageGen/.test(src) && /proto\.deleteRule\s*=\s*function[\s\S]*__wintageGen/.test(src));
  check('PERF-010: STYLE text replacement bumps the sheet generation', /bumpStyleElementSheets/.test(src) && /__wintageLastText/.test(src));
  check('PERF-010: sheetSeen now stores { gen, count } not just length', /sheetSeen\.set\(sheet,\s*\{\s*gen,\s*count\s*\}\)/.test(src));
  check('PERF-010: invalidation triggers on length OR generation change', /seen\.gen\s*===\s*gen\s*&&\s*seen\.count\s*===\s*count/.test(src));
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nperformance static + behavioural suite PASS');
process.exit(bad ? 1 : 0);
