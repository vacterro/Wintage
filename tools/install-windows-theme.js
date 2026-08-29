#!/usr/bin/env node
'use strict';

// Merge Wintage's supported colour sections over the active Windows .theme.
// Wallpaper, sounds and desktop icons stay byte-for-byte in the merged
// file. The first active theme is snapshotted once; palette repaints never move
// that baseline, and --revert hands it back for ShellExecute activation.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { writeAtomic } = require('./write-atomic');

function fail(message) { console.error('install-windows-theme: ' + message); process.exit(1); }

const args = process.argv.slice(2);
function arg(name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
}
const themesDir = arg('--themes-dir');
const overlayFile = arg('--theme');
const currentTheme = arg('--current-theme');
const palette = arg('--palette');
const revert = args.includes('--revert');
const finalizeRevert = args.includes('--finalize-revert');
const dryRun = args.includes('--dry-run');

if (!themesDir) fail('--themes-dir is required');
if (![revert, finalizeRevert].some(Boolean) && (!overlayFile || !currentTheme || !palette)) {
  fail('apply requires --theme, --current-theme and --palette');
}

const legacyInstalled = path.join(themesDir, 'Wintage.theme');
const original = path.join(themesDir, 'Wintage.original.theme');
const originalPath = path.join(themesDir, '.wintage-original-theme-path');
const existingBackup = path.join(themesDir, 'Wintage.theme.wintage.bak');
const createdMarker = path.join(themesDir, 'Wintage.theme.wintage-created');
const paletteMarker = path.join(themesDir, '.wintage-windows-palette');
const activePathMarker = path.join(themesDir, '.wintage-active-theme-path');
// W2-003: a completed Revert RETIRES the snapshot epoch. The retired marker is
// the difference between "snapshot exists because an install is live" and
// "snapshot exists, but the epoch it belongs to ended and the snapshot may be
// stale (the user has changed themes since Revert)". The next fresh Apply must
// re-baseline from the THEN-CURRENT active theme even though the old snapshot
// file still physically exists - and it must never be deleted while Windows may
// still hold it as CurrentTheme. Reuse-on-repaint inside ONE epoch is untouched:
// repaint keeps the epoch baseline; a completed Revert ends it.
const epochRetired = path.join(themesDir, '.wintage-epoch-retired');

function read(file) { return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''); }
function remove(file) { if (fs.existsSync(file)) fs.unlinkSync(file); }

function parseIni(text) {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const trailing = /\r?\n$/.test(text);
  const chunks = [{ name: null, lines: [] }];
  for (const line of text.split(/\r?\n/)) {
    const match = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (match) chunks.push({ name: match[1], lines: [line] });
    else chunks[chunks.length - 1].lines.push(line);
  }
  return { chunks, eol, trailing };
}

function mergeTheme(baseText, overlayText) {
  const base = parseIni(baseText);
  const overlay = parseIni(overlayText);
  const owned = new Set(['theme', 'visualstyles', 'control panel\\colors', 'control panel\\cursors', 'masterthemeselector']);
  const overlayByName = new Map(overlay.chunks.filter(c => c.name).map(c => [c.name.toLowerCase(), c]));
  const replaced = new Set();

  base.chunks = base.chunks.map(chunk => {
    if (!chunk.name) return chunk;
    const key = chunk.name.toLowerCase();
    if (!owned.has(key) || !overlayByName.has(key)) return chunk;
    replaced.add(key);
    return { name: chunk.name, lines: overlayByName.get(key).lines.slice() };
  });
  for (const key of owned) {
    if (!replaced.has(key) && overlayByName.has(key)) {
      base.chunks.push({ name: overlayByName.get(key).name, lines: overlayByName.get(key).lines.slice() });
    }
  }
  if (!base.chunks.some(c => c.name && c.name.toLowerCase() === 'control panel\\desktop')) {
    base.chunks.push({ name: 'Control Panel\\Desktop', lines: ['[Control Panel\\Desktop]', 'Pattern='] });
  }

  const lines = [];
  for (const chunk of base.chunks) {
    while (lines.length && lines[lines.length - 1] === '' && chunk.lines[0] === '') chunk.lines.shift();
    lines.push(...chunk.lines);
    if (chunk.name && lines[lines.length - 1] !== '') lines.push('');
  }
  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines.join(base.eol) + (base.trailing ? base.eol : '');
}

if (finalizeRevert) {
  if (!dryRun) {
    remove(original);
    remove(originalPath);
    remove(existingBackup);
    remove(createdMarker);
    remove(paletteMarker);
    remove(activePathMarker);
    remove(epochRetired);
  }
  console.log(JSON.stringify({ finalized: true }));
  process.exit(0);
}

if (revert) {
  if (!fs.existsSync(original)) fail('no Wintage snapshot to restore');
  const activeManaged = fs.existsSync(activePathMarker) ? read(activePathMarker).trim() : null;
  const cleanup = activeManaged ? [activeManaged] : [];
  if (!dryRun && fs.existsSync(existingBackup)) writeAtomic(legacyInstalled, fs.readFileSync(existingBackup));
  else if (fs.existsSync(createdMarker)) cleanup.push(legacyInstalled);
  console.log(JSON.stringify({ activate: original, revert: true, cleanup: [...new Set(cleanup)] }));
  process.exit(0);
}

if (!fs.existsSync(overlayFile)) fail('generated theme not found: ' + overlayFile);
if (!fs.existsSync(currentTheme) && !fs.existsSync(original)) fail('active theme not found: ' + currentTheme);

// W2-003: firstApply also fires after a RETIRED epoch even though the old
// snapshot file still exists - the snapshot's epoch ended at Revert, so the
// then-current theme becomes the new baseline.
const firstApply = !fs.existsSync(original) || fs.existsSync(epochRetired);
const base = firstApply ? read(currentTheme) : read(original);
const merged = mergeTheme(base, read(overlayFile));
const hash = crypto.createHash('sha256').update(merged).digest('hex').slice(0, 10);
const installed = path.join(themesDir, `Wintage-${hash}.theme`);
const previousManaged = fs.existsSync(activePathMarker) ? read(activePathMarker).trim() : null;
const cleanup = previousManaged && path.resolve(previousManaged) !== path.resolve(installed) ? [previousManaged] : [];
if (fs.existsSync(createdMarker) && path.resolve(legacyInstalled) !== path.resolve(installed)) cleanup.push(legacyInstalled);
if (!dryRun) {
  fs.mkdirSync(themesDir, { recursive: true });
  if (firstApply) {
    writeAtomic(original, fs.readFileSync(currentTheme));
    writeAtomic(originalPath, path.resolve(currentTheme) + '\n');
    if (fs.existsSync(legacyInstalled)) writeAtomic(existingBackup, fs.readFileSync(legacyInstalled));
    else writeAtomic(createdMarker, 'created by Wintage\n');
    // The retired epoch is over: this snapshot is the fresh baseline again.
    remove(epochRetired);
  }
  writeAtomic(installed, merged);
  writeAtomic(paletteMarker, palette + '\n');
  writeAtomic(activePathMarker, installed + '\n');
}
console.log(JSON.stringify({ activate: installed, palette, firstApply, cleanup: [...new Set(cleanup)] }));
