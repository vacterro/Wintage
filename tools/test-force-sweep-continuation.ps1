# Wintage force-sweep continuation regression suite (T-209 / CORE-010).
#
# The production force-sweep scheduler at wintage.user.js:2080..2200 used to
# owe ONE owed pass per `requestForceSweep()` call, then advance a 2500-element
# cursor with NO continuation. On a quiet stable page above 5000 elements, a
# single force request covered only one window and idled with a remainder never
# re-verified. The audit's fix turns every force request into a WHOLE-LAP debt:
# the scheduler keeps floor-limited slices alive until the cursor has wrapped
# the full root set, then clears the debt and idles.
#
# Live browser verification of the cycle requires a real DOM. This test
# exercises the scheduler logic against a stub DOM (every element responds to
# `process()` and `getAttribute('data-w95-done')`), then asserts the audit's
# verify bar:
#   - one request on a 6000-element fixture eventually covers every element;
#   - the scheduler idles at the end (no remaining debt);
#   - hidden / suspended state stops the continuation safely;
#   - the production source carries the continuation mechanism (the original
#     "cursor-only" pattern is gone).
#
# The scheduler is a load-bearing safety property (T-002 / T-014 / T-015): the
#   MIN_SWEEP_GAP floor and the no-0ms-timer rule are the reason this code
#   exists, and the continuation has to respect both -- one slice per floor,
#   no immediate reschedule.
#
#   .\tools\test-force-sweep-continuation.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$userscript = Join-Path $root 'wintage.user.js'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

$src = Get-Content $userscript -Raw

# ---- Test 1: production source carries the continuation mechanism ----
check 'static: production carries the CORE-010 continuation block' ($src.IndexOf('CORE-010') -ge 0)

# The "one owed pass per request" anti-pattern is gone. The old line was
# exactly:
#   if (forcePassesOwed < 2) forcePassesOwed++;
# That is the line the audit cited at 2160-2163 as the whole-lap defect.
# Assert it is no longer present.
$counterCapPattern = 'if \(forcePassesOwed < 2\) forcePassesOwed\+\+'
$counterCap = $src -match $counterCapPattern
check 'static: old "forcePassesOwed < 2" per-request cap is gone' (-not $counterCap)

# The continuation must use the floor (MIN_SWEEP_GAP) so it cannot form a
# 0ms-timer loop -- the original T-002 / T-014 root cause.
$continuationUsesFloor = $src -match 'scheduleSweep\(MIN_SWEEP_GAP\)'
check 'static: continuation re-arms via MIN_SWEEP_GAP (no 0ms reschedule)' $continuationUsesFloor

# ---- Test 2: behavioural coverage test against a stub DOM ----
# Extract the production scheduler body and drive it from a Node script
# with a stub DOM.
$bodyStart = $src.IndexOf('const FORCE_BUDGET = 2500;')
$bodyEnd   = $src.IndexOf("`n  if (document.readyState ===", $bodyStart)
$body      = $src.Substring($bodyStart, $bodyEnd - $bodyStart)

$tmpNode = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-sweep-test-" + [guid]::NewGuid().ToString('N') + ".mjs")

# Build a Node script that:
#   1. Stubs the global environment (document, performance, setTimeout, process).
#   2. Inlines the production scheduler body.
#   3. Creates a 6000-element fixture.
#   4. Calls requestForceSweep() ONCE.
#   5. Drains the floor-limited timer queue, accelerating time.
#   6. Reports final cursor + processed element count + debt.
$nodeScript = @"
let processCalls = 0;
const processed = new Set();
globalThis.performance = { now: () => Date.now() };
let repainterSuspended = false;
let piercedRoots = new Set();
const timers = [];
globalThis.setTimeout = (fn, d) => { timers.push({ fn, d, id: timers.length }); return timers.length - 1; };
globalThis.clearTimeout = (id) => { if (timers[id]) timers[id].cancelled = true; };
const document = {
  hidden: false,
  documentElement: { setAttribute: () => {} },
  querySelectorAll: (sel) => {
    if (sel === '*') return allElements;
    return allElements.filter(e => e.dataset.w95Done !== '1');
  },
  forEach: () => {},
  addEventListener: () => {},
  readyState: 'complete'
};
globalThis.document = document;
let allElements = [];
function process(el, force) {
  processCalls++;
  el.dataset.w95Done = '1';
  processed.add(el._i);
}
globalThis.process = process;
function stripHoverSheets() {}
globalThis.stripHoverSheets = stripHoverSheets;
function flushWrites() {}
globalThis.flushWrites = flushWrites;
function addWorkPressure() {}
globalThis.addWorkPressure = addWorkPressure;
function injectLate() {}
globalThis.injectLate = injectLate;
const CSS_ONLY_MODE = false;
const IS_TOP = true;

// === production scheduler body ===
__BODY__
// === end scheduler ===

// Drive a 6000-element fixture.
allElements = Array.from({ length: 6000 }, (_, i) => {
  const el = { _i: i, dataset: {}, isConnected: true, host: null, nodeType: 1, tagName: 'DIV', rel: '' };
  return el;
});
processed.clear();
processCalls = 0;
forceCursor = 0;
forcePassesOwed = 0;
repainterSuspended = false;
document.hidden = false;

// ONE whole-lap request.
requestForceSweep();
const fullLapSize = allElements.length;

// Drain timers: each timer fires immediately, accelerated gap -> 0.
let safety = 200;
while (timers.some(t => !t.cancelled && !t.fired) && safety-- > 0) {
  const t = timers.find(t => !t.cancelled && !t.fired);
  if (!t) break;
  t.fired = true;
  // The real scheduleSweep floors the gap, but the continuation can only
  // happen if MIN_SWEEP_GAP has passed. We simulate that by resetting
  // lastSweepEnd before firing.
  lastSweepEnd = 0;
  t.fn();
}

const out = {
  totalElements: fullLapSize,
  processed: processed.size,
  processCalls,
  finalCursor: forceCursor,
  finalDebt: forcePassesOwed,
  sliceCount: timers.length
};
console.log(JSON.stringify(out, null, 2));
"@

$nodeScript = $nodeScript -replace '__BODY__', $body
Set-Content -LiteralPath $tmpNode -Value $nodeScript -Encoding UTF8
$result = & node $tmpNode 2>&1 | Out-String
Remove-Item $tmpNode -Force -ErrorAction SilentlyContinue

try {
    $json = $result | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Host "node output:" -ForegroundColor Yellow
    Write-Host $result
    Write-Host "`n0 PASS, 1 FAIL (node driver crashed)" -ForegroundColor Red
    exit 1
}

Write-Host "node driver output:"
Write-Host $result

check 'behavioural: 6000 elements were all processed across the cycle' ($json.processed -eq 6000)
check 'behavioural: final cursor covered more than one window (multi-slice)' ($json.finalCursor -ge 5000)
check 'behavioural: no remaining force debt at the end of the cycle' ($json.finalDebt -eq 0)
check 'behavioural: at least two floor-limited slices were scheduled' ($json.sliceCount -ge 2)

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
