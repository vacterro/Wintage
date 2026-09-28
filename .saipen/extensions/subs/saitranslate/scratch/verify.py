#!/usr/bin/env python3
"""saitranslate: independent verification of the 29 locale mirrors (fresh disk read).

Nothing is imported from apply.py; this re-derives every fact from the bytes on disk.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SUB = os.path.dirname(HERE)
KITCHEN = os.path.join(SUB, 'kitchen', 'locales')
ROOT = os.path.abspath(os.path.join(SUB, '..', '..', '..', '..'))
LOCALES = os.path.join(ROOT, 'desktop', 'locales')
MY = ['ar', 'bg', 'cs', 'da', 'de', 'el', 'es', 'fi', 'fr', 'he', 'hi', 'hr', 'hu',
      'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt', 'ro', 'sk', 'sv', 'th', 'tr',
      'uk', 'vi', 'zh']
DESC = {'BdGoodEmojiDesc': 14, 'BdRemoveStickersDesc': 9, 'BdRemoveGIFSDesc': 10}

en = json.load(open(os.path.join(LOCALES, 'en.json'), encoding='utf-8'))
en_order = [k for k in en]
# the 18 keys this package added = kitchen-only keys, minus the pre-existing LanguageLabel stub
_pub_de = list(json.load(open(os.path.join(LOCALES, 'de.json'), encoding='utf-8')))
_kit_de = list(json.load(open(os.path.join(KITCHEN, 'de.json'), encoding='utf-8')))
NEW = [k for k in _kit_de if k not in _pub_de and k != 'LanguageLabel']
assert len(NEW) == 18, NEW
fails, checks = [], 0

def ck(cond, msg):
    global checks
    checks += 1
    if not cond:
        fails.append(msg)

lines = ['%-4s %-4s %-4s %-5s %-6s %s' % ('loc', 'keys', 'same', 'order', 'format', 'desc-lines')]
for code in MY:
    p = os.path.join(KITCHEN, code + '.json')
    raw = open(p, 'rb').read()
    d = json.loads(raw.decode('utf-8'))
    ks = list(d)
    ck(len(d) == 68, '%s: %d keys (want 68)' % (code, len(d)))
    ck(set(ks) == set(en_order), '%s: key set differs from en: %s' % (code, sorted(set(ks) ^ set(en_order))))
    # order: the pre-existing keys must keep the exact order the published file has
    # (kitchen had already appended LanguageLabel after StatusHint before this package),
    # and the 18 new keys must be appended in en.json order
    pubd = json.load(open(os.path.join(LOCALES, code + '.json'), encoding='utf-8'))
    pub = list(pubd)
    old = [k for k in ks if k not in NEW]
    ck(old == pub + ['LanguageLabel'], '%s: existing key order changed' % code)
    ck([k for k in ks if k in NEW] == [k for k in en_order if k in NEW],
       '%s: new keys not in en order' % code)
    # the decisive scoping check: every previously published key must be returned
    # byte-for-byte unchanged -- this package contributes the 18 keys and nothing else
    drift = [k for k in pub if d[k] != pubd[k]]
    ck(not drift, '%s: pre-existing values changed: %s' % (code, drift))
    ck(not [k for k in NEW if k in pubd], '%s: new keys already published' % code)
    ck(raw[:3] != b'\xef\xbb\xbf', '%s: BOM present' % code)
    ck(raw.endswith(b'\r\n'), '%s: no trailing CRLF' % code)
    ck(raw.count(b'\n') == raw.count(b'\r\n'), '%s: mixed line endings' % code)
    ck(raw.count(b'\r\n') == raw.count(b'\n'), '%s: stray LF' % code)
    for k, v in d.items():
        ck(isinstance(v, str) and v.strip() != '', '%s.%s empty' % (code, k))
        ck(v.count('{0}') == en[k].count('{0}'), '%s.%s placeholder mismatch' % (code, k))
    dl = []
    for k, n in DESC.items():
        v = d[k]
        ck(v.split('\r\n')[0] == en[k].split('\r\n')[0], '%s.%s title drifted' % (code, k))
        ck(len(v.split('\r\n')) == n, '%s.%s has %d lines (want %d)' % (code, k, len(v.split('\r\n')), n))
        ck(len(re.findall(r'^  - ', v, re.M)) == len(re.findall(r'^  - ', en[k], re.M)),
           '%s.%s bullet count differs' % (code, k))
        dl.append(len(v.split('\r\n')))
    same = [k for k in en_order if d[k] == en[k]]
    lines.append('%-4s %-4d %-4d %-5s %-6s %s' % (code, len(d), len(same), 'ok', 'ok', dl))
    if same:
        lines.append('      identical-to-en: %s' % same)

print('\n'.join(lines))
print()
print('checks: %d, failures: %d' % (checks, len(fails)))
for f in fails:
    print('  FAIL', f)

# Core-owned locales, reported only
print()
for code in ['en', 'ru', 'et', 'ded']:
    d = json.load(open(os.path.join(LOCALES, code + '.json'), encoding='utf-8'))
    miss = [k for k in en_order if k not in d]
    print('core %-4s keys=%-3d missing=%d %s' % (code, len(d), len(miss), miss if len(miss) < 6 else miss[:6] + ['...']))
print()
print('kitchen mirror does not cover Core locales:', [c for c in ['en', 'ru', 'et', 'ded'] if os.path.exists(os.path.join(KITCHEN, c + '.json'))] or 'correct (none)')
sys.exit(1 if fails else 0)
