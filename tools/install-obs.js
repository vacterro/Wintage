#!/usr/bin/env node
'use strict';

// Installs (or removes) the Wintage OBS theme.
//
// Ownership model (CORE-001/CORE-010): OBS artifacts are divided into three
// classes, and every one gets persistent, verifiable recovery recorded BEFORE
// the first mutation:
//   - user.ini        Wintage owns EXACTLY ONE key: [Appearance] Theme (T-189).
//                     The pre-Wintage existence/value of that key is snapshotted
//                     once (JSON recovery); a user.ini that did not exist is
//                     marked .wintage-created. Revert merges only the owned key
//                     back into the CURRENT user.ini (unrelated post-Apply user
//                     edits survive) or removes a Wintage-created file.
//   - themes/Wintage.ovt  created-or-replaced provenance plus exact replaced
//                     bytes (byte-for-byte restore). First generation is never
//                     overwritten by a repaint.
//   - .wintage-obs-palette  the Wintage palette marker; created/removed with us.
//
// The parent (targets.ps1 Invoke-Obs) owns the manifest transition; this helper
// must therefore NEVER consume its persistent recovery while a manifest commit
// could still fail. --revert therefore restores the target but keeps every
// recovery artifact; the parent consumes them (Remove-ObsRecovery, exported
// below) only AFTER the manifest transition succeeds. A standalone --revert
// with no manifest coordination (direct CLI use) consumes them normally.
//
// Revert preflights the COMPLETE required recovery set before touching anything
// and fails NONZERO with zero mutation when an installed target lacks required
// recovery - lost recovery is an unverifiable state, never permission to
// perform a destructive revert by guessing.
//
// Usage:
//   node tools/install-obs.js --config DIR (--theme FILE --palette SLUG | --revert) [--dry-run]
//   node tools/install-obs.js --config DIR --revert --keep-recovery   (parent-coordinated revert)
//   node tools/install-obs.js --config DIR --finalize-revert          (consume recovery after commit)

const fs = require('fs');
const path = require('path');
const { writeAtomic } = require('./write-atomic');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

const configDir = arg('--config');
const sourceTheme = arg('--theme');
const palette = arg('--palette');
const revert = process.argv.includes('--revert');
const keepRecovery = process.argv.includes('--keep-recovery');
const finalizeRevert = process.argv.includes('--finalize-revert');
const dryRun = process.argv.includes('--dry-run');

if (!configDir || (!revert && !finalizeRevert && (!sourceTheme || !palette))) {
  console.error('Usage: install-obs.js --config DIR (--theme FILE --palette SLUG | --revert [--keep-recovery] | --finalize-revert) [--dry-run]');
  process.exit(2);
}

const THEME_ID = 'com.wintage.OBS';
const userIni = path.join(configDir, 'user.ini');
const themesDir = path.join(configDir, 'themes');
const themeFile = path.join(themesDir, 'Wintage.ovt');
const markerFile = path.join(configDir, '.wintage-obs-palette');

// Wintage owns exactly ONE key in user.ini: [Appearance] Theme (T-189).
const THEME_KEY = 'Theme';
const THEME_SECTION = 'Appearance';

// ─── Persistent recovery (CORE-001) ─────────────────────────────────────────
// Three independent artifacts, written atomically BEFORE the first mutation:
//   user.ini.wintage.bak   JSON { existed, value } of the owned Theme key.
//   user.ini.wintage-created   empty marker = user.ini did not exist pre-Wintage.
//   Wintage.ovt.wintage.bak    JSON { existed, value? } - byte-exact replaced
//                          theme if a same-named user theme pre-existed.
//   Wintage.ovt.wintage-created empty marker = the .ovt did not exist.
const themeKeyBackup = `${userIni}.wintage.bak`;
const userIniCreated = `${userIni}.wintage-created`;
const ovtBackup = `${themeFile}.wintage.bak`;
const ovtCreated = `${themeFile}.wintage-created`;

function exists(p) { return fs.existsSync(p); }
function remove(p) { if (exists(p)) fs.unlinkSync(p); }

function ReadRecoveryJson(file) {
  if (!exists(file)) return null;
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return null; }
}

// parseIni -> { sections: {name: {key: value}}, order preserved via arrays }
function parseIni(source) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  const out = { bom, sections: {}, sectionOrder: [], keys: {} };
  let section = null;
  for (const line of source.split(/\r?\n/)) {
    const sm = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (sm) {
      section = sm[1];
      if (!(section in out.sections)) { out.sections[section] = {}; out.sectionOrder.push(section); }
      continue;
    }
    if (section) {
      const km = /^\s*([^=]+?)\s*=(.*)$/.exec(line);
      if (km) { out.sections[section][km[1].trim()] = km[2]; out.keys[section + '.' + km[1].trim()] = km[2]; }
    }
  }
  return out;
}

function removeIniKey(source, section, key) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  const eol = source.includes('\r\n') ? '\r\n' : '\n';
  const finalEol = source.endsWith('\n');
  const lines = source.length ? source.split(/\r?\n/) : [];
  if (finalEol) lines.pop();
  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*=`, 'i');
  const start = lines.findIndex((line) => sectionPattern.test(line));
  if (start >= 0) {
    let end = start + 1;
    while (end < lines.length && !/^\s*\[[^\]]+\]\s*$/.test(lines[end])) end += 1;
    const idx = lines.slice(start + 1, end).findIndex((line) => keyPattern.test(line));
    if (idx >= 0) lines.splice(start + 1 + idx, 1);
  }
  return bom + lines.join(eol) + (finalEol || !lines.length ? eol : '');
}

function setIniValue(source, section, key, value) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  const eol = source.includes('\r\n') ? '\r\n' : '\n';
  const finalEol = source.endsWith('\n');
  const lines = source.length ? source.split(/\r?\n/) : [];
  if (finalEol) lines.pop();

  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*=`, 'i');
  let start = lines.findIndex((line) => sectionPattern.test(line));
  if (start < 0) {
    if (lines.length && lines[lines.length - 1] !== '') lines.push('');
    lines.push(`[${section}]`, `${key}=${value}`);
  } else {
    let end = start + 1;
    while (end < lines.length && !/^\s*\[[^\]]+\]\s*$/.test(lines[end])) end += 1;
    const found = lines.slice(start + 1, end).findIndex((line) => keyPattern.test(line));
    if (found >= 0) lines[start + 1 + found] = `${key}=${value}`;
    else lines.splice(end, 0, `${key}=${value}`);
  }
  return bom + lines.join(eol) + (finalEol || !lines.length ? eol : '');
}

// Read the Theme-key snapshot. New format is JSON {existed, value}; a legacy
// whole-file .bak is parsed as INI and its Theme key extracted (T-189).
function readThemeSnapshot() {
  if (!exists(themeKeyBackup)) return null;
  const raw = fs.readFileSync(themeKeyBackup, 'utf8').trim();
  if (raw.startsWith('{')) {
    try {
      const j = JSON.parse(raw);
      if (typeof j.existed === 'boolean') return j;
    } catch (e) { /* fall through to INI */ }
  }
  const ini = parseIni(raw);
  const v = (ini.sections[THEME_SECTION] || {})[THEME_KEY];
  return { existed: v !== undefined, value: v === undefined ? null : v };
}

function currentThemeKeyValue() {
  if (!exists(userIni)) return undefined;
  const ini = parseIni(fs.readFileSync(userIni, 'utf8'));
  return (ini.sections[THEME_SECTION] || {})[THEME_KEY];
}

// ─── Revert preflight: the COMPLETE required recovery set (CORE-001) ────────
// An installed Wintage target must have, for user.ini: either the created
// marker or the Theme-key snapshot, and for the .ovt either the created marker
// or the byte snapshot. Missing mandatory recovery is an unverifiable state:
// fail nonzero BEFORE any mutation.
function assertRecoveryComplete() {
  const missing = [];
  if (!exists(userIniCreated) && !exists(themeKeyBackup)) missing.push(`Theme-key snapshot (${path.basename(themeKeyBackup)} or ${path.basename(userIniCreated)})`);
  if (!exists(ovtCreated) && !exists(ovtBackup)) missing.push(`theme snapshot (${path.basename(ovtBackup)} or ${path.basename(ovtCreated)})`);
  if (missing.length) {
    throw new Error(`OBS: required Wintage recovery is missing for ${configDir}: ${missing.join('; ')} - cannot restore an unverifiable state; nothing was changed.`);
  }
  // A snapshot that exists but cannot be parsed is equally unverifiable.
  if (exists(themeKeyBackup) && !readThemeSnapshot()) {
    throw new Error(`OBS: the Theme-key recovery file is corrupt (${themeKeyBackup}) - cannot restore; nothing was changed.`);
  }
  if (exists(ovtBackup) && !ReadRecoveryJson(ovtBackup)) {
    throw new Error(`OBS: the theme recovery file is corrupt (${ovtBackup}) - cannot restore; nothing was changed.`);
  }
}

// Direct (uncoordinated) revert consumes recovery; parent-coordinated revert
// (--keep-recovery) leaves it for the manifest-transition success path.
function consumeRecovery() {
  if (keepRecovery) return;
  remove(themeKeyBackup);
  remove(userIniCreated);
  remove(ovtBackup);
  remove(ovtCreated);
}

// ─── Apply / repaint ────────────────────────────────────────────────────────
if (revert) {
  if (dryRun) {
    console.log(`OBS Studio: would restore the [${THEME_SECTION}] ${THEME_KEY} key into the current ${path.basename(userIni)} and remove ${path.basename(themeFile)}`);
    process.exit(0);
  }
  // Never-installed state (no marker, no snapshot) is a legitimate no-op ONLY
  // when no mutating evidence exists either. A palette marker alone proves a
  // Wintage install (an earlier corrupt/lost-recovery state) - fail closed.
  if (!exists(userIniCreated) && !exists(themeKeyBackup) &&
      !exists(ovtCreated) && !exists(ovtBackup) && !exists(markerFile)) {
    console.log(`OBS Studio: no Wintage recovery state - nothing to revert.`);
    process.exit(0);
  }
  assertRecoveryComplete();
  if (exists(userIniCreated)) {
    // We created user.ini from nothing - drop it back to nothing.
    if (exists(userIni)) remove(userIni);
    remove(userIniCreated);
  } else {
    const snap = readThemeSnapshot();
    if (exists(userIni)) {
      let ini = fs.readFileSync(userIni, 'utf8');
      ini = snap && snap.existed
        ? setIniValue(ini, THEME_SECTION, THEME_KEY, snap.value)
        : removeIniKey(ini, THEME_SECTION, THEME_KEY);
      writeAtomic(userIni, ini);
    }
  }
  if (exists(ovtCreated)) {
    remove(themeFile);
    remove(ovtCreated);
  } else {
    const snap = ReadRecoveryJson(ovtBackup);
    if (snap && snap.existed && snap.value !== undefined && snap.value !== null) {
      // Byte-for-byte restore of a replaced user theme.
      writeAtomic(themeFile, snap.value);
    } else if (exists(themeFile)) {
      remove(themeFile);
    }
    remove(ovtBackup);
  }
  if (exists(markerFile)) remove(markerFile);
  consumeRecovery();
  console.log('OBS Studio: restored the previous theme selection into the current settings');
  process.exit(0);
}

if (finalizeRevert) {
  // Parent-coordinated: the manifest transition has committed; consume the
  // persistent recovery this helper correctly preserved during --revert.
  if (!dryRun) consumeRecovery();
  console.log(JSON.stringify({ finalized: true }));
  process.exit(0);
}

const theme = fs.readFileSync(sourceTheme, 'utf8');
if (!theme.includes(`id: '${THEME_ID}'`) || !theme.includes("extends: 'com.obsproject.Yami.Classic'")) {
  throw new Error('Built OBS theme is missing the Wintage ID or Yami Classic base.');
}

if (dryRun) {
  console.log(`OBS Studio: would install and activate ${palette}`);
  process.exit(0);
}

fs.mkdirSync(configDir, { recursive: true });
// Capture EVERY required recovery artifact BEFORE the first mutation; the
// first generation is never overwritten by a repaint (CORE-001).
if (!exists(userIniCreated) && !exists(themeKeyBackup)) {
  const current = exists(userIni) ? parseIni(fs.readFileSync(userIni, 'utf8')) : { sections: {} };
  const v = (current.sections[THEME_SECTION] || {})[THEME_KEY];
  writeAtomic(themeKeyBackup, `${JSON.stringify({ existed: v !== undefined, value: v === undefined ? null : v }, null, 2)}\n`);
  if (!exists(userIni)) { writeAtomic(userIniCreated, ''); }
}
if (!exists(ovtCreated) && !exists(ovtBackup)) {
  if (exists(themeFile)) {
    writeAtomic(ovtBackup, `${JSON.stringify({ existed: true, value: fs.readFileSync(themeFile, 'utf8') }, null, 2)}\n`);
  } else {
    writeAtomic(ovtCreated, '');
  }
}
const originalIni = exists(userIni) ? fs.readFileSync(userIni, 'utf8') : '';
writeAtomic(userIni, setIniValue(originalIni, THEME_SECTION, THEME_KEY, THEME_ID));
writeAtomic(themeFile, theme);
writeAtomic(markerFile, `${palette}\n`);
console.log(`OBS Studio: installed and activated ${palette}`);