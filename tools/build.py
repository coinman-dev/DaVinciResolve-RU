"""Builds dist/resolve_ru_extra.qm with the strings missing from the Russian
translation of Resolve.

Sources of the translations, in order:
  translations/overrides.json  {"<context>\\u0004<source>": translation}
  translations/ru.json         {"<source>": translation or [plural forms]}
  the Russian translation of Resolve, for a source text it translates in
  another context (work/ru_existing.json)

Usage: python -I tools/build.py [--tm-only]
"""

import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import qmlib  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Russian has three plural forms: 1, 2-4 and 5+ (as in the Resolve translation).
PLURAL_FORMS = 3


def load_json(path, default):
    path = os.path.join(ROOT, path)
    if not os.path.exists(path):
        return default
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def translation_memory(existing):
    """The most common translation of each source text in Resolve's Russian
    translation."""
    counts = collections.defaultdict(collections.Counter)
    for m in existing:
        if m['tr'] and all(m['tr']):
            counts[m['src']][tuple(m['tr'])] += 1
    return {src: list(c.most_common(1)[0][0]) for src, c in counts.items()}


def forms(translation, plural):
    if isinstance(translation, str):
        translation = [translation]
    if plural and len(translation) < PLURAL_FORMS:
        translation = translation + [translation[-1]] * (PLURAL_FORMS - len(translation))
    return translation


def main():
    tm_only = '--tm-only' in sys.argv
    missing = load_json('work/missing.json', None)
    if missing is None:
        sys.exit('run tools/extract.py first')
    # The Fusion page strings, tools/extract_fusion.py.
    missing = missing + load_json('work/fusion_missing.json', [])
    info = load_json('work/extract_info.json', {})
    tm = translation_memory(load_json('work/ru_existing.json', []) +
                            load_json('work/fusion_ru_existing.json', []))
    ru = {} if tm_only else load_json('translations/ru.json', {})
    overrides = {} if tm_only else load_json('translations/overrides.json', {})

    messages = []
    stats = collections.Counter()
    for m in missing:
        key = m['ctx'] + '\u0004' + m['src']
        if key in overrides:
            tr, source = overrides[key], 'override'
        elif m['src'] in ru:
            tr, source = ru[m['src']], 'ru'
        elif m['src'] in tm:
            tr, source = tm[m['src']], 'tm'
        else:
            stats['untranslated'] += 1
            continue
        stats[source] += 1
        messages.append({
            'ctx': m['ctx'],
            'src': m['src'],
            'cmt': m.get('cmt', ''),
            'tr': forms(tr, m.get('plural', False)),
        })

    # Overrides of strings Resolve does translate, e.g. shorter ones for
    # cramped layouts. The additional translator is searched first.
    missing_keys = {m['ctx'] + '\u0004' + m['src'] for m in missing}
    for key, tr in overrides.items():
        if key in missing_keys:
            continue
        ctx, src = key.split('\u0004', 1)
        stats['override'] += 1
        messages.append({'ctx': ctx, 'src': src, 'cmt': '', 'tr': forms(tr, False)})

    rules = bytes.fromhex(info.get('ru_numerus_rules', ''))
    qm = qmlib.write_qm(messages, 'ru_RU', rules)
    os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
    out = os.path.join(ROOT, 'dist', 'resolve_ru_extra.qm')
    with open(out, 'wb') as f:
        f.write(qm)

    # Round trip check.
    parsed = qmlib.read_messages(qm)
    assert len(parsed['messages']) == len(messages)

    print(f'{out}: {len(messages)} strings, {len(qm)} bytes, {dict(stats)}')


if __name__ == '__main__':
    main()
