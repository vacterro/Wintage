#!/usr/bin/env python3
"""saitranslate: independent verification of the desktop README delta (fresh disk read)."""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KITCHEN = os.path.join(os.path.dirname(HERE), 'kitchen', 'desktop')
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
SRC = os.path.join(ROOT, 'desktop', 'README.md')
PUB = os.path.join(ROOT, 'desktop')
MY = ['ar', 'bg', 'cs', 'da', 'de', 'el', 'es', 'fi', 'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it',
      'ja', 'ko', 'nl', 'no', 'pl', 'pt', 'ro', 'sk', 'sv', 'th', 'tr', 'uk', 'vi', 'zh']

def facts(p):
    t = open(p, encoding='utf-8', newline='').read()
    return dict(
        heads=re.findall(r'^#{1,6} .*$', t, re.M),
        levels=[len(m.group(1)) for m in re.finditer(r'^(#{1,6}) ', t, re.M)],
        rows=[l for l in t.split('\n') if l.startswith('|')],
        # language-independent: the backticked target names in the first cell, row by row
        first=['|'.join(sorted(re.findall(r'`([^`]+)`', l.strip().strip('|').split('|')[0])))
               for l in t.split('\n') if l.startswith('|')],
        fences=len(re.findall(r'^```', t, re.M)),
        links=re.findall(r'\[[^\]]*\]\([^)]*\)', t),
        code=re.findall(r'`[^`\n]+`', t),
        digest=re.findall(r'<!-- source-digest: desktop/README\.md sha256:([0-9a-f]+) -->', t),
        qblocks=len(re.findall(r'^### qBittorrent$', t, re.M)),
    )

src = facts(SRC)
fails, checks = [], 0
def ck(c, m):
    global checks
    checks += 1
    if not c:
        fails.append(m)

rows = []
for code in MY:
    p = os.path.join(KITCHEN, 'README.%s.md' % code)
    f = facts(p)
    ck(f['levels'] == src['levels'], '%s: heading level sequence differs' % code)
    ck(len(f['rows']) == len(src['rows']), '%s: %d table rows (want %d)' % (code, len(f['rows']), len(src['rows'])))
    ck(f['first'] == src['first'], '%s: table target order differs' % code)
    ck(f['fences'] == src['fences'], '%s: ``` count %d (want %d)' % (code, f['fences'], src['fences']))
    ck(f['digest'] == ['b77c16d423936045'], '%s: digest %s' % (code, f['digest']))
    ck(f['qblocks'] == 1, '%s: %d qBittorrent headings' % (code, f['qblocks']))
    ck('1b166ae6a7cf8a5c' not in open(p, encoding='utf-8').read(), '%s: old digest still present' % code)
    # untouched-by-this-package: the published copy's non-delta lines must still be there
    pub = open(os.path.join(PUB, 'README.%s.md' % code), encoding='utf-8', newline='').read()
    pub_line_set = set(x.rstrip('\r') for x in pub.split('\n') if x.strip())
    cur = open(p, encoding='utf-8', newline='').read()
    cur_line_set = set(x.rstrip('\r') for x in cur.split('\n') if x.strip())
    lost = [x for x in pub_line_set if x not in cur_line_set and 'source-digest' not in x]
    ck(not lost, '%s: %d published line(s) vanished, e.g. %s' % (code, len(lost), lost[:1]))
    rows.append('%-3s heads=%d rows=%d fences=%d digest=%s' % (code, len(f['heads']), len(f['rows']), f['fences'], f['digest'][0][:16]))

print('\n'.join(rows))
print()
print('source: heads=%d rows=%d fences=%d levels=%s' % (len(src['heads']), len(src['rows']), src['fences'], src['levels']))
print('checks: %d, failures: %d' % (checks, len(fails)))
for x in fails:
    print('  FAIL', x)
# Core-owned siblings, reported only
for code in ('ru', 'et', 'ded'):
    p = os.path.join(KITCHEN, 'README.%s.md' % code)
    f = facts(p)
    print('core %-3s heads=%d rows=%d digest=%s (source has %d heads, %d rows) -- Core-owned, not touched'
          % (code, len(f['heads']), len(f['rows']), f['digest'][0][:16], len(src['heads']), len(src['rows'])))
sys.exit(1 if fails else 0)
