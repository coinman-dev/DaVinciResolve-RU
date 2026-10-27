"""Splits the source texts that still need a translation into batches for
translating.

Each unique source text is translated once. A batch item lists the contexts
it's used in, which hint at where in the interface it appears, and whether it
needs plural forms. Source texts already translated in translations/ru.json
or by Resolve's own Russian translation are skipped.

Usage: python -I tools/make_batches.py [--size 250]
Writes work/batches/bNNN.json, never overwriting existing batches, so it can
be re-run after new strings appear.
"""

import collections
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path, default=None):
    path = os.path.join(ROOT, path)
    if not os.path.exists(path):
        return default
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def main():
    size = 250
    if '--size' in sys.argv:
        size = int(sys.argv[sys.argv.index('--size') + 1])

    missing = load('work/missing.json') + load('work/fusion_missing.json', [])
    existing = load('work/ru_existing.json') + load('work/fusion_ru_existing.json', [])
    ru = load('translations/ru.json', {})
    tm = {m['src'] for m in existing if m['tr'] and all(m['tr'])}

    batch_dir = os.path.join(ROOT, 'work', 'batches')
    os.makedirs(batch_dir, exist_ok=True)
    batched = set()
    for name in os.listdir(batch_dir):
        if name.endswith('.json') and name.startswith('b'):
            for item in load(os.path.join('work', 'batches', name)):
                batched.add(item['src'])

    contexts = collections.defaultdict(list)
    plural = set()
    order = []
    for m in missing:
        src = m['src']
        if src in ru or src in tm or src in batched:
            continue
        if src not in contexts:
            order.append(src)
        if m['ctx'] not in contexts[src]:
            contexts[src].append(m['ctx'])
        if m.get('plural'):
            plural.add(src)

    # Keep the strings of a context together, which keeps related strings in
    # the same batch.
    order.sort(key=lambda s: (contexts[s][0], s.lower()))

    existing_batches = [n for n in os.listdir(batch_dir) if n.startswith('b')]
    number = len(existing_batches) + 1
    for i in range(0, len(order), size):
        items = []
        for src in order[i:i + size]:
            item = {'src': src, 'ctx': contexts[src][:5]}
            if src in plural:
                item['plural'] = True
            items.append(item)
        path = os.path.join(batch_dir, f'b{number:03d}.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False, indent=1)
        number += 1

    print(f'{len(order)} source texts in {number - len(existing_batches) - 1} new batches')


if __name__ == '__main__':
    main()
