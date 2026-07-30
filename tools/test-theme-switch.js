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

function run({ gm, stored, isTop }) {
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
    IS_TOP: true, console,
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

console.log(bad ? '\n' + bad + ' failure(s)' : '\ntheme-switch test PASS');
process.exit(bad ? 1 : 0);
