#!/usr/bin/env python3
"""saitranslate: revert apply-e.py.

apply-e.py localized `LanguageLabel` in all 29 mirrors; the role's own LOG (SAIT-002)
records that the English literal was a deliberate choice ("en.json value; Core's
ru/et/ded missing same key, en fallback = Core convention"). This package's declared
scope is the 18 new keys only, so the stub values go back to exactly what SAIT-002
wrote. Guarded: only reverts when the current value is the one apply-e.py set.
"""
import json, os, sys

DRY = '--apply' not in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
KITCHEN = os.path.join(os.path.dirname(HERE), 'kitchen', 'locales')
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
EN = json.load(open(os.path.join(ROOT, 'desktop', 'locales', 'en.json'), encoding='utf-8'))

sys.path.insert(0, HERE)
_saved_argv, sys.argv = sys.argv, [sys.argv[0]]  # stop apply-e.py from seeing --apply
ns = {'__file__': os.path.join(HERE, 'apply-e.py'), '__name__': 'apply-e'}
exec(compile(open(os.path.join(HERE, 'apply-e.py'), encoding='utf-8').read(), 'apply-e', 'exec'), ns)
sys.argv = _saved_argv
LANGUAGE, EXTRA = ns['LANGUAGE'], ns['EXTRA']

reverted, skipped = [], []
for code, lang in sorted(LANGUAGE.items()):
    path = os.path.join(KITCHEN, code + '.json')
    d = json.loads(open(path, 'rb').read().decode('utf-8'))
    want = {'LanguageLabel': lang}
    want.update(EXTRA.get(code, {}))
    edits = {}
    for k, myval in want.items():
        if d[k] == myval:
            edits[k] = EN[k]
        else:
            skipped.append('%s.%s not my value (%s)' % (code, k, ascii(d[k])))
    if not edits:
        continue
    for k, v in edits.items():
        d[k] = v
    out = (json.dumps(d, ensure_ascii=False, indent=2) + '\n').replace('\n', '\r\n').encode('utf-8')
    assert json.loads(out.decode('utf-8')) == d and len(d) == 68
    if not DRY:
        open(path, 'wb').write(out)
    reverted.append('%s: %s' % (code, ', '.join(sorted(edits))))

print('reverted %d files: %s' % (len(reverted), ', '.join(reverted)))
print('skipped: %s' % (skipped or 'none'))
print('DRY-RUN' if DRY else 'APPLIED')
