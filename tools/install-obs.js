#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

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

function pathsFor(file) {
  return { backup: `${file}.wintage.bak`, created: `${file}.wintage-created` };
}

function writeAtomic(file, content) {
  const temp = `${file}.wintage-tmp`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(temp, content);
  fs.renameSync(temp, file);
}

function backupOnce(file) {
  const state = pathsFor(file);
  if (fs.existsSync(state.backup) || fs.existsSync(state.created)) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (fs.existsSync(file)) fs.copyFileSync(file, state.backup);
  else fs.writeFileSync(state.created, '', 'utf8');
}

function restore(file) {
  const state = pathsFor(file);
  if (fs.existsSync(state.backup)) {
    const temp = `${file}.wintage-tmp`;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.copyFileSync(state.backup, temp);
    fs.renameSync(temp, file);
    fs.unlinkSync(state.backup);
  } else if (fs.existsSync(state.created)) {
    if (fs.existsSync(file)) fs.unlinkSync(file);
    fs.unlinkSync(state.created);
  }
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

if (revert) {
  if (dryRun) {
    console.log(`OBS Studio: would restore ${userIni} and ${themeFile}`);
    process.exit(0);
  }
  restore(userIni);
  restore(themeFile);
  if (fs.existsSync(markerFile)) fs.unlinkSync(markerFile);
  console.log('OBS Studio: restored previous theme and selection');
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
backupOnce(userIni);
backupOnce(themeFile);
const originalIni = fs.existsSync(userIni) ? fs.readFileSync(userIni, 'utf8') : '';
writeAtomic(userIni, setIniValue(originalIni, 'Appearance', 'Theme', THEME_ID));
writeAtomic(themeFile, theme);
writeAtomic(markerFile, `${palette}\n`);
console.log(`OBS Studio: installed and activated ${palette}`);
