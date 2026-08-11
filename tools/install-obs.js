#!/usr/bin/env node
'use strict';

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
const dryRun = process.argv.includes('--dry-run');

if (!configDir || (!revert && (!sourceTheme || !palette))) {
  console.error('Usage: install-obs.js --config DIR (--theme FILE --palette SLUG | --revert) [--dry-run]');
  process.exit(2);
}

const THEME_ID = 'com.wintage.OBS';
const userIni = path.join(configDir, 'user.ini');
const themesDir = path.join(configDir, 'themes');
const themeFile = path.join(themesDir, 'Wintage.ovt');
const markerFile = path.join(configDir, '.wintage-obs-palette');

// Wintage owns exactly ONE key in user.ini: [Appearance] Theme (T-189). Revert
// merges that key back into the CURRENT user.ini and preserves every other OBS
// setting the user changed after Apply - it never restores a whole old file.
const THEME_KEY = 'Theme';
const THEME_SECTION = 'Appearance';
// The snapshot file records the pre-Wintage value (or absence) of the Theme key.
const themeKeyBackup = `${userIni}.wintage.bak`;

function pathsFor(file) {
  return { backup: `${file}.wintage.bak`, created: `${file}.wintage-created` };
}

function backupOnce(file) {
  const state = pathsFor(file);
  if (fs.existsSync(state.backup) || fs.existsSync(state.created)) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (fs.existsSync(file)) fs.copyFileSync(file, state.backup);
  else fs.writeFileSync(state.created, '', 'utf8');
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
  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\s*=`, 'i');
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

  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\s*=`, 'i');
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
  if (!fs.existsSync(themeKeyBackup)) return null;
  const raw = fs.readFileSync(themeKeyBackup, 'utf8').trim();
  if (raw.startsWith('{')) {
    try { return JSON.parse(raw); } catch (e) { /* fall through to INI */ }
  }
  const ini = parseIni(raw);
  const v = (ini.sections[THEME_SECTION] || {})[THEME_KEY];
  return { existed: v !== undefined, value: v === undefined ? null : v };
}

function snapshotThemeKey() {
  const current = fs.existsSync(userIni) ? parseIni(fs.readFileSync(userIni, 'utf8')) : { sections: {} };
  const v = (current.sections[THEME_SECTION] || {})[THEME_KEY];
  fs.writeFileSync(themeKeyBackup, `${JSON.stringify({ existed: v !== undefined, value: v === undefined ? null : v }, null, 2)}\n`, 'utf8');
}

if (revert) {
  if (dryRun) {
    console.log(`OBS Studio: would restore the [${THEME_SECTION}] ${THEME_KEY} key into the current ${path.basename(userIni)} and remove ${path.basename(themeFile)}`);
    process.exit(0);
  }
  const createdState = pathsFor(userIni);
  if (fs.existsSync(createdState.created)) {
    // We created user.ini from nothing - drop it back to nothing.
    if (fs.existsSync(userIni)) fs.unlinkSync(userIni);
    fs.unlinkSync(createdState.created);
  } else {
    const snap = readThemeSnapshot();
    if (fs.existsSync(userIni)) {
      let ini = fs.readFileSync(userIni, 'utf8');
      ini = snap && snap.existed
        ? setIniValue(ini, THEME_SECTION, THEME_KEY, snap.value)
        : removeIniKey(ini, THEME_SECTION, THEME_KEY);
      writeAtomic(userIni, ini);
    }
    if (snap) fs.unlinkSync(themeKeyBackup);
  }
  if (fs.existsSync(themeFile)) fs.unlinkSync(themeFile);
  if (fs.existsSync(markerFile)) fs.unlinkSync(markerFile);
  console.log('OBS Studio: restored the previous theme selection into the current settings');
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
if (!fs.existsSync(themeKeyBackup)) snapshotThemeKey();
const originalIni = fs.existsSync(userIni) ? fs.readFileSync(userIni, 'utf8') : '';
writeAtomic(userIni, setIniValue(originalIni, THEME_SECTION, THEME_KEY, THEME_ID));
writeAtomic(themeFile, theme);
writeAtomic(markerFile, `${palette}\n`);
console.log(`OBS Studio: installed and activated ${palette}`);
