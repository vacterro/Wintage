#!/usr/bin/env node
'use strict';

// Canonical terminal typography preference (T-283 / SRC-026).
//
// ONE per-machine preference for WHICH font Wintage applies to Windows Terminal
// and to classic conhost, plus the size and rendering mode the user chose. Both
// terminal targets, the GUI, the health probe and Reapply read THIS module --
// no target hard-codes a face independently any more.
//
// File: %APPDATA%\Wintage\terminal-font.json
//
//   { "schema": 1, "fontSlug": "jetbrains-mono", "family": "JetBrains Mono",
//     "size": 12, "renderingMode": "aliased" }
//
// Semantics:
//   - missing file            -> the backward-compatible default (see DEFAULT).
//   - present, valid          -> that preference.
//   - present, malformed      -> FAIL CLOSED: `readPreference` throws rather
//                                than silently overwriting the user's file with
//                                a default. Callers surface the error.
//   - writes are atomic       -> temp file + rename, never a torn document.
//
// The GUI, the CLI and the node helper all import this; there is exactly one
// schema and one validator.

const fs = require('fs');
const path = require('path');
const os = require('os');

const SCHEMA = 1;
const RENDERING_MODES = ['aliased', 'grayscale', 'cleartype'];
const SIZE_MIN = 7;
const SIZE_MAX = 24;

// The Wintage default when no preference exists. Terminus (TTF) for Windows is
// the face the project has shipped for Windows Terminal; the conhost default is
// resolved separately because a missing Terminus must fall back safely there.
const DEFAULT_PREFERENCE = Object.freeze({
  schema: SCHEMA,
  fontSlug: 'terminus-ttf',
  family: 'Terminus (TTF) for Windows',
  size: 12,
  renderingMode: 'aliased'
});

// The per-machine path, resolved EXACTLY like install.ps1's $WintageAppData:
// WINTAGE_APPDATA (the Wintage data dir itself, used by the test seam) wins;
// otherwise %APPDATA%\Wintage. The PowerShell reader in modules/json-doc.ps1
// resolves the same way, so both runtimes name the SAME file.
function preferencePath(appDataOverride) {
  if (appDataOverride) return path.join(appDataOverride, 'terminal-font.json');
  if (process.env.WINTAGE_APPDATA) return path.join(process.env.WINTAGE_APPDATA, 'terminal-font.json');
  const base = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  return path.join(base, 'Wintage', 'terminal-font.json');
}

function readOwnedDocument(file) {
  if (!fs.existsSync(file)) return { exists: false, value: null };
  const raw = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  let value;
  try {
    value = JSON.parse(raw);
  } catch (err) {
    const error = new Error(`terminal-font.json is unreadable (${err.message}) at ${file}; refusing to overwrite it with a default.`);
    error.code = 'PREFERENCE_MALFORMED';
    throw error;
  }
  return { exists: true, value };
}

function validate(pref) {
  const problems = [];
  if (!pref || typeof pref !== 'object' || Array.isArray(pref)) {
    problems.push('preference is not an object');
    return problems;
  }
  if (Number(pref.schema) !== SCHEMA) problems.push(`schema must be ${SCHEMA}`);
  if (typeof pref.fontSlug !== 'string' || !pref.fontSlug.trim()) problems.push('fontSlug must be a non-empty string');
  if (typeof pref.family !== 'string' || !pref.family.trim()) problems.push('family must be a non-empty string');
  const rawSize = pref.size;
  const size = Number(rawSize);
  if (!Number.isFinite(size) || !Number.isInteger(size) || size < SIZE_MIN || size > SIZE_MAX) problems.push(`size must be an integer in ${SIZE_MIN}..${SIZE_MAX}`);
  if (!RENDERING_MODES.includes(pref.renderingMode)) problems.push(`renderingMode must be one of ${RENDERING_MODES.join(', ')}`);
  return problems;
}

// Missing file -> default. Present-but-invalid -> PREFERENCE_MALFORMED throw.
// `fileOverride` (see --preference) lets a caller/tests point at an explicit
// document; otherwise the per-machine path is used.
function readPreference(appDataOverride, fileOverride) {
  const file = fileOverride || preferencePath(appDataOverride);
  const doc = readOwnedDocument(file);
  if (!doc.exists) return { ...DEFAULT_PREFERENCE, source: 'default', file };
  const problems = validate(doc.value);
  if (problems.length) {
    const error = new Error(`terminal-font.json is invalid (${problems.join('; ')}) at ${file}; refusing to overwrite it with a default.`);
    error.code = 'PREFERENCE_MALFORMED';
    throw error;
  }
  return {
    schema: SCHEMA,
    fontSlug: doc.value.fontSlug,
    family: doc.value.family,
    size: Number(doc.value.size),
    renderingMode: doc.value.renderingMode,
    source: 'file',
    file
  };
}

function writeAtomicText(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, text, 'utf8');
  fs.renameSync(tmp, file);
}

function writePreference(pref, appDataOverride, fileOverride) {
  const problems = validate(pref);
  if (problems.length) {
    const error = new Error(`refusing to write an invalid terminal-font preference (${problems.join('; ')})`);
    error.code = 'PREFERENCE_INVALID';
    throw error;
  }
  const file = fileOverride || preferencePath(appDataOverride);
  const doc = { schema: SCHEMA, fontSlug: pref.fontSlug, family: pref.family, size: Number(pref.size), renderingMode: pref.renderingMode };
  writeAtomicText(file, `${JSON.stringify(doc, null, 2)}\n`);
  return { ...doc, source: 'file', file };
}

module.exports = {
  SCHEMA,
  RENDERING_MODES,
  SIZE_MIN,
  SIZE_MAX,
  DEFAULT_PREFERENCE,
  preferencePath,
  validate,
  readPreference,
  writePreference
};

// ---------------------------------------------------------------------------
// CLI surface (T-283): the PowerShell GUI/CLI reaches the ONE canonical reader
// through this process instead of re-implementing the schema. Commands:
//   read  [--file PATH]                 -> JSON preference (default when missing)
//   path                                -> the per-machine preference path
//   write --slug S --family F --size N --mode M [--file PATH]
// A malformed document exits 3 (PREFERENCE_MALFORMED); a usage/invalid write
// exits 2. Nothing here ever silently rewrites a bad file.
// ---------------------------------------------------------------------------
function cliArg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

if (require.main === module) {
  const cmd = (process.argv[2] || 'read').toLowerCase();
  const fileOverride = cliArg('--file');
  try {
    if (cmd === 'path') {
      process.stdout.write(`${preferencePath()}\n`);
      process.exit(0);
    }
    if (cmd === 'read') {
      const pref = readPreference(undefined, fileOverride || undefined);
      process.stdout.write(`${JSON.stringify(pref)}\n`);
      process.exit(0);
    }
    if (cmd === 'write') {
      const slug = cliArg('--slug');
      const family = cliArg('--family');
      const size = cliArg('--size');
      const mode = cliArg('--mode');
      if (!slug || !family || size == null || !mode) {
        process.stderr.write('write requires --slug --family --size --mode\n');
        process.exit(2);
      }
      const written = writePreference({ schema: SCHEMA, fontSlug: slug, family, size: Number(size), renderingMode: mode }, undefined, fileOverride || undefined);
      process.stdout.write(`${JSON.stringify(written)}\n`);
      process.exit(0);
    }
    process.stderr.write(`unknown command '${cmd}' (expected read|path|write)\n`);
    process.exit(2);
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    process.exit(err.code === 'PREFERENCE_MALFORMED' ? 3 : 2);
  }
}
