#!/usr/bin/env node
'use strict';
// ChatGPT fast CSS performance & selector safety gate.
//
// WHY THIS FILE EXISTS.
// Locks the CSS-only high-churn path for ChatGPT, and guarantees that neither
// CHATGPT_FAST_CSS nor CHATGPT_FAST_SHADOW_CSS contains performance-killing
// selectors (:has(), class-substring, universal all-element, or generated atomic classes).
//
// RED CONTROLS:
// Violating any selector ban or detaching the high-churn path turns this gate red.

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
const FAST_SHADOW_CSS = templateLiteral(SRC, 'CHATGPT_FAST_SHADOW_CSS');

if (!FAST_CSS || !FAST_SHADOW_CSS) {
  fail('CHATGPT_FAST_CSS or CHATGPT_FAST_SHADOW_CSS not found in wintage.user.js');
  process.exit(1);
}

// 1. Verify routing architecture
console.log('-- high-churn routing architecture --');
check('IS_CHATGPT routes to CHATGPT_FAST_CSS',
  SRC.includes('IS_CHATGPT') && /ACTIVE_GLOBAL_CSS\s*=\s*IS_CHATGPT\s*\?\s*CHATGPT_FAST_CSS/s.test(SRC));
check('HIGH_CHURN_HOST classification includes IS_CHATGPT',
  /HIGH_CHURN_HOST\s*=[^;]*IS_CHATGPT/s.test(SRC));

// 2. Selector safety audit
console.log('\n-- selector safety audit --');
function auditSheet(css, name) {
  const errs = [];
  const text = css.replace(/\/\*[\s\S]*?\*\//g, '');

  // Extract selectors (text before '{')
  let depth = 0, from = 0;
  const selectors = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '{') {
      if (depth === 0) {
        for (const s of text.slice(from, i).split(',')) {
          const trimmed = s.trim();
          if (trimmed && !trimmed.startsWith('@')) selectors.push(trimmed);
        }
      }
      depth++;
    } else if (text[i] === '}') {
      depth--;
      if (depth === 0) from = i + 1;
    }
  }

  for (const sel of selectors) {
    if (sel.includes(':has(')) {
      errs.push(`${name}: :has() forbidden in selector: "${sel}"`);
    }
    if (/\[class\*=/i.test(sel)) {
      errs.push(`${name}: class-substring selector forbidden: "${sel}"`);
    }
    if (/(^|[\s>+~])\*(?![a-zA-Z0-9_-])/.test(sel)) {
      errs.push(`${name}: universal all-element selector forbidden: "${sel}"`);
    }
    if (/\bx-[a-z0-9]{4,}\b/i.test(sel)) {
      errs.push(`${name}: generated atomic class forbidden: "${sel}"`);
    }
  }

  return errs;
}

const fastErrs = auditSheet(FAST_CSS, 'CHATGPT_FAST_CSS');
const shadowErrs = auditSheet(FAST_SHADOW_CSS, 'CHATGPT_FAST_SHADOW_CSS');
check('CHATGPT_FAST_CSS passes all selector safety checks', fastErrs.length === 0, fastErrs.join('; '));
check('CHATGPT_FAST_SHADOW_CSS passes all selector safety checks', shadowErrs.length === 0, shadowErrs.join('; '));

// 3. October contracts present in fast sheet
console.log('\n-- contract presence --');
const fastClean = FAST_CSS.replace(/\/\*[\s\S]*?\*\//g, '');
check('October app-root contract present', fastClean.includes('#web-mobile-root'));
check('October viewport-owner contract present', fastClean.includes('div.thread-scroll-container'));
check('October prompt-editor contract present', fastClean.includes('[role="textbox"][contenteditable="true"]'));
check('October assistant-message contract present', fastClean.includes('[data-markdown-text-style="assistant-message"]'));

// 4. Red controls
console.log('\n-- red controls --');
const hasViolation = auditSheet(FAST_CSS + '\nhtml[data-w95-chatgpt="1"] div:has(p) { color: red; }\n', 'test');
check('RC1: :has() turns gate red', hasViolation.length > 0);

const substringViolation = auditSheet(FAST_CSS + '\nhtml[data-w95-chatgpt="1"] [class*="composer"] { color: red; }\n', 'test');
check('RC2: class-substring selector turns gate red', substringViolation.length > 0);

const universalViolation = auditSheet(FAST_CSS + '\nhtml[data-w95-chatgpt="1"] main * { color: red; }\n', 'test');
check('RC3: universal all-element selector turns gate red', universalViolation.length > 0);

const atomicViolation = auditSheet(FAST_CSS + '\nhtml[data-w95-chatgpt="1"] .x-a1b2c3d4 { color: red; }\n', 'test');
check('RC4: generated atomic class turns gate red', atomicViolation.length > 0);

if (bad > 0) {
  console.error('\ntest-chatgpt-perf-css: ' + bad + ' failure(s)');
  process.exit(1);
}
console.log('\ntest-chatgpt-perf-css gate: PASS');
process.exit(0);
