#!/usr/bin/env python3
"""saitranslate: apply the desktop/README.md prose delta to the 29 locale mirrors.

Insertion is structural, never textual: the two new sections go immediately before
the locale's own "Electron apps" heading (source index 12, translation index 10),
the new table row directly after the locale's `obs` row, and the source digest is
restamped. Dry-run unless --apply.
"""
import json, os, re, sys

DRY = '--apply' not in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
KITCHEN = os.path.join(os.path.dirname(HERE), 'kitchen', 'desktop')
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
SRC = os.path.join(ROOT, 'desktop', 'README.md')
MY = ['ar', 'bg', 'cs', 'da', 'de', 'el', 'es', 'fi', 'fr', 'he', 'hi', 'hr', 'hu',
      'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt', 'ro', 'sk', 'sv', 'th', 'tr',
      'uk', 'vi', 'zh']
OLD_MARK = 'source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c'
NEW_MARK = 'source-digest: desktop/README.md sha256:b77c16d423936045'

def load(p, name):
    ns = {}
    exec(compile(open(p, encoding='utf-8').read(), p, 'exec'), ns)
    return ns[name]

DOC = {}
for part in ('a', 'b', 'c'):
    for k, v in load(os.path.join(HERE, 'docdelta-%s.py' % part), 'DOC').items():
        assert k not in DOC, k
        DOC[k] = v
ROWS = load(os.path.join(HERE, 'docdelta-row.py'), 'ROWS')
assert sorted(DOC) == sorted(MY), sorted(set(DOC) ^ set(MY))
assert sorted(ROWS) == sorted(MY), sorted(set(ROWS) ^ set(MY))
for code, d in DOC.items():
    assert len(d['q']) == 4 and len(d['f']) == 4, code
    assert d['fonts_head'].startswith('### '), code

src = open(SRC, encoding='utf-8', newline='').read()
src_heads = re.findall(r'^#{1,6} .*$', src, re.M)
src_rows = [l for l in src.split('\n') if l.startswith('|')]
src_q_first = src.split('\n### qBittorrent\n')[1].strip().split('\n')[0]
report, problems = [], []

for code in MY:
    path = os.path.join(KITCHEN, 'README.%s.md' % code)
    raw = open(path, 'rb').read().decode('utf-8')
    nl = '\r\n' if raw.count('\r\n') and raw.count('\r\n') == raw.count('\n') else '\n'
    heads = [m.start() for m in re.finditer(r'^#{1,6} .*$', raw, re.M)]
    heads_txt = re.findall(r'^#{1,6} .*$', raw, re.M)
    assert len(heads_txt) == 15, '%s: %d headings (want 15)' % (code, len(heads_txt))
    assert 'Electron' in heads_txt[10], '%s: heading 10 is %r, not the Electron anchor' % (code, heads_txt[10])
    obs = [i for i, l in enumerate(raw.split(nl)) if l.startswith('|') and '`obs`' in l]
    assert len(obs) == 1, '%s: %d obs rows' % (code, len(obs))
    row_i = obs[0]
    d = DOC[code]
    cells = [c.strip() for c in raw.split(nl)[row_i].strip().strip('|').split('|')]
    assert len(cells) == 3, '%s: obs row has %d cells' % (code, len(cells))
    assert '`config.json`' in ROWS[code] and '`stylesheet.qss`' in ROWS[code] and '`qBittorrent.ini`' in ROWS[code], code
    new_row = '| `qbittorrent` | %s | %s |' % (ROWS[code], cells[2])

    block = ['### qBittorrent', ''] + d['q'] + [''] + [d['fonts_head'], ''] + d['f'] + ['', '']
    lines = raw.split(nl)
    # locate the char offset of heading 10 in line terms
    target = heads_txt[10]
    idx = next(i for i, l in enumerate(lines) if l == target)
    lines[idx:idx] = block
    # table row after the obs row (recompute: line index shifted by len(block))
    j = next(i for i, l in enumerate(lines) if l.startswith('|') and '`obs`' in l)
    lines[j + 1:j + 1] = [new_row]
    out = nl.join(lines)
    assert OLD_MARK in out, '%s: old digest marker not found' % code
    out = out.replace(OLD_MARK, NEW_MARK)
    assert out.count(NEW_MARK) == 1 and OLD_MARK not in out

    # verification pass on the produced text
    vh = re.findall(r'^#{1,6} .*$', out, re.M)
    vr = [l for l in out.split(nl) if l.startswith('|')]
    vf = len(re.findall(r'^```', out, re.M))
    ok = (len(vh) == 17 and len(vr) == 15 and vf == 10
          and '### qBittorrent' in out and d['fonts_head'] in out
          and new_row in out and NEW_MARK in out and OLD_MARK not in out)
    if not ok:
        problems.append('%s: heads=%d rows=%d fences=%d' % (code, len(vh), len(vr), vf))
    # no English prose leaked into the insertion
    if d['q'][0] == src_q_first:
        problems.append('%s: qBittorrent paragraph is still the English source' % code)
    report.append('%s: heads %d->%d, table %d->%d, fences %d, nl=%s' % (
        code, len(heads_txt), len(vh), len([l for l in raw.split(nl) if l.startswith('|')]), len(vr),
        vf, 'CRLF' if nl == '\r\n' else 'LF'))
    if not DRY:
        open(path, 'wb').write(out.encode('utf-8'))

print('\n'.join(report))
print('problems: %d %s' % (len(problems), problems))
print('source reference: %d headings, %d table rows, %d fences' % (len(src_heads), len(src_rows), len(re.findall(r'^```', src, re.M))))
print('DRY-RUN' if DRY else 'APPLIED (%d files)' % len(MY))
sys.exit(1 if problems else 0)
