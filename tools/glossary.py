"""Builds work/glossary.tsv: the terms of Resolve's own Russian translation,
for consistent terminology. Short source texts (up to 4 words) with their most
common translation, the most frequent first.

Usage: python -I tools/glossary.py
"""

import collections
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    existing = []
    for name in ('ru_existing.json', 'fusion_ru_existing.json'):
        path = os.path.join(ROOT, 'work', name)
        if os.path.exists(path):
            with open(path, encoding='utf-8') as f:
                existing += json.load(f)

    counts = collections.defaultdict(collections.Counter)
    for m in existing:
        src = m['src'].strip()
        tr = m['tr'][0] if m['tr'] else None
        if not tr or tr == src or '\n' in src or len(src.split()) > 4:
            continue
        if any(c.isalpha() for c in src) and len(src) > 1:
            counts[src][tr.strip()] += 1

    rows = sorted(counts.items(), key=lambda kv: (-sum(kv[1].values()), kv[0].lower()))
    with open(os.path.join(ROOT, 'work', 'glossary.tsv'), 'w', encoding='utf-8') as f:
        f.write('english\trussian\n')
        for src, c in rows:
            f.write(f'{src}\t{c.most_common(1)[0][0]}\n')
    print(f'{len(rows)} terms')


if __name__ == '__main__':
    main()
