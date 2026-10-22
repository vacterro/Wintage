#!/usr/bin/env node
// Single source of truth for the theme pack contract (T-187: token-schema drift).
//
// The 21-token schema, the WCAG text roles and the pack identity rules used to
// live in four places at once — apply-themes.js, check-css.js, the GUI and the
// tests, each with its own copy that drifted in its own direction. This module
// is the canonical owner: the generators and gates import it, and PowerShell
// (which cannot require JS) consumes the exported `--json` snapshot that the
// release suite re-verifies against this file on every run.
//
// CLI:
//   node tools/theme-schema.js --json   # print { tokens, wcagRoles, wcagBackdrops } as JSON
//
// The emitted snapshot must stay byte-consistent with tools/theme-schema.json;
// tests/Run-Tests.ps1 FAILs the repo when they disagree.

const fs = require('fs');
const path = require('path');

// The complete token set every pack MUST carry. Order is display order: the
// GUI swatch grid, the generated THEMES block and the derive helpers all follow
// it, so it is part of the contract, not a cosmetic preference.
const REQUIRED_TOKENS = [
  'background', 'backgroundSoft',
  'surface', 'surfaceRaised', 'surfaceAlt',
  'borderDark', 'borderHighlight', 'bevelLight', 'borderMuted',
  'textPrimary', 'textSecondary', 'textMuted',
  'accentTeal', 'accentTealDeep',
  'success', 'warning', 'danger', 'dangerText',
  'selection', 'compareBack', 'link'
];

// The roles that actually carry TEXT and are therefore held to the WCAG AA
// 4.5:1 floor. This list is deliberately NOT borderHighlight: on light palettes
// that token is a near-white decorative bevel edge, not a text role, and gating it
// produced false FAILs for every palette where the edge is lighter than body text.
//
// Each role is measured against EVERY backdrop it can actually land on, not
// against one guessed backdrop:
//
//   textPrimary  - the theme's own CSS paints it on the page ground, on the soft
//                  ground, on panels (surface), on the three control faces
//                  (surfaceRaised / surfaceAlt / the :active face) and inside
//                  sunken fields (compareBack). A button label is text: gating
//                  only the page ground let CodeNomad's button label sit at
//                  3.91:1 on its own hover face.
//   textSecondary- visited links, on the soft ground. Unchanged from the
//                  original contract.
//   link         - links sit on the page ground AND on the soft ground. On a
//                  LIGHT palette the page ground (#C0C0C0) is DARKER than the
//                  soft ground (#FFFFFF), so measuring the link against the soft
//                  ground alone passed a 2.54:1 link on the gray the user
//                  actually reads (T-988).
//
// The backdrop list is data so the PowerShell consumers (the GUI editor and the
// release suite) can read the same contract from the --json snapshot instead of
// re-implementing it.
const WCAG_BACKDROPS = {
  textPrimary: ['background', 'backgroundSoft', 'surface', 'surfaceRaised', 'surfaceAlt', 'compareBack'],
  textSecondary: ['backgroundSoft'],
  link: ['background', 'backgroundSoft']
};
const WCAG_ROLES = Object.keys(WCAG_BACKDROPS);

// Load and validate every pack in a themes directory. Throws on the first
// violation so a malformed pack can never silently vanish from a build:
// a duplicate slug, duplicate label, filename/slug mismatch, missing token or
// unknown token is a hard error, never a quietly-overwritten row.
function loadAndValidatePacks(dir) {
  if (!fs.existsSync(dir)) throw new Error('no themes directory at ' + dir);
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();
  if (!files.length) throw new Error(dir + ' holds no .json packs');
  const themes = [];
  const slugFile = {};
  const labels = new Set();
  for (const f of files) {
    let pack;
    try {
      pack = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^\uFEFF/, ''));
    } catch (e) {
      throw new Error(f + ': not valid JSON — ' + e.message);
    }
    const slug = pack.slug || path.basename(f, '.json');
    if (!/^[a-z][a-z0-9]*$/.test(slug)) {
      throw new Error(f + ': slug "' + slug + '" must be lowercase alphanumeric (it becomes a JS identifier)');
    }
    if (path.basename(f, '.json') !== slug) {
      throw new Error(f + ': filename does not match pack.slug "' + slug + '" — the CLI lists packs by filename while the generators consume the internal slug, so the two must never disagree');
    }
    if (slugFile[slug]) {
      throw new Error(slugFile[slug] + ' and ' + f + ': duplicate slug "' + slug + '"');
    }
    if (!pack.label) throw new Error(f + ': no label');
    if (labels.has(pack.label)) {
      throw new Error(f + ': duplicate label "' + pack.label + '" — the GUI resolves selection by label, so two packs sharing one label are indistinguishable');
    }
    if (pack.label.includes("'")) throw new Error(f + ": label must not contain an apostrophe (it is emitted inside single quotes)");
    if (!pack.tokens || typeof pack.tokens !== 'object') throw new Error(f + ': no tokens object');
    for (const t of REQUIRED_TOKENS) {
      const v = pack.tokens[t];
      if (!v) throw new Error(f + ': missing token ' + t);
      if (!/^#[0-9A-Fa-f]{6}$/.test(v)) throw new Error(f + ': token ' + t + ' = "' + v + '" is not a 6-digit hex');
    }
    const extra = Object.keys(pack.tokens).filter(k => !REQUIRED_TOKENS.includes(k));
    if (extra.length) throw new Error(f + ': unknown token(s) ' + extra.join(', '));
    slugFile[slug] = f;
    labels.add(pack.label);
    themes.push({ slug, label: pack.label, order: typeof pack.order === 'number' ? pack.order : 99, tokens: pack.tokens });
  }
  // Menu order is the pack's own `order`, ties broken by slug — so the list a user
  // sees does not silently reshuffle when a pack is added.
  themes.sort((a, b) => a.order - b.order || a.slug.localeCompare(b.slug));
  return themes;
}

if (require.main === module) {
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ tokens: REQUIRED_TOKENS, wcagRoles: WCAG_ROLES, wcagBackdrops: WCAG_BACKDROPS }));
  } else {
    console.error('usage: node tools/theme-schema.js --json');
    process.exit(2);
  }
}

module.exports = { REQUIRED_TOKENS, WCAG_ROLES, WCAG_BACKDROPS, loadAndValidatePacks };
