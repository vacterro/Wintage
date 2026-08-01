#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

const settingsPath = arg('--settings');
const palettePath = arg('--palette');
const revert = process.argv.includes('--revert');
const dryRun = process.argv.includes('--dry-run');

if (!settingsPath || (!revert && !palettePath)) {
  console.error('Usage: install-terminal.js --settings PATH (--palette PACK | --revert) [--dry-run]');
  process.exit(2);
}

const backupPath = `${settingsPath}.wintage.bak`;
const createdPath = `${settingsPath}.wintage-created`;
const markerPath = `${settingsPath}.wintage-palette`;
// Windows Terminal is cell-based: proportional Verdana overlaps neighbouring
// cells. Consolas preserves the requested compact sans-like look without lying
// to the renderer about glyph width.
const TERMINAL_FONT = 'Consolas';

function stripJsonComments(source) {
  let out = '';
  let quote = false;
  let escape = false;
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i];
    const n = source[i + 1];
    if (quote) {
      out += c;
      if (escape) escape = false;
      else if (c === '\\') escape = true;
      else if (c === '"') quote = false;
      continue;
    }
    if (c === '"') {
      quote = true;
      out += c;
      continue;
    }
    if (c === '/' && n === '/') {
      while (i < source.length && source[i] !== '\n') i += 1;
      out += '\n';
      continue;
    }
    if (c === '/' && n === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) {
        if (source[i] === '\n') out += '\n';
        i += 1;
      }
      i += 1;
      continue;
    }
    out += c;
  }
  return out;
}

function stripTrailingCommas(source) {
  let out = '';
  let quote = false;
  let escape = false;
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i];
    if (quote) {
      out += c;
      if (escape) escape = false;
      else if (c === '\\') escape = true;
      else if (c === '"') quote = false;
      continue;
    }
    if (c === '"') {
      quote = true;
      out += c;
      continue;
    }
    if (c === ',') {
      let j = i + 1;
      while (/\s/.test(source[j] || '')) j += 1;
      if (source[j] === '}' || source[j] === ']') continue;
    }
    out += c;
  }
  return out;
}

function readJsonc(file) {
  const source = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(stripTrailingCommas(stripJsonComments(source)));
}

function replaceFile(file, content) {
  const temp = `${file}.wintage-tmp`;
  fs.writeFileSync(temp, content, 'utf8');
  fs.renameSync(temp, file);
}

function restoreFile(backup, file) {
  const temp = `${file}.wintage-tmp`;
  fs.copyFileSync(backup, temp);
  fs.renameSync(temp, file);
}

if (revert) {
  if (dryRun) {
    console.log(`Windows Terminal: would restore ${settingsPath}`);
    process.exit(0);
  }
  if (fs.existsSync(createdPath)) {
    if (fs.existsSync(settingsPath)) fs.unlinkSync(settingsPath);
    fs.unlinkSync(createdPath);
  } else if (fs.existsSync(backupPath)) {
    restoreFile(backupPath, settingsPath);
    fs.unlinkSync(backupPath);
  } else {
    console.log('Windows Terminal: no Wintage backup to restore.');
    process.exit(0);
  }
  if (fs.existsSync(markerPath)) fs.unlinkSync(markerPath);
  console.log(`Windows Terminal: restored ${settingsPath}`);
  process.exit(0);
}

const palette = readJsonc(palettePath);
const t = palette.tokens;
const required = [
  'background', 'surfaceAlt', 'borderMuted', 'textPrimary', 'textSecondary',
  'accentTeal', 'accentTealDeep', 'success', 'warning', 'danger', 'dangerText',
  'selection', 'link'
];
for (const key of required) {
  if (!/^#[0-9a-f]{6}$/i.test(t[key] || '')) throw new Error(`Palette token '${key}' is missing or invalid.`);
}

const settings = fs.existsSync(settingsPath) ? readJsonc(settingsPath) : {};
if (Array.isArray(settings.profiles)) {
  settings.profiles = { defaults: {}, list: settings.profiles };
} else if (!settings.profiles || typeof settings.profiles !== 'object') {
  settings.profiles = {};
}
if (!settings.profiles.defaults || Array.isArray(settings.profiles.defaults)) settings.profiles.defaults = {};
settings.profiles.defaults.colorScheme = 'Wintage';
const oldFont = settings.profiles.defaults.font
  && typeof settings.profiles.defaults.font === 'object'
  && !Array.isArray(settings.profiles.defaults.font)
  ? settings.profiles.defaults.font
  : {};
settings.profiles.defaults.font = {
  ...oldFont,
  face: TERMINAL_FONT,
  size: 12,
  weight: 'normal'
};
settings.profiles.defaults.antialiasingMode = 'aliased';

const scheme = {
  name: 'Wintage',
  background: t.background,
  foreground: t.textPrimary,
  cursorColor: t.link,
  selectionBackground: t.selection,
  black: t.background,
  blue: t.accentTealDeep,
  cyan: t.accentTeal,
  green: t.success,
  purple: t.surfaceAlt,
  red: t.danger,
  white: t.textSecondary,
  yellow: t.warning,
  brightBlack: t.borderMuted,
  brightBlue: t.link,
  brightCyan: t.accentTeal,
  brightGreen: t.success,
  brightPurple: t.surfaceAlt,
  brightRed: t.dangerText,
  brightWhite: t.textPrimary,
  brightYellow: t.textPrimary
};
settings.schemes = Array.isArray(settings.schemes)
  ? settings.schemes.filter((item) => !item || item.name !== 'Wintage')
  : [];
settings.schemes.push(scheme);

if (dryRun) {
  console.log(`Windows Terminal: would apply ${palette.slug} + ${TERMINAL_FONT} to ${settingsPath}`);
  process.exit(0);
}

fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
if (!fs.existsSync(backupPath) && !fs.existsSync(createdPath)) {
  if (fs.existsSync(settingsPath)) fs.copyFileSync(settingsPath, backupPath);
  else fs.writeFileSync(createdPath, '', 'utf8');
}
replaceFile(settingsPath, `${JSON.stringify(settings, null, 4)}\n`);
fs.writeFileSync(markerPath, `${palette.slug}\n`, 'utf8');
console.log(`Windows Terminal: applied ${palette.slug} + ${TERMINAL_FONT}`);
