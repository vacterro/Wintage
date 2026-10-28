'use strict';
// Exercise the real route-guard sequence and helpers against isolated state.
const fs = require('fs');
const path = require('path');
const os = require('os');
const vm = require('vm');
const cp = require('child_process');
const source = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');
function block(prefix) {
  const start = source.indexOf(prefix);
  if (start < 0) throw Error('Missing source block: ' + prefix);
  let depth = 0;
  for (let i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw Error('Unclosed source block: ' + prefix);
}
let failures = 0;
function check(label, pass) {
  console.log((pass ? 'PASS: ' : 'FAIL: ') + label);
  if (!pass) failures++;
}
function style(initial) {
  const values = { ...initial };
  const priorities = Object.fromEntries(Object.keys(initial).map(k => [k, 'important']));
  return {
    get length() { return Object.keys(values).length; },
    0: 'color',
    getPropertyValue(k) { return values[k] || ''; },
    getPropertyPriority(k) { return priorities[k] || ''; },
    setProperty(k, v, p) { values[k] = v; priorities[k] = p || ''; },
    removeProperty(k) { const old = values[k]; delete values[k]; delete priorities[k]; return old; }
  };
}

// The real guard must restore a stripped site hover rule before suspension
// releases the registry. This is the actual production cleanup statement.
{
  const clear = block('function suspendRepainter(').match(/try \{ hoverStrippedRules\.length = 0; \} catch \(e\) \{ \}/);
  if (!clear) throw Error('Cannot locate the production registry-release statement');
  const rule = { style: style({ color: 'rgb(1, 2, 3)' }) };
  const sandbox = {
    rule, HOVER_PAINT: /color/, HOVER_REGISTRY_CAP: 4096, hasWeakRef: false,
    hoverStrippedRules: [], hoverStrippedOriginals: new WeakMap(),
    isExcludedUrl: () => true, location: { href: 'https://example.com/oauth', reload() {} },
    window: {}, routeQuarantined: false
  };
  vm.runInNewContext([
    block('const hoverHandleOf = function (') + ';', block('function compactHoverRegistry('),
    block('function stripHoverRule('), block('function restoreHoverRules('),
    'function suspendRepainter() { ' + clear[0] + ' }',
    'function quarantineThemeStyles() { restoreHoverRules(); }',
    block('const guard = function () {') + ';', 'stripHoverRule(rule); guard();'
  ].join('\n'), sandbox);
  check('excluded-route guard restores real stripped hover color before releasing snapshots',
    rule.style.getPropertyValue('color') === 'rgb(1, 2, 3)');
}

// paintRoot runs before ordinary repainter bookkeeping. Its original values
// must survive quarantine even when <html> has no data-w95-done marker.
{
  const root = { style: style({ 'background-color': 'rgb(4, 5, 6)', color: 'rgb(7, 8, 9)' }),
    setAttribute() {}, removeAttribute() {} };
  const sandbox = {
    document: { documentElement: root, querySelectorAll: () => [], adoptedStyleSheets: [] },
    Element: { prototype: {} }, rootInlineOriginals: null,
    routeQuarantined: false, rootAttributeObserver: { disconnect() {} },
    ownedInlineOriginals: new WeakMap(), restoreHoverRules() {},
    T: { background: '#000', textPrimary: '#fff' }, DARK: true, THEME_ID: 'goldendefault'
  };
  vm.runInNewContext([
    block('function paintRoot('), block('function removeInjectedStyleNodes('),
    block('function dropAdoptedThemeSheets('), block('function quarantineThemeStyles('),
    'paintRoot(); quarantineThemeStyles(); quarantineThemeStyles(); paintRoot();'
  ].join('\n'), sandbox);
  check('root background restores its exact original inline value and priority',
    root.style.getPropertyValue('background-color') === 'rgb(4, 5, 6)'
    && root.style.getPropertyPriority('background-color') === 'important');
  check('root text restores its exact original inline value and priority',
    root.style.getPropertyValue('color') === 'rgb(7, 8, 9)'
    && root.style.getPropertyPriority('color') === 'important');
}

// A user can remove profiles.defaults after Apply while retaining profiles.list.
// Revert must preserve that valid document rather than throwing mid-plan.
{
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-terminal-alignment-'));
  const settings = path.join(temp, 'settings.json');
  const helper = path.join(__dirname, 'install-terminal.js');
  const env = { ...process.env, WINTAGE_APPDATA: path.join(temp, 'appdata') };
  const run = args => cp.spawnSync(process.execPath, [helper, '--settings', settings, ...args], { env, encoding: 'utf8' });
  const applied = run(['--palette', path.join(__dirname, '..', 'themes', 'goldendefault.json')]);
  check('terminal created-file fixture applies successfully', applied.status === 0);
  const current = JSON.parse(fs.readFileSync(settings, 'utf8'));
  current.profiles = { list: [{ name: 'User-added profile', commandline: 'cmd.exe' }] };
  fs.writeFileSync(settings, JSON.stringify(current));
  const reverted = run(['--revert']);
  check('terminal revert succeeds after defaults were removed independently', reverted.status === 0);
  const after = JSON.parse(fs.readFileSync(settings, 'utf8'));
  check('terminal revert keeps independently added profiles', after.profiles.list[0].name === 'User-added profile');
  fs.rmSync(temp, { recursive: true, force: true });
}
process.exit(failures ? 1 : 0);
