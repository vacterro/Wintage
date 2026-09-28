#!/usr/bin/env node
'use strict';

// Canonical terminal font catalog loader (T-283 / SRC-026).
//
// ONE catalog, ONE validator. The GUI, install-terminal.js, the conhost target
// and every test read fonts/terminal/catalog.json through this module -- font
// metadata is never scattered across GUI code, install.ps1 and tests.
//
// The loader also exposes the CAPABILITY probe used to decide what a face may be
// applied to. Capability is computed, never assumed:
//   - a bundled face is previewable because the file is present;
//   - a family is USABLE only when a real font probe resolves it on this machine
//     (installed), which is the same question Windows Terminal and conhost ask;
//   - classic conhost additionally requires a fixed-pitch face.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const CATALOG_PATH = path.join(ROOT, 'fonts', 'terminal', 'catalog.json');

function catalogPath() {
  return CATALOG_PATH;
}

function readCatalog(file) {
  const p = file || CATALOG_PATH;
  const raw = fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '');
  const doc = JSON.parse(raw);
  if (!doc || Number(doc.schema) !== 1 || !Array.isArray(doc.fonts)) {
    throw new Error(`${p}: catalog must carry schema 1 and a fonts array.`);
  }
  return doc;
}

// A coarse but honest family-resolution probe. GDI+ enumeration sees HKLM, HKCU
// and per-user Fonts alike; the registry fallback exists for a host without
// System.Drawing. This mirrors desktop/modules/targets.ps1's Test-WintageFontInstalled.
function installedFamilies() {
  const names = new Set();
  try {
    const { execFileSync } = require('child_process');
    const script = [
      'Add-Type -AssemblyName System.Drawing -ErrorAction Stop;',
      '[System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }'
    ].join(' ');
    const out = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], { encoding: 'utf8', timeout: 30000 });
    for (const line of out.split(/\r?\n/)) {
      const name = line.trim();
      if (name) names.add(name);
    }
  } catch (err) {
    // No probe available: report an empty set, never invent capability.
  }
  return names;
}

function familyInstalled(family, probe) {
  const set = probe || installedFamilies();
  return set.has(family);
}

// Resolve a catalog entry to its absolute vendored file path (bundled only).
function fontFile(entry) {
  if (!entry || !entry.bundled || !entry.file) return null;
  return path.join(ROOT, 'fonts', 'terminal', entry.file);
}

function findFont(slug, catalog) {
  const doc = catalog || readCatalog();
  return doc.fonts.find((f) => f.slug === slug) || null;
}

module.exports = {
  CATALOG_PATH,
  catalogPath,
  readCatalog,
  installedFamilies,
  familyInstalled,
  fontFile,
  findFont
};
