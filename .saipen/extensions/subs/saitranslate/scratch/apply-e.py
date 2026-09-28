#!/usr/bin/env python3
"""saitranslate: second drift item -- untranslated stubs in the 29 mirrors.

Only keys whose current value is byte-identical to en.json are touched, so a
deliberate locale choice can never be clobbered. Dry-run unless --apply.
"""
import json, os, sys, io

DRY = '--apply' not in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
KITCHEN = os.path.join(os.path.dirname(HERE), 'kitchen', 'locales')
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
EN = json.load(open(os.path.join(ROOT, 'desktop', 'locales', 'en.json'), encoding='utf-8'))

LANGUAGE = {
    'ar': 'اللغة', 'bg': 'Език', 'cs': 'Jazyk', 'da': 'Sprog', 'de': 'Sprache',
    'el': 'Γλώσσα', 'es': 'Idioma', 'fi': 'Kieli', 'fr': 'Langue', 'he': 'שפה',
    'hi': 'भाषा', 'hr': 'Jezik', 'hu': 'Nyelv', 'id': 'Bahasa', 'it': 'Lingua',
    'ja': '言語', 'ko': '언어', 'nl': 'Taal', 'no': 'Språk', 'pl': 'Język',
    'pt': 'Idioma', 'ro': 'Limba', 'sk': 'Jazyk', 'sv': 'Språk', 'th': 'ภาษา',
    'tr': 'Dil', 'uk': 'Мова', 'vi': 'Ngôn ngữ', 'zh': '语言',
}
EXTRA = {'vi': {'ColTarget': 'mục tiêu', 'ColPalette': 'bảng màu'}}

assert len(LANGUAGE) == 29
changed, kept = [], []
for code, lang in sorted(LANGUAGE.items()):
    path = os.path.join(KITCHEN, code + '.json')
    raw = open(path, 'rb').read()
    d = json.loads(raw.decode('utf-8'))
    want = {'LanguageLabel': lang}
    want.update(EXTRA.get(code, {}))
    edits = {}
    for k, v in want.items():
        cur = d[k]
        if cur == EN[k]:
            edits[k] = v
        else:
            kept.append('%s.%s already localized (%s)' % (code, k, ascii(cur)))
    if not edits:
        continue
    for k, v in edits.items():
        assert v and v != EN[k], (code, k)
        d[k] = v
    text = json.dumps(d, ensure_ascii=False, indent=2) + '\n'
    out = text.replace('\n', '\r\n').encode('utf-8')
    assert json.loads(out.decode('utf-8')) == d and len(d) == 68
    assert out[:3] != b'\xef\xbb\xbf' and out.endswith(b'\r\n')
    if not DRY:
        open(path, 'wb').write(out)
    changed.append('%s: %s' % (code, ', '.join('%s=%s' % (k, ascii(v)) for k, v in edits.items())))

print('\n'.join(changed).encode('ascii', 'backslashreplace').decode())
print('\nkept (already localized): %s' % (kept or 'none'))
print('files edited: %d/29, keys: %d, %s' % (len(changed), sum(len(EXTRA.get(c, {})) + 1 for c in changed),
                                             'DRY-RUN' if DRY else 'APPLIED'))
