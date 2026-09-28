#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-goodemoji-matchsrc.js
// PERF-005 (audit/7.md, SRC-018:R017): matchSrc is bounded by URL length.
//
// The old fallback ran Object.entries(codeToItem) and up to three src.includes
// per code for EVERY unmatched image: measured 2,880,000 String.includes for
// 1,000 ordinary unmatched URLs, and it materialised a fresh ~960-entry array
// per call. Matching must stay proportional to URL length, independent of the
// mapping-table size, while every mapped base/tone/variation/gender URL resolves
// identically and no substring-prefix false positive is introduced.
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

const PLUGIN = path.join(__dirname, '..', 'desktop', 'targets', 'betterdiscord', 'plugins', 'GoodEmoji.plugin.js');

function loadPlugin(counters) {
  const ctx = {
    console: { log: () => { } },
    document: { documentElement: { lang: 'en', getAttribute: () => 'en' }, querySelectorAll: () => [] },
    navigator: { language: 'en' },
    Node: { TEXT_NODE: 3, ELEMENT_NODE: 1 },
    NodeFilter: { SHOW_TEXT: 4 },
    MutationObserver: class { observe() { } disconnect() { } },
    module: { exports: {} },
    __counters: counters || null,
  };
  ctx.window = ctx;
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  // Instrument INSIDE the vm realm: the plugin's strings and objects use this
  // realm's String.prototype/Object, so a host-side patch would never see them.
  let prelude = '';
  if (counters) {
    prelude = `
      (function(){
        const c = __counters;
        const oi = String.prototype.includes;
        String.prototype.includes = function(...a){ c.includes++; return oi.apply(this, a); };
        const oe = Object.entries;
        Object.entries = function(...a){ c.entries++; return oe.apply(this, a); };
      })();
    `;
  }
  vm.runInContext(prelude + fs.readFileSync(PLUGIN, 'utf8') + '\nthis.__G = module.exports;', ctx);
  return ctx.__G;
}

console.log('--- PERF-005: mapped fixtures resolve identically ---');
{
  const GoodEmoji = loadPlugin();
  const inst = new GoodEmoji();
  inst.initMaps();
  const fixtures = [
    ['base', 'https://cdn.discordapp.com/emojis/1f62d.png', true],
    ['tone', 'https://cdn.discordapp.com/emojis/1f595-1f3fb.png', true],
    ['variation', 'https://cdn.discordapp.com/emojis/2716-fe0f.png', true],
    ['gender-zwj', 'https://cdn.discordapp.com/emojis/1f6ab.png', true],
  ];
  for (const [name, url, want] of fixtures) {
    check(`mapped ${name} URL resolves`, !!inst.matchSrc(url), want);
  }
  // The three legacy nonstandard delimiter shapes the old fallback accepted.
  check('legacy /code. shape resolves', !!inst.matchSrc('https://x.test/1f62d.png'), true);
  check('legacy /code- shape resolves', !!inst.matchSrc('https://x.test/1f595-1f3fb.png'), true);
  check('legacy _code. shape resolves', !!inst.matchSrc('https://x.test/a_1f62d.png'), true);
  // A genuinely unmapped code returns null.
  check('an unmapped code returns null', inst.matchSrc('https://x.test/1f9ff.png'), null);
}

console.log('\n--- PERF-005: no substring-prefix false positive ---');
{
  const GoodEmoji = loadPlugin();
  const inst = new GoodEmoji();
  inst.initMaps();
  // A known code must not match as a mere PREFIX of a longer delimited
  // identifier: /1f62daaa has 1f62d as a prefix but is its own token.
  check('a longer identifier sharing a code prefix does not match',
    inst.matchSrc('https://example.test/status/1f62daaa'), null);
  check('a bare slash-delimited code does not match',
    inst.matchSrc('https://example.test/1f62d'), null);
  check('a hex substring before an image extension does not match',
    inst.matchSrc('https://example.test/not1f62d.png'), null);
  check('a slash-delimited code in a path does not match',
    inst.matchSrc('https://example.test/attachments/1f62d'), null);
  check('a code path child does not match',
    inst.matchSrc('https://example.test/1f62d/child'), null);
  check('a plain container id is not matched', inst.matchSrc('https://cdn.discordapp.com/attachments/123456789012345678/234567890123456789/file.png'), null);
}

console.log('\n--- PERF-005: unmatched cost is O(1) per URL and table-size independent ---');
{
  const counters = { includes: 0, entries: 0 };
  const GoodEmoji = loadPlugin(counters);
  const inst = new GoodEmoji();
  inst.initMaps();
  const origEntries = Object.keys(inst.codeToItem).length;
  check('codeToItem is populated', origEntries > 0, true);

  const urls = [];
  for (let i = 0; i < 1000; i++) urls.push('https://cdn.discordapp.com/emojis/1f9' + (i % 10) + '' + (i % 10) + 'f.png');
  counters.includes = 0; counters.entries = 0;
  for (const u of urls) inst.matchSrc(u);
  const inclPer = counters.includes / 1000;
  const entriesPer = counters.entries / 1000;

  // Multiply the table by 10 and repeat.
  for (let i = 0; i < origEntries * 9; i++) inst.codeToItem['zz' + i.toString(16)] = inst.codeToItem[Object.keys(inst.codeToItem)[0]];
  const big = Object.keys(inst.codeToItem).length;
  counters.includes = 0; counters.entries = 0;
  for (const u of urls) inst.matchSrc(u);
  const inclPerBig = counters.includes / 1000;
  const entriesPerBig = counters.entries / 1000;

  check('unmatched: zero Object.entries allocations per image (was 1)', entriesPer, 0);
  check('unmatched: zero includes per image (was 2880)', inclPer, 0);
  check('table was multiplied ~10x', big >= origEntries * 9, true);
  check('unmatched cost does NOT grow with the mapping table (includes)', inclPerBig <= inclPer, true);
  check('unmatched cost does NOT grow with the mapping table (entries)', entriesPerBig <= entriesPer, true);
}

console.log('\n' + (bad === 0 ? 'ALL PASS' : bad + ' FAIL'));
process.exit(bad === 0 ? 0 : 1);
