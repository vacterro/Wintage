#!/usr/bin/env node
'use strict';
// T-283 / SRC-026 -- focused terminal-fonts suite (catalog, preference,
// capability, private preview, Windows Terminal helper, conhost guard).
//
// Runs with plain node + child processes; no test framework. Exit 1 on any fail.
// RED control: pass --red-control to inject one source mutation per group and
// prove the corresponding assertion goes red (the mutation MUST apply).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync, spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const RED = process.argv.includes('--red-control');

let pass = 0; let fail = 0;
function check(label, ok) {
  if (ok) { console.log(`PASS: ${label}`); pass++; } else { console.log(`FAIL: ${label}`); fail++; }
}
function tmpDir(tag) {
  const d = path.join(os.tmpdir(), `wintage-tf-${tag}-${process.pid}-${Date.now()}`);
  fs.mkdirSync(d, { recursive: true });
  return d;
}

// ---------------------------------------------------------------------------
// A. CATALOG
// ---------------------------------------------------------------------------
const { readCatalog, installedFamilies, familyInstalled, fontFile } = require('./terminal-font-catalog');
const catalog = readCatalog();

check('catalog carries exactly 20 bundled families', catalog.fonts.filter((f) => f.bundled).length === 20);
check('catalog has a non-empty preview sample', Array.isArray(catalog.previewSample) && catalog.previewSample.length >= 10);

const slugs = catalog.fonts.map((f) => f.slug);
check('every catalog slug is unique', new Set(slugs).size === slugs.length);
const paths = catalog.fonts.filter((f) => f.bundled).map((f) => f.file);
check('every bundled local path is unique', new Set(paths).size === paths.length);

const SUPPORTED = ['.ttf', '.otf', '.ttc'];
let filesOk = true; let licenseOk = true; let metaOk = true; let hashOk = true; let formatOk = true;
const crypto = require('crypto');
for (const f of catalog.fonts.filter((x) => x.bundled)) {
  const abs = fontFile(f);
  if (!abs || !fs.existsSync(abs)) { filesOk = false; console.log(`  missing file: ${f.slug} -> ${f.file}`); continue; }
  const licenseAbs = path.join(ROOT, 'fonts', 'terminal', (f.licenseFile || '').replace(/\//g, path.sep));
  if (!f.licenseFile || !fs.existsSync(licenseAbs)) { licenseOk = false; console.log(`  missing license: ${f.slug}`); }
  if (!f.family || !f.source || !f.version || !f.license || !f.sha256) { metaOk = false; console.log(`  incomplete metadata: ${f.slug}`); }
  if (!SUPPORTED.includes(path.extname(abs).toLowerCase())) { formatOk = false; console.log(`  unsupported format: ${f.slug}`); }
  const actual = crypto.createHash('sha256').update(fs.readFileSync(abs)).digest('hex');
  if (actual !== f.sha256) { hashOk = false; console.log(`  sha256 mismatch: ${f.slug} expected ${f.sha256} got ${actual}`); }
}
check('every bundled font file exists', filesOk);
check('every bundled license file exists', licenseOk);
check('every entry carries source/version/license/sha256/family', metaOk);
check('every bundled file sha256 matches the catalog', hashOk);
check('every bundled file is a supported font format', formatOk);

check('no bundled asset is executable content', catalog.fonts.filter((f) => f.bundled).every((f) => SUPPORTED.includes(path.extname(f.file).toLowerCase())));

// sources.json <-> catalog consistency
const sources = JSON.parse(fs.readFileSync(path.join(ROOT, 'fonts', 'terminal', 'sources.json'), 'utf8'));
check('sources.json pins 20 families', sources.fonts.length === 20);
let pinOk = true;
for (const s of sources.fonts) {
  const cat = catalog.fonts.find((f) => f.slug === s.slug);
  const expected = s.sha256_out || s.sha256_file;
  if (!s.url || !expected || !cat || cat.sha256 !== expected) { pinOk = false; console.log(`  unpinned/mismatch: ${s.slug}`); }
}
check('every source is pinned with a url + matching hash', pinOk);

// ---------------------------------------------------------------------------
// B. PREFERENCE
// ---------------------------------------------------------------------------
const pref = require('./terminal-font-preference');
// The override IS the Wintage data dir (matching WINTAGE_APPDATA in install.ps1).
const home = tmpDir('home');

const def = pref.readPreference(home);
check('missing preference -> backward-compatible default', def.source === 'default' && def.family === 'Terminus (TTF) for Windows' && def.size === 12);

const written = pref.writePreference({ schema: 1, fontSlug: 'jetbrains-mono', family: 'JetBrains Mono', size: 14, renderingMode: 'grayscale' }, home);
check('valid preference round-trips', written.family === 'JetBrains Mono');
const reread = pref.readPreference(home);
check('written preference reads back with the same values', reread.family === 'JetBrains Mono' && reread.size === 14 && reread.renderingMode === 'grayscale' && reread.source === 'file');

// malformed fails closed
const badHome = tmpDir('bad');
fs.writeFileSync(path.join(badHome, 'terminal-font.json'), '{ "schema": 1, "family": "" }');
let threw = null;
try { pref.readPreference(badHome); } catch (e) { threw = e; }
check('malformed preference fails closed (throws, never a silent default)', !!threw && threw.code === 'PREFERENCE_MALFORMED');
check('a failed read leaves the malformed file untouched', fs.readFileSync(path.join(badHome, 'terminal-font.json'), 'utf8').includes('"family": ""'));

// invalid write refused
let writeThrew = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 99, renderingMode: 'aliased' }, home); } catch (e) { writeThrew = e; }
check('write refuses an out-of-range size', !!writeThrew && writeThrew.code === 'PREFERENCE_INVALID');

// Node: fractional sizes must be rejected (integer schema 7..24)
let fracThrew = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 12.5, renderingMode: 'aliased' }, home); } catch (e) { fracThrew = e; }
check('Node rejects fractional size 12.5', !!fracThrew && fracThrew.code === 'PREFERENCE_INVALID');
let fracThrew2 = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 7.5, renderingMode: 'aliased' }, home); } catch (e) { fracThrew2 = e; }
check('Node rejects fractional size 7.5', !!fracThrew2 && fracThrew2.code === 'PREFERENCE_INVALID');
let fracThrew3 = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 24.1, renderingMode: 'aliased' }, home); } catch (e) { fracThrew3 = e; }
check('Node rejects fractional size 24.1', !!fracThrew3 && fracThrew3.code === 'PREFERENCE_INVALID');
// Node accepts integer boundaries
let int7Ok = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 7, renderingMode: 'aliased' }, badHome); } catch (e) { int7Ok = e; }
check('Node accepts integer size 7 (lower bound)', !int7Ok);
let int24Ok = null;
try { pref.writePreference({ schema: 1, fontSlug: 'x', family: 'X', size: 24, renderingMode: 'aliased' }, badHome); } catch (e) { int24Ok = e; }
check('Node accepts integer size 24 (upper bound)', !int24Ok);

// atomicity: no partial/temp file left behind
const dirListing = fs.readdirSync(home);
check('no temp file survives an atomic write', !dirListing.some((n) => n.includes('.tmp-')));

// CLI round-trip through the canonical process entry (WINTAGE_APPDATA seam)
const cliRead = execFileSync('node', [path.join(__dirname, 'terminal-font-preference.js'), 'read'], { encoding: 'utf8', env: { ...process.env, WINTAGE_APPDATA: home } }).trim();
check('CLI read returns the canonical JSON', JSON.parse(cliRead).family === 'JetBrains Mono');
const cliPath = execFileSync('node', [path.join(__dirname, 'terminal-font-preference.js'), 'path'], { encoding: 'utf8', env: { ...process.env, WINTAGE_APPDATA: home } }).trim();
check('CLI path points at the Wintage data dir', cliPath === path.join(home, 'terminal-font.json'));

// CORE-006: write --file override writes ONLY the explicit file, not the app-data preference.
const appDataRoot = tmpDir('appdata');
const explicitRoot = tmpDir('explicit');
const explicitFile = path.join(explicitRoot, 'explicit.json');
const envWithOverride = { ...process.env, WINTAGE_APPDATA: appDataRoot };
const writeOut = execFileSync('node', [path.join(__dirname, 'terminal-font-preference.js'), 'write', '--slug', 'terminus-ttf', '--family', 'Terminus (TTF) for Windows', '--size', '12', '--mode', 'aliased', '--file', explicitFile], { encoding: 'utf8', env: envWithOverride }).trim();
const writeResult = JSON.parse(writeOut);
const appDataPref = path.join(appDataRoot, 'Wintage', 'terminal-font.json');
check('CORE-006: write --file reports the explicit file', writeResult.file === explicitFile);
check('CORE-006: only the explicit file is created', fs.existsSync(explicitFile) && !fs.existsSync(appDataPref));
check('CORE-006: app-data preference is absent', !fs.existsSync(appDataPref));
check('CORE-006: explicit file content round-trips via read --file', JSON.parse(execFileSync('node', [path.join(__dirname, 'terminal-font-preference.js'), 'read', '--file', explicitFile], { encoding: 'utf8', env: envWithOverride }).trim()).family === 'Terminus (TTF) for Windows');
// RED control: the pre-fix behavior wrote to preferencePath(appData) even with --file,
// discarding fileOverride. Restoring writePreference(..., undefined) without fileOverride
// would make writeResult.file point at appDataPref instead of explicitFile.
check('CORE-006 RED control: write --file does NOT fall back to app-data path', writeResult.file !== appDataPref);

// ---------------------------------------------------------------------------
// B2. POWERSHELL <-> NODE PARITY (the schema exists in two runtimes)
// ---------------------------------------------------------------------------
// The installer reads the preference in PowerShell (no Node dependency) while
// the GUI writes it through the Node module. Both must agree on what is valid
// and what the default is, or a document one accepts the other would reject.
const ps = process.platform === 'win32' ? 'powershell' : 'pwsh';
const parityScript = `
$ErrorActionPreference='Stop'
. '${path.join(ROOT, 'desktop', 'modules', 'json-doc.ps1').replace(/'/g, "''")}'
$cases = @(
  @{ Name='missing';  Env=$null },
  @{ Name='valid';    Doc='{"schema":1,"fontSlug":"fira-code","family":"Fira Code","size":13,"renderingMode":"grayscale"}' },
  @{ Name='badjson';  Doc='not json' },
  @{ Name='badsize';  Doc='{"schema":1,"fontSlug":"x","family":"X","size":99,"renderingMode":"aliased"}' },
  @{ Name='badmode';  Doc='{"schema":1,"fontSlug":"x","family":"X","size":12,"renderingMode":"nope"}' },
  @{ Name='badschema';Doc='{"schema":2,"fontSlug":"x","family":"X","size":12,"renderingMode":"aliased"}' },
  @{ Name='frac125';   Doc='{"schema":1,"fontSlug":"x","family":"X","size":12.5,"renderingMode":"aliased"}' },
  @{ Name='frac75';    Doc='{"schema":1,"fontSlug":"x","family":"X","size":7.5,"renderingMode":"aliased"}' },
  @{ Name='frac241';   Doc='{"schema":1,"fontSlug":"x","family":"X","size":24.1,"renderingMode":"aliased"}' },
  @{ Name='ok7';       Doc='{"schema":1,"fontSlug":"x","family":"X","size":7,"renderingMode":"aliased"}' },
  @{ Name='ok13';      Doc='{"schema":1,"fontSlug":"x","family":"X","size":13,"renderingMode":"aliased"}' },
  @{ Name='ok24';      Doc='{"schema":1,"fontSlug":"x","family":"X","size":24,"renderingMode":"aliased"}' }
)
foreach ($c in $cases) {
  $h = Join-Path ([System.IO.Path]::GetTempPath()) ('wtf-parity-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $h | Out-Null
  if ($null -ne $c.Doc) { [System.IO.File]::WriteAllText((Join-Path $h 'terminal-font.json'), $c.Doc, (New-Object System.Text.UTF8Encoding($false))) }
  $env:WINTAGE_APPDATA = $h
  try {
    $p = Get-TerminalFontPreference
    Write-Output ("CASE=" + $c.Name + ";OK=1;SRC=" + $p.source + ";FAM=" + $p.family + ";SIZE=" + $p.size + ";MODE=" + $p.renderingMode)
  } catch {
    Write-Output ("CASE=" + $c.Name + ";OK=0")
  }
  Remove-Item -Recurse -Force $h -ErrorAction SilentlyContinue
}
`;
const parityOut = execFileSync(ps, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', parityScript], { encoding: 'utf8' });
function psCase(name) {
  const line = parityOut.split(/\r?\n/).find((l) => l.startsWith(`CASE=${name};`));
  if (!line) return null;
  const out = {};
  for (const kv of line.split(';')) { const [k, v] = kv.split('='); out[k] = v; }
  return out;
}
check('parity: PS and Node agree on the missing-file default',
  psCase('missing').OK === '1' && psCase('missing').SRC === 'default' && psCase('missing').FAM === pref.DEFAULT_PREFERENCE.family);
check('parity: PS accepts a valid document the Node module writes',
  psCase('valid').OK === '1' && psCase('valid').FAM === 'Fira Code' && psCase('valid').SIZE === '13' && psCase('valid').MODE === 'grayscale');
check('parity: PS rejects bad JSON like Node', psCase('badjson').OK === '0');
check('parity: PS rejects an out-of-range size like Node', psCase('badsize').OK === '0');
check('parity: PS rejects an unknown rendering mode like Node', psCase('badmode').OK === '0');
check('parity: PS rejects a wrong schema like Node', psCase('badschema').OK === '0');
check('parity: PS rejects fractional size 12.5 like Node', psCase('frac125').OK === '0');
check('parity: PS rejects fractional size 7.5 like Node', psCase('frac75').OK === '0');
check('parity: PS rejects fractional size 24.1 like Node', psCase('frac241').OK === '0');
check('parity: PS accepts integer size 7 (lower bound)', psCase('ok7').OK === '1' && psCase('ok7').SIZE === '7');
check('parity: PS accepts integer size 13 (mid)', psCase('ok13').OK === '1' && psCase('ok13').SIZE === '13');
check('parity: PS accepts integer size 24 (upper bound)', psCase('ok24').OK === '1' && psCase('ok24').SIZE === '24');

// ---------------------------------------------------------------------------
// C. PRIVATE PREVIEW (process-local; no system registration)
// ---------------------------------------------------------------------------
const probeScript = `$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root='${ROOT.replace(/'/g, "''")}'
$cat = Get-Content (Join-Path $root 'fonts/terminal/catalog.json') -Raw | ConvertFrom-Json
$entry = $cat.fonts | Where-Object { $_.slug -eq 'jetbrains-mono' }
$path = Join-Path $root ('fonts/terminal/' + ($entry.file -replace '/','\\'))
$before = @([System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name })
$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($path)
$fam = $pfc.Families[0]
$after = @([System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name })
# the private family resolves
Write-Output ("RESOLVED=" + $fam.Name)
# the private collection did NOT register the family globally
$globalHas = $after -contains $fam.Name
Write-Output ("GLOBAL_AFTER=" + $globalHas)
$f = New-Object System.Drawing.Font($fam, 12)
$bmp = New-Object System.Drawing.Bitmap 64,32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$wi = $g.MeasureString('i',$f).Width
$wW = $g.MeasureString('W',$f).Width
$isMono = ([Math]::Abs($wi-$wW) -le 0.6)
$g.Dispose(); $bmp.Dispose(); $f.Dispose(); $pfc.Dispose()
Write-Output ("MONO=" + $isMono)
`;
const probeOut = execFileSync(ps, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', probeScript], { encoding: 'utf8' });
check('bundled uninstalled font resolves via PrivateFontCollection', /RESOLVED=JetBrains Mono/.test(probeOut));
check('private preview performs ZERO system font registration', /GLOBAL_AFTER=False/.test(probeOut));
check('private preview reports the face fixed-pitch (cell width check)', /MONO=True/.test(probeOut));

// ---------------------------------------------------------------------------
// D. WINDOWS TERMINAL HELPER
// ---------------------------------------------------------------------------
const wt = tmpDir('wt');
const wtSettings = path.join(wt, 'settings.json');
fs.writeFileSync(wtSettings, JSON.stringify({ profiles: { defaults: { colorScheme: 'UserOwn', font: { face: 'Consolas', size: 10, weight: 'bold', cellWidth: '1.2' } } }, unrelated: { keep: true } }, null, 4));
const palette = path.join(ROOT, 'themes', 'goldendefault.json');

// explicit overrides: no preference file involved
const runApply = (extra) => execFileSync('node', [path.join(__dirname, 'install-terminal.js'), '--settings', wtSettings, '--palette', palette, ...extra], { encoding: 'utf8' });
runApply(['--face', 'JetBrains Mono', '--font-size', '15', '--rendering', 'grayscale']);
const applied = JSON.parse(fs.readFileSync(wtSettings, 'utf8'));
check('WT apply writes the selected installed family', applied.profiles.defaults.font.face === 'JetBrains Mono');
check('WT apply writes the selected size', applied.profiles.defaults.font.size === 15);
check('WT apply maps the rendering mode to antialiasingMode', applied.profiles.defaults.antialiasingMode === 'grayscale');
check('WT apply preserves unrelated settings', applied.unrelated && applied.unrelated.keep === true);
check('WT apply preserves the non-owned font key (cellWidth)', applied.profiles.defaults.font.cellWidth === '1.2');

// revert restores exact pre-Wintage owned values
execFileSync('node', [path.join(__dirname, 'install-terminal.js'), '--settings', wtSettings, '--revert'], { encoding: 'utf8' });
const reverted = JSON.parse(fs.readFileSync(wtSettings, 'utf8'));
check('WT revert restores the original colorScheme', reverted.profiles.defaults.colorScheme === 'UserOwn');
check('WT revert restores the original font face/size/weight', reverted.profiles.defaults.font.face === 'Consolas' && reverted.profiles.defaults.font.size === 10 && reverted.profiles.defaults.font.weight === 'bold');
check('WT revert keeps the non-owned cellWidth', reverted.profiles.defaults.font.cellWidth === '1.2');

// malformed preference fails closed with ZERO mutation
const wt2 = tmpDir('wt2');
const wt2Settings = path.join(wt2, 'settings.json');
fs.writeFileSync(wt2Settings, '{"profiles":{"defaults":{}}}');
const badPrefHome = tmpDir('badpref');
fs.writeFileSync(path.join(badPrefHome, 'terminal-font.json'), 'not json');
const beforeBad = fs.readFileSync(wt2Settings, 'utf8');
const r = spawnSync('node', [path.join(__dirname, 'install-terminal.js'), '--settings', wt2Settings, '--palette', palette], { encoding: 'utf8', env: { ...process.env, WINTAGE_APPDATA: badPrefHome } });
check('WT apply refuses a malformed preference (nonzero, zero mutation)', r.status !== 0 && fs.readFileSync(wt2Settings, 'utf8') === beforeBad);

// ---------------------------------------------------------------------------
// E. CONHOST GUARD (static + source presence)
// ---------------------------------------------------------------------------
const targetsSrc = fs.readFileSync(path.join(ROOT, 'desktop', 'modules', 'targets.ps1'), 'utf8');
check('conhost apply resolves the face from the canonical preference', /Get-ConhostOwnedFont/.test(targetsSrc));
check('conhost refuses an unusable selected face before mutation', /Test-ConhostFaceUsable/.test(targetsSrc) && /refusing to apply/.test(targetsSrc));
check('conhost health validates the configured face against the preference', /conhost FaceName is/.test(targetsSrc));
check('conhost no longer hard-codes the face into the owned value set', !/FaceName\s*=\s*@\{\s*Value\s*=\s*\$CONSOLE_FONT/.test(targetsSrc));

// ---------------------------------------------------------------------------
// F. GUI TAB (static structure)
// ---------------------------------------------------------------------------
const guiSrc = fs.readFileSync(path.join(ROOT, 'desktop', 'WintageInstaller.ps1'), 'utf8');
check('GUI defines the third tab button', /btnTabFonts/.test(guiSrc));
check('GUI tab strip is data-driven (tabTable)', /script:tabTable/.test(guiSrc));
check('GUI sets exactly one panel visible per tab', /row\.Panel\.Visible\s*=\s*\(\$row\.Key -eq \$tab\)/.test(guiSrc));
check('GUI preview disposes private fonts on close', /Clear-TfPreviewResources/.test(guiSrc));
check('GUI private-font module is dot-sourced', /modules\/terminal-fonts\.ps1/.test(guiSrc));
check('GUI button enablement follows capability', /Set-TfControlsEnabled/.test(guiSrc));
check('GUI exposes a visible Refresh control on the terminal-fonts tab', /btnTfRefresh/.test(guiSrc) && /\(T 'TfRefresh'/.test(guiSrc));
check('GUI Install instruction references a visible Refresh control', /confirm Install in the Windows dialog, then press Refresh/.test(guiSrc) && /btnTfRefresh/.test(guiSrc));

// ---------------------------------------------------------------------------
// G. DEFECT 1 -- conhost state label is NOT inverted (static proof)
// ---------------------------------------------------------------------------
{
  const t = guiSrc;
  const hasReadyFirst = /\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*'READY'/.test(t);
  const hasInverted = /\$conState\s*=\s*if\s*\(\$cap\.Conhost\)\s*\{\s*'UNSUP/.test(t);
  check('conhost state: Conhost==true renders READY (not UNSUPPORTED)', hasReadyFirst);
  check('conhost state: inverted shape is NOT present', !hasInverted);
}

// ---------------------------------------------------------------------------
// H. DEFECT 2 -- persisted family is restored into GUI selection
// ---------------------------------------------------------------------------
{
  check('Initialize-TfTab delegates to Select-TfPreferenceRow (slug-based)', /Select-TfPreferenceRow/.test(guiSrc));
  check('GUI does NOT blindly select row 0 as preference on init (has Select-TfPreferenceRow)', /Select-TfPreferenceRow/.test(guiSrc) && /\$script:TfPreferenceResolved/.test(guiSrc));
  check('Load-TfPreferenceIntoUi does not silently fall through to row 0', /Select-TfPreferenceRow/.test(guiSrc) && /not in the catalog/.test(guiSrc));
  check('unresolved slug leaves Apply disabled (TfPreferenceResolved gates ApplyConhost)', /\$script:TfPreferenceResolved/.test(guiSrc) && /\$btnTfApplyConhost/.test(guiSrc) && /TfPreferenceResolved/.test(guiSrc));
}

// ---------------------------------------------------------------------------
// I. DEFECT 3 -- real conhost Apply proves fixed-pitch before mutation
// ---------------------------------------------------------------------------
{
  const s = targetsSrc;
  check('conhost guard calls a dedicated fixed-pitch probe', /Test-ConhostFaceFixedPitch/.test(s) || /Test-ConhostFaceFixedPitch/.test(fs.readFileSync(path.join(ROOT, 'desktop', 'modules', 'terminal-fonts.ps1'), 'utf8')));
  check('Test-ConhostFaceUsable refuses a non-fixed-pitch face before mutation', /not fixed-pitch/.test(s));
  check('fixed-pitch probe measures several glyphs (not one pair)', /'i'.*'W'.*'M'.*'0'.*'1'/.test(s));
  check('fixed-pitch probe uses a bounded tolerance', /-le\s*0\.6/.test(s));
  check('fixed-pitch probe is behavioural (GDI MeasureString, not an allowlist)', /MeasureString/.test(s) && !/AllowList|allowlist.*catalog|knownSafe/.test(s.split('Test-ConhostFaceUsable')[0] || ''));
}

// ---------------------------------------------------------------------------
// J. DEFECT 4 -- Refresh preserves slug+filter, no row0 reset
// ---------------------------------------------------------------------------
{
  check('Refresh clears the installed-family probe cache', /\$script:TfInstalledNames\s*=\s*\$null/.test(guiSrc));
  check('Refresh preserves the selected slug (not SelectedIndex 0)', /Select-TfPreferenceRow\s*\$prevSlug/.test(guiSrc) || /\$prevSlug/.test(guiSrc));
  check('Refresh preserves search text', /\$txtTfSearch\.Text/.test(guiSrc) && /Apply-TfFilter\s*\$searchText/.test(guiSrc));
  check('Refresh does NOT blindly reset selection to row 0', !/if\s*\(\$lstTfFonts\.SelectedIndex\s*-lt\s*0.*SelectedIndex\s*=\s*0\s*\}\s*\r?\n\s*Update-TfSelection\s*\r?\n\s*Say-TfLog\s*'font state re-probed'/ .test(guiSrc) && /Select-TfPreferenceRow/.test(guiSrc));
}

// ---------------------------------------------------------------------------
// K. DEFECT 5 -- Restore Default cannot desync under a search filter
// ---------------------------------------------------------------------------
{
  check('Restore Default clears the search filter so the default row is visible', /\$txtTfSearch\.Text\s*=\s*''/.test(guiSrc) || /clear the search filter/i.test(guiSrc));
  check('Restore Default selects by stable slug (terminus-ttf), not substring label', /Select-TfPreferenceRow\s*\$slug/.test(guiSrc) && !/\$lstTfFonts\.Items\[.*\]\s*-like\s*"\*/.test(guiSrc.slice(guiSrc.indexOf('TfRestore') || 0)));
}

// ---------------------------------------------------------------------------
// L. DEFECT G -- selection identity is stable across capability-label changes
// ---------------------------------------------------------------------------
{
  check('selection is resolved by slug via visible-row mapping (not Format-TfRow label equality)', /TfVisibleRows/.test(guiSrc));
  check('filter rebuilds from the catalog cache into a stable visible mapping', /TfVisibleRows\s*=\s*@\(\)/.test(guiSrc) && /Apply-TfFilter/.test(guiSrc));
}

// ---------------------------------------------------------------------------
// RED CONTROL -- prove the guards are load-bearing
// ---------------------------------------------------------------------------
if (RED) {
  console.log('\n-- red control --');
  // R1: mutate the catalog hash for one family -> hash check must go red.
  const catPath = path.join(ROOT, 'fonts', 'terminal', 'catalog.json');
  const saved = fs.readFileSync(catPath, 'utf8');
  try {
    const doc = JSON.parse(saved);
    doc.fonts[0].sha256 = 'a'.repeat(64);
    fs.writeFileSync(catPath, JSON.stringify(doc, null, 2));
    let red = false;
    try {
      delete require.cache[require.resolve('./terminal-font-catalog')];
      delete require.cache[require.resolve('./terminal-font-preference')];
      const c2 = require('./terminal-font-catalog').readCatalog();
      for (const f of c2.fonts.filter((x) => x.bundled)) {
        const abs = require('./terminal-font-catalog').fontFile(f);
        const actual = crypto.createHash('sha256').update(fs.readFileSync(abs)).digest('hex');
        if (actual !== f.sha256) { red = true; break; }
      }
    } catch (e) { red = true; }
    check('RED: a corrupted catalog hash is detected', red);
  } finally { fs.writeFileSync(catPath, saved); }

  // R2: mutate the conhost guard so the face is hard-coded -> static guard red.
  const tgtPath = path.join(ROOT, 'desktop', 'modules', 'targets.ps1');
  const savedT = fs.readFileSync(tgtPath, 'utf8');
  try {
    const mutated = savedT.replace(/Get-ConhostOwnedFont/g, 'CONSOLE_FONT_HARDCODED');
    fs.writeFileSync(tgtPath, mutated);
    const after = fs.readFileSync(tgtPath, 'utf8');
    check('RED: removing the preference resolution is detected', !/Get-ConhostOwnedFont/.test(after));
  } finally { fs.writeFileSync(tgtPath, savedT); }

  // R3: mutate the tab table single-visible rule -> static guard red.
  const guiPath = path.join(ROOT, 'desktop', 'WintageInstaller.ps1');
  const savedG = fs.readFileSync(guiPath, 'utf8');
  try {
    const mutated = savedG.replace('$row.Panel.Visible = ($row.Key -eq $tab)', '$row.Panel.Visible = $true');
    fs.writeFileSync(guiPath, mutated);
    const after = fs.readFileSync(guiPath, 'utf8');
    check('RED: breaking single-visible-tab is detected', !/row\.Panel\.Visible\s*=\s*\(\$row\.Key -eq \$tab\)/.test(after));
  } finally { fs.writeFileSync(guiPath, savedG); }
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail ? 1 : 0);
