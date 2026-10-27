"""Merges the checked batch translations from work/out/ into
translations/ru.json (source text -> translation or plural forms).

Existing entries of translations/ru.json are kept unless a batch translates
the same source text again.

Usage: python -I tools/assemble.py
"""

import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    outs = sorted(glob.glob(os.path.join(ROOT, 'work', 'out', 'b*.json')))
    check = subprocess.run([sys.executable, '-I', os.path.join(ROOT, 'tools', 'check.py'), *outs])
    if check.returncode:
        sys.exit('fix the batch errors first')

    path = os.path.join(ROOT, 'translations', 'ru.json')
    ru = {}
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            ru = json.load(f)

    added = 0
    for out in outs:
        with open(out, encoding='utf-8') as f:
            for src, tr in json.load(f).items():
                added += src not in ru
                ru[src] = tr

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(dict(sorted(ru.items(), key=lambda kv: kv[0].lower())), f,
                  ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{path}: {len(ru)} source texts, {added} new')


if __name__ == '__main__':
    main()
