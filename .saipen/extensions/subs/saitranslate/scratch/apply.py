#!/usr/bin/env python3
"""saitranslate: merge the 18 new BetterDiscord keys into the 29 locale mirrors.

Dry-run by default; pass --apply to write. Hard-asserts the whole contract so a
silent partial merge is impossible.
"""
import json, os, sys, io

DRY = '--apply' not in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
SUB = os.path.dirname(HERE)
KITCHEN = os.path.join(SUB, 'kitchen')
ROOT = os.path.abspath(os.path.join(SUB, '..', '..', '..', '..'))
LOCALES = os.path.join(ROOT, 'desktop', 'locales')
MY_LOCALES = ['ar', 'bg', 'cs', 'da', 'de', 'el', 'es', 'fi', 'fr', 'he', 'hi', 'hr',
              'hu', 'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt', 'ro', 'sk', 'sv',
              'th', 'tr', 'uk', 'vi', 'zh']

def load_mod(path, name):
    ns = {}
    exec(compile(open(path, encoding='utf-8').read(), path, 'exec'), ns)
    return ns[name]

en = json.load(open(os.path.join(LOCALES, 'en.json'), encoding='utf-8'))
a = load_mod(os.path.join(HERE, 'backfill-a.py'), 'TRANS')
b = load_mod(os.path.join(HERE, 'backfill-b.py'), 'TRANS')
c = load_mod(os.path.join(HERE, 'backfill-c.py'), 'TRANS')
d = load_mod(os.path.join(HERE, 'backfill-d.py'), 'BULLETS')

NEW = [k for k in en if k not in json.load(open(os.path.join(KITCHEN, 'locales', 'de.json'), encoding='utf-8'))]
assert len(NEW) == 18, NEW

TRANS = {}
for part in (a, b, c):
    for k, v in part.items():
        assert k not in TRANS, 'duplicate locale ' + k
        TRANS[k] = v
assert sorted(TRANS) == sorted(MY_LOCALES), (sorted(set(TRANS) ^ set(MY_LOCALES)))
assert sorted(d) == sorted(MY_LOCALES)

DESC_SHAPE = {'BdGoodEmojiDesc': (14, 3, 9), 'BdRemoveStickersDesc': (9, 3, 4),
              'BdRemoveGIFSDesc': (10, 3, 5)}
report, problems = [], []
for code in MY_LOCALES:
    src = open(os.path.join(LOCALES, code + '.json'), 'rb').read()
    t = TRANS[code]
    assert sorted(t) == sorted(NEW), (code, sorted(set(t) ^ set(NEW)))
    # kill the scratch placeholder bullets supplied by batches A/B/C
    for k in NEW:
        if isinstance(t[k], list) and k == 'BdGoodEmojiDesc':
            assert t[k][3:12] == ['  - sob -> joy', '  - cry -> smile', '  - pleading -> sunglasses',
                                  '  - skull -> slight_smile', '  - wilted_rose -> rose',
                                  '  - clown -> thumbsup', '  - sad/frown -> smiley/grin',
                                  '  - broken_heart -> heart', '  - middle_finger -> peace'], code
            t[k][3:12] = ['  - ' + x for x in d[code]]
    vals = {}
    for k in NEW:
        v = t[k]
        if isinstance(v, list):
            v = '\r\n'.join(v)
        vals[k] = v
        assert isinstance(v, str) and v.strip(), (code, k)
        if k in ('BdStatusReady', 'BdStatusNotFound'):
            assert v.count('{0}') == 1, (code, k, v)
        else:
            assert '{0}' not in v, (code, k)
        assert 'sob ->' not in v and 'joy' != v, (code, k)
    for k, (nlines, bstart, nbul) in DESC_SHAPE.items():
        lines = vals[k].split('\r\n')
        assert len(lines) == nlines, (code, k, len(lines))
        assert lines[0] == en[k].split('\r\n')[0], (code, k, lines[0])
        # intro line ends a sentence list: allow the fullwidth colon used by CJK locales
        assert lines[1] == '' and lines[bstart - 1].endswith((':', '\uff1a')), (code, k)
        assert lines[bstart + nbul] == '', (code, k)
        for i in range(nbul):
            assert lines[bstart + i].startswith('  - ') and len(lines[bstart + i]) > 6, (code, k, i)
    # merge, preserving existing order, appending new keys in en order
    path = os.path.join(KITCHEN, 'locales', code + '.json')
    cur = json.load(open(path, encoding='utf-8'))
    before = len(cur)
    assert not [k for k in NEW if k in cur], (code, 'already present')
    for k in NEW:
        cur[k] = vals[k]
    assert len(cur) == before + 18
    text = json.dumps(cur, ensure_ascii=False, indent=2) + '\n'
    out = io.BytesIO()
    out.write(text.replace('\n', '\r\n').encode('utf-8'))
    raw = out.getvalue()
    assert raw[:3] != b'\xef\xbb\xbf' and raw.endswith(b'\r\n')
    back = json.loads(raw.decode('utf-8'))
    assert back == cur and len(back) == 68, code
    report.append('%s: %d -> %d keys, %d bytes -> %d bytes%s' % (
        code, before, len(back), len(src), len(raw), '' if DRY else ' (written)'))
    if not DRY:
        open(path, 'wb').write(raw)

print(('\n'.join(report)))
print('OK: %d/%d locales, 18 keys each, %s' % (len(report), len(MY_LOCALES), 'DRY-RUN' if DRY else 'APPLIED'))
