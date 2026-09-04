#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { writeAtomic } = require('./write-atomic');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

const settingsPath = arg('--settings');
const palettePath = arg('--palette');
const revert = process.argv.includes('--revert');
const dryRun = process.argv.includes('--dry-run');
// W2-007: multi-item Revert must keep the recovery artifacts intact until the
// caller has confirmed EVERY recorded item reverted cleanly and the manifest
// has been removed. Without --keep-recovery the helper unlinks the .wintage.bak
// and the created/owned-field markers immediately, so an item-N failure
// commits items 1..N-1 irreversibly while the manifest still claims the entire
// set. --keep-recovery suppresses the cleanup; a follow-up --finalize-recovery
// (or a normal revert on a fully-cleaned manifest) consumes the artifacts.
const keepRecovery = process.argv.includes('--keep-recovery');
const finalizeRecovery = process.argv.includes('--finalize-recovery');

if (!settingsPath || (!revert && !finalizeRecovery && !palettePath)) {
  console.error('Usage: install-terminal.js --settings PATH (--palette PACK | --revert [--keep-recovery] | --finalize-recovery) [--dry-run]');
  process.exit(2);
}

const backupPath = `${settingsPath}.wintage.bak`;
const createdPath = `${settingsPath}.wintage-created`;
const markerPath = `${settingsPath}.wintage-palette`;
// Windows Terminal is cell-based: proportional Verdana overlaps neighbouring
// cells. Terminus (TTF) for Windows is the user's installed bitmap-style
// monospace (the classic console look) and keeps the requested compact
// sans-like look without lying to the renderer about glyph width.
const TERMINAL_FONT = 'Terminus (TTF) for Windows';

// The ONLY fields Wintage owns in settings.json (T-189). Revert merges these
// back into the CURRENT file and preserves every unrelated key/profile/setting
// the user changed after Apply - it never restores a whole old file.
const OWNED_FIELDS = {
  colorScheme: 'profiles.defaults.colorScheme',
  font: 'profiles.defaults.font',
  antialiasingMode: 'profiles.defaults.antialiasingMode',
  historySize: 'profiles.defaults.historySize'
};
// historySize is a FLOOR, not an exact value (T-193): a profile with no
// scrollback (historySize 0/absent) gets the Windows Terminal default 9000;
// a profile already above it is left alone. Revert restores the recorded value.
const TERMINAL_SCROLLBACK = 9000;
const OWNED_FONT_KEYS = ['face', 'size', 'weight'];

function getIn(obj, pathStr) {
  return pathStr.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}
function setIn(obj, pathStr, value) {
  const parts = pathStr.split('.');
  let o = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    const k = parts[i];
    if (o[k] == null || typeof o[k] !== 'object') o[k] = {};
    o = o[k];
  }
  o[parts[parts.length - 1]] = value;
  return obj;
}
function delIn(obj, pathStr) {
  const parts = pathStr.split('.');
  let o = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (o[parts[i]] == null) return;
    o = o[parts[i]];
  }
  delete o[parts[parts.length - 1]];
}

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
  writeAtomic(file, content);
}

// Field presence is tracked SEPARATELY from value (CORE-015): an explicitly
// configured historySize: 0 is a legitimate setting, not "absent". Truthiness
// tests would collapse it into absence and Revert would delete it.
function hasOwned(obj, pathStr) {
  const parts = pathStr.split('.');
  let o = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (o == null || typeof o !== 'object') return false;
    o = o[parts[i]];
  }
  return o != null && typeof o === 'object' && Object.prototype.hasOwnProperty.call(o, parts[parts.length - 1]);
}

// CORE-001: presence and value are SEPARATE facts. `null` cannot carry both,
// because a user may legitimately configure `"colorScheme": null` and a
// snapshot that records absence the same way makes Revert delete a real
// setting. Every owned scalar is stored as a cell instead.
function ownedCell(obj, pathStr) {
  return hasOwned(obj, pathStr)
    ? { present: true, value: getIn(obj, pathStr) }
    : { present: false };
}

// CORE-001: Apply normalises a legacy top-level `profiles` ARRAY into
// `{ defaults, list }`. That is a destructive representation change, so the
// original container form is recorded and restored; without it Revert leaves
// the user with a shape they never wrote.
function profilesShapeOf(settings) {
  if (!Object.prototype.hasOwnProperty.call(settings, 'profiles')) return { kind: 'absent' };
  const value = settings.profiles;
  if (Array.isArray(value)) return { kind: 'array' };
  if (value && typeof value === 'object') return { kind: 'object' };
  return { kind: 'other', value };
}

// CORE-001: Apply drops every scheme named Wintage before inserting its own.
// A user who happens to own a scheme by that name loses it permanently, so the
// displaced entries are captured verbatim and restored on Revert. Ownership is
// "this entry was not here before Apply", never "the name matches".
function schemesShapeOf(settings) {
  if (!Object.prototype.hasOwnProperty.call(settings, 'schemes')) {
    return { kind: 'absent', displaced: [] };
  }
  const value = settings.schemes;
  if (Array.isArray(value)) {
    return { kind: 'array', displaced: value.filter((item) => item && item.name === 'Wintage') };
  }
  return { kind: 'other', value, displaced: [] };
}

// A legacy whole-file backup (pre-T-189) is still usable: parse it and extract
// only the owned fields, so an old install reverts without time-travelling the
// rest of the file.
function readOwnedSnapshot(backupPathOrObject) {
  if (backupPathOrObject && typeof backupPathOrObject === 'object') {
    if (backupPathOrObject.__wintage_owned) return upgradeSnapshot(backupPathOrObject);
    // legacy whole-file backup: the file itself IS the pre-Apply document, so
    // presence, container shape and displaced schemes are all recoverable from
    // it exactly. This path loses nothing.
    const file = backupPathOrObject;
    return {
      __wintage_owned: true,
      schema: 2,
      fields: {
        colorScheme: ownedCell(file, OWNED_FIELDS.colorScheme),
        font: ownedCell(file, OWNED_FIELDS.font),
        antialiasingMode: ownedCell(file, OWNED_FIELDS.antialiasingMode),
        historySize: ownedCell(file, OWNED_FIELDS.historySize)
      },
      profiles: profilesShapeOf(file),
      schemes: schemesShapeOf(file)
    };
  }
  if (fs.existsSync(backupPathOrObject)) {
    return readOwnedSnapshot(readJsonc(backupPathOrObject));
  }
  return null;
}

// CORE-001: a schema-1 snapshot records only four scalars and overloads `null`
// for absence. It is migrated DELIBERATELY rather than reinterpreted: `null`
// keeps its old meaning (absent) because that is what the writer meant, and the
// facts schema 1 never recorded are marked unknown so Revert leaves those
// structures alone instead of inventing a shape.
function upgradeSnapshot(snap) {
  if (Number(snap.schema) >= 2) {
    return {
      __wintage_owned: true,
      schema: 2,
      fields: {
        colorScheme: normalizeCell(snap.fields && snap.fields.colorScheme),
        font: normalizeCell(snap.fields && snap.fields.font),
        antialiasingMode: normalizeCell(snap.fields && snap.fields.antialiasingMode),
        historySize: normalizeCell(snap.fields && snap.fields.historySize)
      },
      profiles: snap.profiles && snap.profiles.kind ? snap.profiles : { kind: 'unknown' },
      schemes: snap.schemes && snap.schemes.kind
        ? { displaced: [], ...snap.schemes }
        : { kind: 'unknown', displaced: [] }
    };
  }
  const legacyCell = (value) => (value === null || value === undefined
    ? { present: false }
    : { present: true, value });
  return {
    __wintage_owned: true,
    schema: 2,
    migrated_from: 1,
    fields: {
      colorScheme: legacyCell(snap.colorScheme),
      font: legacyCell(snap.font),
      antialiasingMode: legacyCell(snap.antialiasingMode),
      historySize: legacyCell(snap.historySize)
    },
    profiles: { kind: 'unknown' },
    schemes: { kind: 'unknown', displaced: [] }
  };
}

function normalizeCell(cell) {
  if (cell && typeof cell === 'object' && 'present' in cell) {
    return cell.present ? { present: true, value: cell.value } : { present: false };
  }
  return { present: false };
}

// Presence-aware merge (CORE-001/CORE-015): a snapshot field whose original
// value was explicitly 0 -- or explicitly null -- is restored as written, and
// only a field that was genuinely absent stays deleted.
function mergeOwnedField(current, pathStr, cell) {
  if (cell && cell.present) setIn(current, pathStr, cell.value);
  else delIn(current, pathStr);
}

// Merge the owned fields from the snapshot into the CURRENT settings, removing
// the Wintage scheme. Everything else in the current file survives untouched.
function mergeOwnedIntoCurrent(current, snap) {
  const fields = snap.fields;
  mergeOwnedField(current, OWNED_FIELDS.colorScheme, fields.colorScheme);
  const curFont = getIn(current, OWNED_FIELDS.font);
  const fontCell = fields.font;
  const snapFont = fontCell.present ? fontCell.value : undefined;
  if (snapFont && typeof snapFont === 'object' && !Array.isArray(snapFont)) {
    const merged = (curFont && typeof curFont === 'object' && !Array.isArray(curFont)) ? curFont : {};
    for (const k of OWNED_FONT_KEYS) {
      if (k in snapFont) merged[k] = snapFont[k];
      else delete merged[k];
    }
    setIn(current, OWNED_FIELDS.font, merged);
  } else if (fontCell.present) {
    // The original font was a scalar/null/array: restore it verbatim rather
    // than stripping keys off a value that never had them.
    setIn(current, OWNED_FIELDS.font, snapFont);
  } else {
    if (curFont && typeof curFont === 'object') {
      for (const k of OWNED_FONT_KEYS) delete curFont[k];
      if (Object.keys(curFont).length === 0) delIn(current, OWNED_FIELDS.font);
    }
  }
  mergeOwnedField(current, OWNED_FIELDS.antialiasingMode, fields.antialiasingMode);
  mergeOwnedField(current, OWNED_FIELDS.historySize, fields.historySize);
  restoreSchemes(current, snap.schemes);
  restoreProfilesShape(current, snap.profiles);
  return current;
}

// CORE-001: remove ONLY what Apply inserted and put back what it displaced.
// `schemes` is deleted again only when Apply is the reason it exists.
function restoreSchemes(current, shape) {
  const kind = shape && shape.kind;
  if (kind === 'other') {
    current.schemes = shape.value;
    return;
  }
  if (!Array.isArray(current.schemes)) return;
  const displaced = (shape && Array.isArray(shape.displaced)) ? shape.displaced : [];
  const survivors = current.schemes.filter((s) => !s || s.name !== 'Wintage');
  current.schemes = survivors.concat(displaced);
  // 'unknown' is a schema-1 snapshot: it never recorded whether `schemes`
  // existed before, so removing the key is a guess. Keep the (now empty) array
  // rather than deleting a structure we cannot prove Apply created.
  if (current.schemes.length === 0 && kind === 'absent') delete current.schemes;
}

// CORE-001: put the legacy ARRAY container back, but only when doing so loses
// nothing. A user who added real content under `profiles.defaults` after Apply
// cannot have it expressed in the array form, and their edit outranks the
// cosmetics of the original shape.
function restoreProfilesShape(current, shape) {
  const kind = shape && shape.kind;
  if (kind === 'other') {
    current.profiles = shape.value;
    return;
  }
  if (kind === 'absent') {
    const p = current.profiles;
    const emptyDefaults = !p || !p.defaults || Object.keys(p.defaults).length === 0;
    const onlyDefaults = !p || Object.keys(p).every((k) => k === 'defaults');
    if (emptyDefaults && onlyDefaults) delete current.profiles;
    return;
  }
  if (kind !== 'array') return;
  const p = current.profiles;
  if (!p || typeof p !== 'object' || Array.isArray(p) || !Array.isArray(p.list)) return;
  const defaults = p.defaults;
  const defaultsEmpty = !defaults || (typeof defaults === 'object' && Object.keys(defaults).length === 0);
  const extraKeys = Object.keys(p).filter((k) => k !== 'list' && k !== 'defaults');
  if (defaultsEmpty && extraKeys.length === 0) current.profiles = p.list;
}

if (finalizeRecovery) {
  // W2-007: --finalize-recovery can run standalone (no --revert) to consume
  // the recovery artifacts after the caller has confirmed the manifest
  // transition committed. It only runs when the manifest is no longer
  // claiming ownership (marker absent), so the caller cannot accidentally
  // delete the still-needed recovery.
  if (fs.existsSync(markerPath)) {
    console.error(`Windows Terminal: --finalize-recovery refused for ${settingsPath} - the palette marker is still present, the manifest still claims this item. Revert it first or pass --keep-recovery.`);
    process.exit(1);
  }
  const consumed = [];
  if (fs.existsSync(backupPath)) { fs.unlinkSync(backupPath); consumed.push(backupPath); }
  if (fs.existsSync(createdPath)) { fs.unlinkSync(createdPath); consumed.push(createdPath); }
  console.log(`Windows Terminal: finalised recovery for ${settingsPath} (${consumed.length} artifact(s) consumed).`);
  process.exit(0);
}

if (revert) {
  if (dryRun) {
    console.log(`Windows Terminal: would restore the Wintage-owned fields into ${settingsPath}`);
    process.exit(0);
  }
  // CORE-009: expected ownership must be explicit at the helper boundary. When
  // the palette marker says Wintage owns this file, the mandatory recovery
  // (created marker OR owned-field backup) MUST be present; a manifest-recorded
  // item whose recovery was lost is an unverifiable state and returns NONZERO
  // with settings, marker and manifest untouched - never a "nothing to revert".
  if (fs.existsSync(markerPath) && !fs.existsSync(createdPath) && !fs.existsSync(backupPath)) {
    console.error(`Windows Terminal: ${settingsPath} is Wintage-themed (palette marker present) but the recovery backup is missing - cannot restore an unverifiable state; nothing was changed.`);
    process.exit(1);
  }
  // An unrecorded standalone revert stays a no-op only when NO Wintage
  // ownership marker/state is present (CORE-009).
  if (!fs.existsSync(createdPath) && !fs.existsSync(backupPath) && !fs.existsSync(markerPath)) {
    console.log('Windows Terminal: no Wintage backup to restore.');
    process.exit(0);
  }
  if (fs.existsSync(createdPath)) {
    if (fs.existsSync(settingsPath)) fs.unlinkSync(settingsPath);
    // W2-007: with --keep-recovery the created marker survives so a failed
    // sibling revert can roll THIS item back to its pre-Revert themed state.
    if (!keepRecovery) fs.unlinkSync(createdPath);
  } else {
    const snap = readOwnedSnapshot(backupPath);
    if (!snap) {
      console.error(`Windows Terminal: the recovery backup at ${backupPath} is corrupt - cannot restore an unverifiable state; nothing was changed.`);
      process.exit(1);
    }
    const current = fs.existsSync(settingsPath) ? readJsonc(settingsPath) : {};
    mergeOwnedIntoCurrent(current, snap);
    replaceFile(settingsPath, `${JSON.stringify(current, null, 4)}\n`);
    // W2-007: --keep-recovery leaves the owned-field backup on disk so a
    // failed sibling revert can re-apply the original owned-field values.
    if (!keepRecovery) fs.unlinkSync(backupPath);
  }
  // W2-007: --keep-recovery leaves the marker in place too. The manifest
  // keeps claiming ownership until the caller confirms the whole multi-item
  // Revert succeeded and explicitly removes the manifest entry.
  if (fs.existsSync(markerPath) && !keepRecovery) fs.unlinkSync(markerPath);
  console.log(`Windows Terminal: restored the Wintage-owned fields into ${settingsPath}${keepRecovery ? ' (recovery preserved)' : ''}`);
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
// Owned-field snapshot captured from the ORIGINAL file before any mutation, so
// Revert can restore exactly these fields into whatever the file has become.
// CORE-001: presence is recorded separately from value, and the two structures
// Apply rewrites destructively -- the `profiles` container form and the schemes
// it displaces -- are recorded too. Without them Revert cannot reconstruct the
// pre-Apply document even though every gate passes.
const ownedSnapshot = {
  __wintage_owned: true,
  schema: 2,
  fields: {
    colorScheme: ownedCell(settings, OWNED_FIELDS.colorScheme),
    font: ownedCell(settings, OWNED_FIELDS.font),
    antialiasingMode: ownedCell(settings, OWNED_FIELDS.antialiasingMode),
    historySize: ownedCell(settings, OWNED_FIELDS.historySize)
  },
  profiles: profilesShapeOf(settings),
  schemes: schemesShapeOf(settings)
};
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
const curHistory = settings.profiles.defaults.historySize;
settings.profiles.defaults.historySize = (typeof curHistory === 'number' && curHistory > TERMINAL_SCROLLBACK)
  ? curHistory
  : TERMINAL_SCROLLBACK;

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
  if (fs.existsSync(settingsPath)) {
    // Snapshot ONLY the owned fields, never the whole file (T-189).
    fs.writeFileSync(backupPath, `${JSON.stringify(ownedSnapshot, null, 2)}\n`, 'utf8');
  } else {
    fs.writeFileSync(createdPath, '', 'utf8');
  }
}
replaceFile(settingsPath, `${JSON.stringify(settings, null, 4)}\n`);
fs.writeFileSync(markerPath, `${palette.slug}\n`, 'utf8');
console.log(`Windows Terminal: applied ${palette.slug} + ${TERMINAL_FONT}`);
