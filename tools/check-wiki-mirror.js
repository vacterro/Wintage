#!/usr/bin/env node
// Guards the repo wiki/ mirror against silent drift from the saiwiki kitchen.
//
// The repo keeps a mirror of the maintained wiki at wiki/*.md, copied from
// .saipen/extensions/subs/saiwiki/kitchen/wiki/ when a saiwiki package is
// collected. The ONLY permitted difference is internal-link adaptation: the
// kitchen pages are written for the GitHub wiki (bare page links, `](Desktop)`),
// while the repo mirror renders on the main site and needs `.md` on those same
// links (`](Desktop.md)`). Everything else must be byte-identical.
//
// Written after the qq run caught wiki/Installation.md still carrying
// `.\install.ps1` while desktop/README.md had been fixed at T-145 — the mirror
// had drifted and nothing failed loudly. This check turns that into an instant
// FAIL: content drift, a page only on one side, or a link adapted differently
// than the .md rule allows all abort with a named page and diff.
//
// Usage: node tools/check-wiki-mirror.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');

const kitchenDir = path.join(__dirname, '..', '.saipen', 'extensions', 'subs', 'saiwiki', 'kitchen', 'wiki');
const repoDir = path.join(__dirname, '..', 'wiki');

let failures = 0;
function fail(msg) { console.error('FAIL: ' + msg); failures++; }

// A kitchen page name is the bare stem of any file in the kitchen wiki.
function pageNames() {
  return fs.readdirSync(kitchenDir)
    .filter((f) => f.endsWith('.md'))
    .map((f) => f.replace(/\.md$/, ''));
}

// Adapt a kitchen page for the repo mirror: every markdown link whose target
// names a wiki page gets `.md` appended (before any #anchor). Non-page targets
// (external URLs, the wiki's own special pages not in the set) stay untouched.
function adaptForRepo(content, pages) {
  return content.replace(/\]\(([^)]*)\)/g, (whole, target) => {
    const hash = target.indexOf('#');
    const base = hash >= 0 ? target.slice(0, hash) : target;
    if (pages.includes(base)) {
      const suffix = hash >= 0 ? target.slice(hash) : '';
      return '](' + base + '.md' + suffix + ')';
    }
    return whole;
  });
}

function readUtf8(p) { return fs.readFileSync(p, 'utf8'); }

const kitchenPages = pageNames();
const repoFiles = fs.readdirSync(repoDir).filter((f) => f.endsWith('.md'));

for (const page of kitchenPages) {
  const name = page + '.md';
  if (!fs.existsSync(path.join(repoDir, name))) {
    fail('kitchen page ' + name + ' has no repo wiki/ mirror');
    continue;
  }
  const kitchenSrc = readUtf8(path.join(kitchenDir, name));
  const repoSrc = readUtf8(path.join(repoDir, name));
  const adapted = adaptForRepo(kitchenSrc, kitchenPages);
  if (adapted !== repoSrc) {
    fail('repo wiki/' + name + ' drifted from kitchen (only .md link adaptation allowed)');
    const a = adapted.split('\n');
    const b = repoSrc.split('\n');
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      if (a[i] !== b[i]) {
        console.error('  first diff line ' + (i + 1) + ':\n    kitchen: ' + JSON.stringify(a[i]) + '\n    mirror:  ' + JSON.stringify(b[i]));
        break;
      }
    }
  }
}

for (const name of repoFiles) {
  if (!kitchenPages.includes(name.replace(/\.md$/, ''))) {
    fail('repo wiki/' + name + ' has no kitchen source (orphan mirror page)');
  }
}

if (failures) {
  console.error('Wiki mirror is out of date with the saiwiki kitchen - re-run prepare saiwiki (qq) and collect, then rerun');
  process.exit(1);
}
console.log('PASS: repo wiki/ mirror matches the saiwiki kitchen (only .md link adaptation)');
