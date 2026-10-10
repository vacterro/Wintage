#!/usr/bin/env node
'use strict';
// ChatGPT Web 2026 contract regression gate.
//
// WHY THIS FILE EXISTS.
// Proves that CHATGPT_FAST_CSS, the sheet ChatGPT actually receives on chatgpt.com,
// carries the authoritative current structural contracts and semantic token mappings,
// and rejects retired broad selectors.
//
// RED CONTROLS:
// Stripping the October contracts out of the active sheet turns this gate red.

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

function runAudit(cssText) {
  const errs = [];

  // Strip comments before analyzing rules so documentation mentioning old selectors does not fail
  const noComments = cssText.replace(/\/\*[\s\S]*?\*\//g, '');

  // 1. Required current-live and October contracts
  const REQUIRED_SELECTORS = [
    'html[data-w95-chatgpt="1"] #web-mobile-root',
    'html[data-w95-chatgpt="1"] [role="complementary"][aria-label="Sidebar"]',
    'html[data-w95-chatgpt="1"] [role="textbox"][contenteditable="true"]',
    'html[data-w95-chatgpt="1"] div.thread-scroll-container',
    'html[data-w95-chatgpt="1"] main',
    'html[data-w95-chatgpt="1"] [data-markdown-text-style="assistant-message"]',
    'html[data-w95-chatgpt="1"] [data-message-author-role="assistant"]',
    'html[data-w95-chatgpt="1"] [data-user-message-bubble="true"]',
    'html[data-w95-chatgpt="1"] [data-markdown-copy="code-block"]'
  ];

  for (const sel of REQUIRED_SELECTORS) {
    if (!noComments.includes(sel)) {
      errs.push('missing required selector: ' + sel);
    }
  }

  // 2. Token mappings must resolve to ${T.*} interpolations
  const REQUIRED_TOKENS = [
    '--chat-background-color: ${T.backgroundSoft}',
    '--composer-background-color: ${T.surface}',
    '--user-message-background-color: ${T.surfaceRaised}',
    '--codeblock-background-color: ${T.compareBack}'
  ];

  for (const tok of REQUIRED_TOKENS) {
    if (!noComments.includes(tok)) {
      errs.push('missing token interpolation: ' + tok);
    }
  }

  // 3. Retired selectors banned from active rules
  if (/\[class\*=["']?composer["']?\s*i?\]/i.test(noComments)) {
    errs.push('banned retired selector found: [class*="composer" i]');
  }
  if (/div\.sticky\.bottom-0/i.test(noComments)) {
    errs.push('banned retired selector found: div.sticky.bottom-0');
  }

  return errs;
}

const fastCss = templateLiteral(SRC, 'CHATGPT_FAST_CSS');
if (!fastCss) {
  fail('CHATGPT_FAST_CSS template literal could not be parsed from wintage.user.js');
  process.exit(1);
}

console.log('-- active ChatGPT stylesheet contract audit --');
const initialErrors = runAudit(fastCss);
check('CHATGPT_FAST_CSS carries all required October contracts and token mappings', initialErrors.length === 0, initialErrors.join('; '));

// Red Control: removing October contracts turns the gate red
console.log('\n-- red controls --');
const mutantCss = fastCss
  .replace(/html\[data-w95-chatgpt="1"\] #web-mobile-root/g, '/* removed */')
  .replace(/html\[data-w95-chatgpt="1"\] div\.thread-scroll-container/g, '/* removed */')
  .replace(/html\[data-w95-chatgpt="1"\] \[data-markdown-text-style="assistant-message"\]/g, '/* removed */');

const mutantErrors = runAudit(mutantCss);
check('RC1: stripping October contracts causes audit to fail as required', mutantErrors.length >= 3,
  'expected at least 3 errors, got: ' + mutantErrors.length);

const bannedMutantCss = fastCss + '\nhtml[data-w95-chatgpt="1"] div.sticky.bottom-0 { color: red; }\n';
const bannedErrors = runAudit(bannedMutantCss);
check('RC2: adding retired sticky.bottom-0 selector causes audit to fail as required', bannedErrors.length > 0);

if (bad > 0) {
  console.error('\ntest-chatgpt-2026: ' + bad + ' failure(s)');
  process.exit(1);
}
console.log('\ntest-chatgpt-2026 gate: PASS');
process.exit(0);
