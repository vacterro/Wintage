#!/usr/bin/env node
'use strict';
// ChatGPT contract parity & drift gate.
//
// WHY THIS FILE EXISTS.
// Reads tools/chatgpt-live-contract.js (the single source of the current-live contract list)
// and requires every surface the inspector calls ALWAYS to be bound in the shipped sheet,
// or named as a transparent host whose themed owner is itself ALWAYS.
//
// RED CONTROLS:
// Goes red if the current-live viewport-owner rule is cut while older fallbacks remain.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? ' -- ' + detail : '')); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label, detail);
  return false;
}

const SRC = fs.readFileSync(USER_JS, 'utf8');

function templateLiteral(src, name) {
  const decl = 'const ' + name + ' = `';
  const i = src.indexOf(decl);
  if (i < 0) return '';
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(src.slice(start));
  return m ? src.slice(start, start + m.index) : '';
}

const FAST_CSS = templateLiteral(SRC, 'CHATGPT_FAST_CSS');
if (!FAST_CSS) {
  fail('CHATGPT_FAST_CSS not found in wintage.user.js');
  process.exit(1);
}

const contract = require('./chatgpt-live-contract.js');
const { CURRENT_LIVE_HOOKS, selectorParts } = contract;
const inspector = require('./inspect-web.js');

function verifyContracts(css) {
  const errs = [];
  const parts = new Set(selectorParts(css));

  // 1. Verify every current-live hook is present in the sheet
  for (const hook of CURRENT_LIVE_HOOKS) {
    const inSheet = parts.has(hook.css);
    if (!inSheet) {
      errs.push(`current-live hook missing from sheet: ${hook.css} (${hook.label})`);
    }

    const surfaceEntry = inspector.SURFACES.find(s => s.id === hook.surface);
    const inInspector = surfaceEntry && surfaceEntry.selector.includes(hook.inspector);
    if (!inInspector) {
      errs.push(`current-live hook inspector selector not in inspect-web: ${hook.inspector}`);
    }
  }

  // 2. Verify all ALWAYS surfaces
  const ALWAYS_SURFACES = inspector.SURFACES.filter(s => s.contract === inspector.CONTRACT.ALWAYS);
  for (const s of ALWAYS_SURFACES) {
    const isTransparentHost = !!inspector.TRANSPARENT_HOSTS[s.id];
    const selectors = s.selector.split(',').map(x => x.trim());
    const anyBound = selectors.some(sel => {
      if (sel === 'html') return css.includes('html[data-w95-chatgpt="1"]');
      return Array.from(parts).some(sp => sp.endsWith(sel) || sp.includes(sel));
    });

    if (!anyBound && !isTransparentHost) {
      errs.push(`ALWAYS surface "${s.id}" (${s.label}) is neither bound in sheet nor a transparent host`);
    }
  }

  return errs;
}

console.log('-- current-live contract hooks parity --');
const initialErrors = verifyContracts(FAST_CSS);
check('all current-live hooks and ALWAYS surfaces pass parity audit', initialErrors.length === 0, initialErrors.join('; '));

for (const hook of CURRENT_LIVE_HOOKS) {
  pass(`hook "${hook.label}" bound in sheet (${hook.css})`);
}

console.log('\n-- red controls --');
// Red Control: cut current-live viewport owner rule (div.thread-scroll-container)
// while keeping legacy fallback. Parity gate MUST fail.
const mutatedSheet = FAST_CSS.replace(
  /html\[data-w95-chatgpt="1"\] div\.thread-scroll-container\s*\{[^}]*\}/g,
  ''
);
const mutatedErrors = verifyContracts(mutatedSheet);
check('RC1: cutting current-live viewport-owner rule causes audit to fail as required',
  mutatedErrors.some(e => e.includes('div.thread-scroll-container')),
  mutatedErrors.join('; ')
);

if (bad > 0) {
  console.error('\ntest-chatgpt-contract-parity: ' + bad + ' failure(s)');
  process.exit(1);
}
console.log('\ntest-chatgpt-contract-parity gate: PASS');
process.exit(0);
