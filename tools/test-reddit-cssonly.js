#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-reddit-cssonly.js
// T-902 / SRC-065: REDDIT IS A HIGH-CHURN, CSS-ONLY HOST. This is the RED
// CONTROL for that decision.
//
// Reddit is an infinite shreddit-component feed. The users reported Chromium
// renderer crashes (STATUS_ACCESS_VIOLATION is a NATIVE fault -- nothing here
// claims Wintage owns it) while the document-wide repainter was running on
// reddit.com. T-902 promotes Reddit into the EXISTING high-churn contract
// (one authority: HIGH_CHURN_HOST -> CSS_ONLY_MODE) instead of adding a second
// Reddit-only mode, and this gate exists so a future agent cannot silently
// remove `IS_REDDIT ||` from that line to chase a cosmetic gap: doing so
// re-arms the mutation observer, the computed-style sweeps, the CSSOM hover
// surgery and the force passes on the one host that must not have them.
//
// The classification half drives the REAL extracted host block in a vm (not a
// source-string copy of the regexes). The CSS half audits the T-902 rule group
// at RULE level: every selector must be a stable product contract (named custom
// element, ARIA role, stable data attribute/id) scoped to the Reddit host --
// no generated atomic class, no build hash, no :has(), no universal selector
// over the app tree.
// ═════════════════════════════════════════════════════════════════════════════

'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let bad = 0;
const check = (label, got, want) => {
  const ok = (want === undefined) ? Boolean(got) : (JSON.stringify(got) === JSON.stringify(want));
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};

const USERSCRIPT_PATH = path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(USERSCRIPT_PATH, 'utf8');

// ── the real host-classification block ───────────────────────────────────────
// Slice from the HOST declaration through the CSS_ONLY_MODE assignment. Both
// anchors are load-bearing: losing either means the single-authority shape
// changed and every assertion below would be grading a stale copy.
const HOST_START = '  const HOST = (location.hostname || \'\').toLowerCase();';
const HOST_END = '  const CSS_ONLY_MODE = HIGH_CHURN_HOST;';

function hostBlock(text) {
  const a = text.indexOf(HOST_START);
  const b = text.indexOf(HOST_END, a < 0 ? 0 : a);
  if (a < 0 || b < 0) return null;
  return text.slice(a, b + HOST_END.length);
}

function classify(host, text) {
  const block = hostBlock(text === undefined ? src : text);
  if (!block) return null;
  const sandbox = { location: { hostname: host } };
  return vm.runInNewContext(
    block + '\n({ IS_X: IS_X, IS_REDDIT: IS_REDDIT, IS_CHATGPT: IS_CHATGPT,' +
    ' IS_GOOGLE: IS_GOOGLE, HIGH_CHURN_HOST: HIGH_CHURN_HOST, CSS_ONLY_MODE: CSS_ONLY_MODE });',
    sandbox);
}

check('host block is present (HOST .. CSS_ONLY_MODE = HIGH_CHURN_HOST)', hostBlock(src) !== null, true);

// ONE authority: the flag is not re-derived anywhere. A second `CSS_ONLY_MODE =`
// assignment (e.g. a Reddit-only mode bolted on beside it) fails here.
check('exactly one CSS_ONLY_MODE assignment in the userscript',
  (src.match(/\bCSS_ONLY_MODE\s*=/g) || []).length, 1);
check('CSS_ONLY_MODE is HIGH_CHURN_HOST (no second gate, no Reddit-only override)',
  hostBlock(src).includes('const CSS_ONLY_MODE = HIGH_CHURN_HOST;'), true);
check('HIGH_CHURN_HOST reads IS_REDDIT', /const HIGH_CHURN_HOST = [^;]*\bIS_REDDIT\b/.test(src), true);
check('the IS_REDDIT term sits inside the HIGH_CHURN_HOST line, not in a parallel mode',
  /const HIGH_CHURN_HOST = [^;]*\bIS_REDDIT\b[^;]*;\s*\n\s*const CSS_ONLY_MODE = HIGH_CHURN_HOST;/.test(src), true);

// ── the Reddit hosts: classified high-churn, hence CSS-only ─────────────────
const REDDIT_HOSTS = ['www.reddit.com', 'reddit.com', 'old.reddit.com', 'new.reddit.com',
  'sh.reddit.com', 'www.redd.it', 'redd.it'];
for (const h of REDDIT_HOSTS) {
  const c = classify(h);
  check('IS_REDDIT true for ' + h, c && c.IS_REDDIT, true);
  check('HIGH_CHURN_HOST true for ' + h, c && c.HIGH_CHURN_HOST, true);
  check('CSS_ONLY_MODE true for ' + h + ' (lean path, no repainter)', c && c.CSS_ONLY_MODE, true);
}

// Look-alikes must never inherit it.
for (const h of ['reddit.com.evil.example', 'notreddit.com', 'reddit.community.example',
  'oldreddit.com', 'redd.it.evil.example', 'myreddit.com']) {
  const c = classify(h);
  check('look-alike ' + h + ' is NOT Reddit and NOT high-churn',
    c && (c.IS_REDDIT || c.HIGH_CHURN_HOST), false);
}

// ── no regression: the six hosts that already held the contract ─────────────
for (const h of ['x.com', 'twitter.com', 'chatgpt.com', 'chat.openai.com', 'claude.ai',
  'gemini.google.com', 'chat.qwen.ai', 'perplexity.ai']) {
  const c = classify(h);
  check('existing high-churn host ' + h + ' still CSS-only',
    c && c.HIGH_CHURN_HOST && c.CSS_ONLY_MODE, true);
}

// Controls: an ordinary site keeps the full repainter.
for (const h of ['example.com', 'localhost', 'github.com', 'news.ycombinator.com']) {
  const c = classify(h);
  check('control host ' + h + ' keeps the full (non-CSS-only) path',
    c && !c.HIGH_CHURN_HOST && !c.CSS_ONLY_MODE, true);
}

// A dev server must not be folded into the high-churn set (T-371 contract).
for (const h of ['localhost', '127.0.0.1', 'dev.local']) {
  const c = classify(h);
  check('dev host ' + h + ' is not high-churn', c && !c.HIGH_CHURN_HOST, true);
}

// ── RED CONTROL: remove IS_REDDIT and the classification MUST fail ──────────
const without = src.replace('IS_X || IS_CHATGPT || IS_REDDIT ||', 'IS_X || IS_CHATGPT ||');
check('RED control: the mutated copy really dropped the IS_REDDIT term',
  without !== src && !/const HIGH_CHURN_HOST = [^;]*\bIS_REDDIT\b/.test(without), true);
for (const h of ['www.reddit.com', 'reddit.com', 'old.reddit.com']) {
  const c = classify(h, without);
  check('RED control: without IS_REDDIT, ' + h + ' would fall back OFF CSS_ONLY_MODE',
    c && c.IS_REDDIT === true && c.CSS_ONLY_MODE === false, true);
}
check('RED control: a Reddit host still matches IS_REDDIT without the term (it must lose the *contract*, not the identity)',
  classify('www.reddit.com', without).IS_REDDIT, true);

// ── the host stamp the CSS keys off ────────────────────────────────────────
check('the Reddit host stamp data-w95-reddit is applied at runtime', src.includes("data-w95-reddit"), true);
check('the stamp is gated on IS_REDDIT (not on a re-tested hostname)', /IS_REDDIT[\s\S]{0,400}?data-w95-reddit|data-w95-reddit[\s\S]{0,400}?IS_REDDIT/.test(src), true);

// ── T-902 CSS group: RULE-LEVEL audit, stable product contracts only ────────
const CSS_START = '/* ── T-902: THE SURFACES THE JS REPAINTER USED TO CORRECT BY HAND';
const CSS_END = '/* Google Search & Material 3 / AI Overview / OneGoogle surface tokens */';
const gi = src.indexOf(CSS_START);
const gj = src.indexOf(CSS_END, gi < 0 ? 0 : gi);
check('the T-902 Reddit CSS group exists and is terminated', gi > 0 && gj > gi, true);

const group = (gi > 0 && gj > gi) ? src.slice(gi, gj) : '';
// Strip comments and the `${...}` token placeholders (their braces are not CSS
// block braces), then split on the `{` that opens each rule.
const body = group.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\$\{[^}]*\}/g, 'TOKEN');
const selectors = [];
for (const m of body.matchAll(/([^{}]+)\{/g)) {
  for (const s of m[1].split(',')) {
    const sel = s.trim();
    if (sel) selectors.push(sel);
  }
}
check('the group declares rules', selectors.length >= 8, true);
check('every selector in the group is scoped to html[data-w95-reddit="1"]',
  selectors.filter((s) => !s.startsWith('html[data-w95-reddit="1"] ')), []);

const BANNED = [
  [/:has\(/, ':has()'],
  [/\[class\*=/, 'substring class match [class*=]'],
  [/\[class\^=/, 'prefix class match'],
  [/\[id\*=/, 'substring id match'],
  [/\[style\*=/, 'inline-style substring match'],
  [/^\*\s*$|^\*\s*\{|html\[data-w95-reddit="1"\] \*\s*$/, 'universal selector over the app tree'],
  [/\.[a-z][a-z0-9]*-\d/, 'generated numbered class'],
  [/\._[a-z0-9]{5,}/, 'generated atomic class'],
  [/\.[a-z0-9]{6,}["\s]/, 'looks like a build-hashed class']
];
const bannedHits = [];
for (const sel of selectors) {
  for (const [re, name] of BANNED) {
    if (re.test(sel)) bannedHits.push(name + ' :: ' + sel);
  }
}
check('no banned selector shape in the T-902 group (generated classes, [class*=], :has(), universal)', bannedHits, []);

// Positive side: the group really covers the surfaces the repainter used to
// hand-correct -- comments, overlays, and the composer.
const joined = selectors.join(' , ');
check('group themes comments via the named shreddit element', /shreddit-comment\b/.test(joined), true);
check('group themes overlay shells via ARIA roles', /\[role="dialog"\]/.test(joined) && /\[role="menu"\]/.test(joined), true);
check('group themes the composer via a stable product hook', /shreddit-composer|contenteditable|role="textbox"/.test(joined), true);
check('group carries no drop shadows/universal |"*"| rule beyond the bounded comment descendant',
  selectors.filter((s) => s.endsWith(' *') && !s.startsWith('html[data-w95-reddit="1"] shreddit-comment')).length, 0);

// ── durable knowledge: the decision is written down where the next agent looks
check('the host gate carries the T-902 rationale comment', src.includes('REDDIT IS IN THIS SET ON PURPOSE (T-902)'), true);
check('the rationale names the fallback (fix the CSS, never re-arm the repainter)',
  /Removing IS_REDDIT from this line to chase a/.test(src) && /cosmetic gap re-arms all of that/.test(src), true);
check('the rationale refuses the native-crash causality claim',
  src.includes('STATUS_ACCESS_VIOLATION is') && src.includes('native fault'), true);

const ADR = path.join(__dirname, '..', '.saipen', 'KNOWLEDGE', 'ADR-010.md');
check('KNOWLEDGE/ADR-010.md records the Reddit CSS-only decision', fs.existsSync(ADR), true);
if (fs.existsSync(ADR)) {
  const adr = fs.readFileSync(ADR, 'utf8');
  check('ADR-010 states Reddit is high-churn / CSS-only', /HIGH_CHURN_HOST|CSS_ONLY_MODE/.test(adr), true);
  check('ADR-010 forbids removing IS_REDDIT to chase cosmetics', /IS_REDDIT/.test(adr), true);
}

console.log(bad === 0 ? '\nRESULT: reddit-cssonly OK' : '\nRESULT: ' + bad + ' FAIL');
process.exit(bad ? 1 : 0);
