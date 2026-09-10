// Theme-switch regression test. Runs the REAL source slice — from the THEMES table through
// the menu block — under stubbed globals, so what is tested is the shipped text
// rather than a paraphrase of it.
const fs = require('fs'), vm = require('vm'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');

const from = src.indexOf('  const THEMES = {');
const endMark = '\n  }\n\n  // ─── UI.md TOKENS';
let to = src.indexOf('  // ─── FONT', from);
to = src.indexOf('  const W95_VERSION', from); // menu block sits before this
if (from < 0 || to < 0) { console.error('FAIL: could not slice the source'); process.exit(1); }
let slice = src.slice(from, to);

// A second theme, so "unknown slug", "valid non-default slug" and the menu are all
// testable. Injected into the source text, not into a copy of the table.
slice = slice.replace(/(\n  \};)/, `,
    testpal: {
      label: 'Test Palette',
      tokens: { background: '#101010', backgroundSoft: '#111111', surface: '#121212',
        surfaceRaised: '#131313', surfaceAlt: '#141414', borderDark: '#151515',
        borderHighlight: '#161616', borderMuted: '#171717', textPrimary: '#EEEEEE',
        textSecondary: '#DDDDDD', textMuted: '#CCCCCC', accentTeal: '#008080',
        accentTealDeep: '#004C4C', success: '#4A7A20', warning: '#7A7A20',
        danger: '#7A2020', selection: '#181818', compareBack: '#0A0A0A' }
    }$1`);

// The default palette is the user's choice, not this test's: it is read from the
// source instead of hardcoded. Pinning 'golden' here turned a deliberate change of
// DEFAULT_THEME into three red tests that said nothing about the switch logic.
const DEFAULT_THEME = (/const DEFAULT_THEME = '(\w+)'/.exec(src) || [, 'golden'])[1];
const themeBlock = src.slice(src.indexOf('\n    ' + DEFAULT_THEME + ': {'), src.indexOf('\n    ' + DEFAULT_THEME + ': {') + 900);
const DEFAULT_LABEL = /label: '([^']+)'/.exec(themeBlock)[1];
const DEFAULT_BG = /background: '(#[0-9A-Fa-f]{6})'/.exec(themeBlock)[1];

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

function run({ gm, stored, isTop, isX, isReddit, isGoogle }) {
  const painted = {}, attrs = {}, menu = [];
  let reloads = 0, wrote = null;
  const el = {
    style: { setProperty: (k, v) => { painted[k] = v; } },
    setAttribute: (k, v) => { attrs[k] = v; }
  };
  const ctx = {
    document: { documentElement: el },
    location: { reload: () => { reloads++; } },
    IS_TOP: isTop,
    IS_X: !!isX,
    IS_REDDIT: !!isReddit,
    IS_GOOGLE: !!isGoogle,
    console
  };
  if (gm) {
    ctx.GM_getValue = (k, d) => (stored === undefined ? d : stored);
    ctx.GM_setValue = (k, v) => { wrote = [k, v]; };
    ctx.GM_registerMenuCommand = (label, fn) => { menu.push([label, fn]); };
  }
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\nthis.__out = { THEME_ID, T, THEMES };\n}).call(this)', ctx);
  // reloads/wrote are read AFTER menu callbacks fire, so they must be live getters —
  // snapshotting them here returns the pre-click zero and fails a working product.
  return { out: ctx.__out, painted, attrs, menu, get reloads() { return reloads; }, get wrote() { return wrote; } };
}

// 1. no GM API at all -> default palette, nothing thrown
let r = run({ gm: false, isTop: true });
check('no GM API -> default palette', r.out.THEME_ID, DEFAULT_THEME);
check('no GM API -> paints the default background', r.painted['background-color'], DEFAULT_BG);
check('no GM API -> no menu', r.menu.length, 0);

// 2. stored slug that no longer exists -> default, not a crash
r = run({ gm: true, stored: 'deleted-pack', isTop: true });
check('unknown slug -> default palette', r.out.THEME_ID, DEFAULT_THEME);

// 3. stored valid slug -> that palette, and the FIRST paint follows it
r = run({ gm: true, stored: 'testpal', isTop: true });
check('stored slug honoured', r.out.THEME_ID, 'testpal');
check('first paint follows the theme', r.painted['background-color'], '#101010');
check('first paint text follows the theme', r.painted['color'], '#EEEEEE');
check('data-w95-theme stamped', r.attrs['data-w95-theme'], 'testpal');

// 4. menu: one entry per theme, top frame only, active one marked
r = run({ gm: true, stored: DEFAULT_THEME, isTop: true });
// Counted from the table the script actually declares, not hardcoded — a test that
// has to be edited every time a theme pack is added stops being run.
const themeCount = Object.keys(r.out.THEMES).length;
// The menu is allowed to carry entries that are not themes (there is a "Buy me a
// coffee" one). Counting r.menu.length made an unrelated menu addition look like a
// broken switch, so only the marked theme rows are counted.
const themeMenu = r.menu.filter(m => m[0].startsWith('● ') || m[0].startsWith('○ '));
check('menu entry per theme', themeMenu.length, themeCount);
// The ACTIVE entry is wherever the default palette sits in menu order, not index 0.
// Assuming index 0 only held while the default happened to be the first pack; the
// moment DEFAULT_THEME changed, four checks went red about the wrong thing.
const activeIdx = r.menu.findIndex(m => m[0].startsWith('● '));
check('exactly one entry marked active', r.menu.filter(m => m[0].startsWith('● ')).length, 1);
check('the active entry is the default palette', r.menu[activeIdx][0], '● ' + DEFAULT_LABEL);
check('every other theme entry marked inactive', themeMenu.filter(m => !m[0].startsWith('● ')).every(m => m[0].startsWith('○ ')), true);
const testEntry = r.menu.findIndex(m => m[0] === '○ Test Palette');
check('injected test palette present in the menu', testEntry >= 0, true);
const sub = run({ gm: true, stored: DEFAULT_THEME, isTop: false });
check('sub-frame registers nothing', sub.menu.length, 0);

// 5. clicking: active = no-op, other = persist + reload
r.menu[activeIdx][1]();
check('clicking the active theme does not write', r.wrote, null);
check('clicking the active theme does not reload', r.reloads, 0);
r.menu[testEntry][1]();
check('clicking another theme persists it', r.wrote, ['w95-theme', 'testpal']);
check('clicking another theme reloads', r.reloads, 1);

// 6. GM_setValue throwing must NOT reload (a reload without a stored value is an
//    infinite loop back onto the same theme)
{
  const menu = [];
  let reloads = 0;
  const ctx = {
    document: { documentElement: { style: { setProperty() { } }, setAttribute() { } } },
    location: { reload: () => { reloads++; } },
    IS_TOP: true, IS_X: false, IS_REDDIT: false, IS_GOOGLE: false, console,
    GM_getValue: (k, d) => d,
    GM_setValue: () => { throw new Error('storage quota'); },
    GM_registerMenuCommand: (l, f) => menu.push([l, f])
  };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\n}).call(this)', ctx);
  menu.find(m => m[0] === '○ Test Palette')[1]();
  check('failed write does not reload', reloads, 0);
}

// 7. the header must actually carry the grants + the sandbox mode they depend on
for (const need of ['// @grant        GM_getValue', '// @grant        GM_setValue',
  '// @grant        GM_registerMenuCommand', '// @sandbox      raw']) {
  check('header carries ' + need.trim(), src.includes(need), true);
}
check('no leftover @grant none', /@grant\s+none/.test(src), false);

// 8. host-specific data attributes — X, Reddit, ordinary hosts
r = run({ gm: true, stored: DEFAULT_THEME, isTop: true, isX: true });
check('X host -> data-w95-x', r.attrs['data-w95-x'], '1');
check('X host -> no data-w95-reddit', 'data-w95-reddit' in r.attrs, false);
r = run({ gm: true, stored: DEFAULT_THEME, isTop: true, isReddit: true });
check('Reddit host -> data-w95-reddit', r.attrs['data-w95-reddit'], '1');
check('Reddit host -> no data-w95-x', 'data-w95-x' in r.attrs, false);
r = run({ gm: true, stored: DEFAULT_THEME, isTop: true, isGoogle: true });
check('Google host -> data-w95-google', r.attrs['data-w95-google'], '1');
check('Google host -> no data-w95-x', 'data-w95-x' in r.attrs, false);
r = run({ gm: true, stored: DEFAULT_THEME, isTop: true });
check('ordinary host -> no data-w95-x', 'data-w95-x' in r.attrs, false);
check('ordinary host -> no data-w95-reddit', 'data-w95-reddit' in r.attrs, false);
check('ordinary host -> no data-w95-google', 'data-w95-google' in r.attrs, false);

// 9. CORE-014: a refused reload must not leave a silent split brain.
//    The write lands before the navigation, so a blocked reload leaves storage on
//    the NEW palette while the page keeps painting the OLD one. That state has to
//    be stated, not swallowed: warn once, and never claim the switch failed
//    (storage really did change).
{
  const menu = [];
  let reloads = 0;
  const warns = [];
  let wrote = null;
  const ctx = {
    document: { documentElement: { style: { setProperty() { } }, setAttribute() { } } },
    location: { reload: () => { reloads++; throw new Error('navigation refused'); } },
    IS_TOP: true, IS_X: false, IS_REDDIT: false, IS_GOOGLE: false,
    console: { warn: (m) => warns.push(String(m)), log: console.log, error: console.error },
    GM_getValue: (k, d) => d,
    GM_setValue: (k, v) => { wrote = [k, v]; },
    GM_registerMenuCommand: (l, f) => menu.push([l, f])
  };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\n}).call(this)', ctx);
  menu.find(m => m[0] === '○ Test Palette')[1]();
  check('refused reload: the palette was still persisted', wrote, ['w95-theme', 'testpal']);
  check('refused reload: reload was attempted', reloads, 1);
  check('refused reload: warns exactly once', warns.length, 1);
  check('refused reload: warning names the palette', /testpal/.test(warns[0] || ''), true);
  check('refused reload: warning names the manual fix', /[Rr]eload/.test(warns[0] || ''), true);
  check('refused reload: does not throw out of the callback', true, true);
}

// 10. CORE-003/CORE-014: the pending row is created by the RUNTIME event that
//     creates the split brain -- a switch that persisted while the reload was
//     refused -- and is BEHAVIOURALLY reachable. The old startup predicate
//     (STORED_THEME_ID !== THEME_ID && THEMES[STORED_THEME_ID]) could never be
//     true: a valid stored slug becomes THEME_ID one line after it is read, and
//     an invalid one fails the THEMES lookup. A recovery row that cannot appear
//     is worse than none, because it reads as covered.
{
  r = run({ gm: true, stored: 'testpal', isTop: true });
  check('healthy startup -> no pending row', r.menu.filter(m => m[0].startsWith('⟳ ')).length, 0);
}
{
  const menu = [];
  let reloads = 0;
  let refuse = true;
  const ctx = {
    document: { documentElement: { style: { setProperty() { } }, setAttribute() { } } },
    location: { reload: () => { reloads++; if (refuse) throw new Error('navigation refused'); } },
    IS_TOP: true, IS_X: false, IS_REDDIT: false, IS_GOOGLE: false,
    console: { warn() { }, log: console.log, error: console.error },
    GM_getValue: (k, d) => d,
    GM_setValue: () => { },
    GM_registerMenuCommand: (l, f) => menu.push([l, f])
  };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\n}).call(this)', ctx);
  check('before any switch -> no pending row', menu.filter(m => m[0].startsWith('⟳ ')).length, 0);
  menu.find(m => m[0] === '○ Test Palette')[1]();
  const pending = menu.filter(m => m[0].startsWith('⟳ '));
  check('refused reload registers exactly one pending row', pending.length, 1);
  check('the pending row names the palette that is waiting', pending[0][0], '⟳ Apply pending theme: Test Palette');
  // Clicking it must retry the navigation and nothing else.
  refuse = false;
  const before = reloads;
  pending[0][1]();
  check('the pending row retries the reload', reloads - before, 1);
  // A second refused switch must not stack a second row.
  refuse = true;
  menu.find(m => m[0] === '○ Test Palette')[1]();
  check('a second refusal does not stack rows', menu.filter(m => m[0].startsWith('⟳ ')).length, 1);
}
// Source pins: the constant and the recovery action must both still exist, and
// the unreachable predicate must NOT come back.
check('source declares STORED_THEME_ID', /const STORED_THEME_ID = requested;/.test(src), true);
check('the unreachable startup predicate is gone',
  /STORED_THEME_ID && STORED_THEME_ID !== THEME_ID && THEMES\[STORED_THEME_ID\]/.test(src), false);
check('pending state is runtime, not a startup constant', /let pendingThemeId = null;/.test(src), true);
check('pending row offers a reload', /Apply pending theme: '/.test(src), true);

// 11. SRC-005 CORE-001: a reload that RETURNS NORMALLY is not proof the old
//     document unloaded. A cancelled beforeunload leaves this document alive
//     with storage already on the new palette -- the split brain the throw
//     path reports, arriving through the class the catch can never see. The
//     switch arms a one-shot survival probe: pagehide disarms it, the timer
//     firing on a live document reports the pending row + warning.
{
  const menu = [];
  let reloads = 0;
  let timerFired = 0;
  const warns = [];
  const listeners = { pagehide: [], beforeunload: [] };
  const fakeTimers = [];
  const ctx = {
    document: { documentElement: { style: { setProperty() { } }, setAttribute() { } } },
    location: { reload: () => { reloads++; } },
    IS_TOP: true, IS_X: false, IS_REDDIT: false, IS_GOOGLE: false,
    console: { warn: (m) => warns.push(String(m)), log: console.log, error: console.error },
    setTimeout: (fn) => { fakeTimers.push(fn); },
    clearTimeout: () => { },
    addEventListener: (n, f) => { (listeners[n] || (listeners[n] = [])).push(f); },
    removeEventListener: () => { },
    GM_getValue: (k, d) => d,
    GM_setValue: () => { },
    GM_registerMenuCommand: (l, f) => menu.push([l, f])
  };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\n}).call(this)', ctx);
  menu.find(m => m[0] === '○ Test Palette')[1]();
  check('surviving document: reload was requested and returned', reloads, 1);
  check('surviving document: no row before the probe fires', menu.filter(m => m[0].startsWith('⟳ ')).length, 0);
  // The document is still alive when the timer fires -> exactly one row + warning.
  fakeTimers.forEach(f => f());
  timerFired = fakeTimers.length;
  check('surviving document: the probe fired once', timerFired, 1);
  const pending = menu.filter(m => m[0].startsWith('⟳ '));
  check('surviving document: one pending row after the probe', pending.length, 1);
  check('surviving document: row names the waiting palette', pending[0][0], '⟳ Apply pending theme: Test Palette');
  check('surviving document: warns exactly once', warns.length, 1);
  check('surviving document: warning names the palette', /testpal/.test(warns[0] || ''), true);
  // Retry through the row retries the reload exactly once.
  const before = reloads;
  pending[0][1]();
  check('surviving document: the row retries the reload once', reloads - before, 1);
}
// 12. the OTHER side of the probe: a real unload disarms it. pagehide before
//     the timer fires -> NO pending row, NO warning -- a document that really
//     navigated away must not be reported as stuck.
{
  const menu = [];
  const warns = [];
  const listeners = { pagehide: [], beforeunload: [] };
  const fakeTimers = [];
  const ctx = {
    document: { documentElement: { style: { setProperty() { } }, setAttribute() { } } },
    location: { reload: () => { } },
    IS_TOP: true, IS_X: false, IS_REDDIT: false, IS_GOOGLE: false,
    console: { warn: (m) => warns.push(String(m)), log: console.log, error: console.error },
    setTimeout: (fn) => { fakeTimers.push(fn); },
    clearTimeout: () => { },
    addEventListener: (n, f) => { (listeners[n] || (listeners[n] = [])).push(f); },
    removeEventListener: () => { },
    GM_getValue: (k, d) => d,
    GM_setValue: () => { },
    GM_registerMenuCommand: (l, f) => menu.push([l, f])
  };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\n}).call(this)', ctx);
  menu.find(m => m[0] === '○ Test Palette')[1]();
  // The navigation really happened: pagehide fires before the timer.
  listeners.pagehide.forEach(f => f());
  fakeTimers.forEach(f => f());
  check('real unload: no pending row', menu.filter(m => m[0].startsWith('⟳ ')).length, 0);
  check('real unload: no warning', warns.length, 0);
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\ntheme-switch test PASS');
process.exit(bad ? 1 : 0);
