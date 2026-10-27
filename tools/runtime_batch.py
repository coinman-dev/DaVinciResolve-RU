"""Makes a batch of the strings the mod logged as untranslated (logUntranslated
setting, captured with tools/dbwin.ps1) that no language file of Resolve has,
so they need a context-specific translation in translations/overrides.json.

Usage: python -I tools/runtime_batch.py work/untranslated.log
Writes work/batches/rNNN.json with items {key, ctx, src}; the translation goes
to work/out/rNNN.json as {key: translation}, merged by tools/assemble.py.
"""

import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import qmlib  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path, default=None):
    path = os.path.join(ROOT, path)
    if not os.path.exists(path):
        return default
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def main():
    log = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    items = list(dict.fromkeys(
        (m.group(1), m.group(2))
        for m in re.finditer(r'Untranslated: (.*?) \| (.*)$', log, re.M)))

    # Strings of the language files are handled by the main batches; the ones
    # logged anyway are deliberately the same in Russian (names, codes).
    known = set()
    for path in glob.glob(os.path.join(ROOT, 'work', 'extracted', '*.qm')):
        for m in qmlib.read_messages(open(path, 'rb').read())['messages']:
            known.add((m['ctx'], m['src']))
    for name in ('work/fusion_missing.json', 'work/fusion_ru_existing.json'):
        for m in load(name, []):
            known.add((m['ctx'], m['src']))

    overrides = load('translations/overrides.json', {})
    batched = set()
    for path in glob.glob(os.path.join(ROOT, 'work', 'batches', 'r*.json')):
        batched |= {i['key'] for i in load(os.path.relpath(path, ROOT))}

    new = []
    for ctx, src in items:
        key = ctx + '\u0004' + src
        if (ctx, src) in known or key in overrides or key in batched:
            continue
        if not re.search(r'[a-z]{2}', src):  # codes, units, single letters
            continue
        new.append({'key': key, 'ctx': ctx, 'src': src})

    if not new:
        print('nothing new')
        return
    number = len(glob.glob(os.path.join(ROOT, 'work', 'batches', 'r*.json'))) + 1
    path = os.path.join(ROOT, 'work', 'batches', f'r{number:03d}.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(new, f, ensure_ascii=False, indent=1)
    print(f'{path}: {len(new)} strings')


if __name__ == '__main__':
    main()
