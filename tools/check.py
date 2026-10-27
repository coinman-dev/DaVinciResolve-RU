"""Checks translated batches: every source text of the batch is translated,
placeholders, markup and formatting are kept, plural forms are given.

Usage: python -I tools/check.py work/out/b001.json [...]
       python -I tools/check.py --all
Exits with 1 and lists the problems if there are any.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PLACEHOLDER = re.compile(r'%L?\d+|%n|%[a-z]+|\{[\w.]*\}')
TAG = re.compile(r'</?(?:a|b|i|u|s|p|br|hr|li|ul|ol|em|tt|h\d|div|pre|sub|sup|img|font|span|code|body|head|html|meta|table|tr|td|th|style|small|big|strong|center|nobr|qt)\b[^>]*>', re.I)
CYRILLIC = re.compile(r'[а-яёА-ЯЁ]')


def multiset(items):
    return sorted(items)


def check_one(src, tr, plural):
    problems = []
    forms = tr if isinstance(tr, list) else [tr]
    if plural:
        if not isinstance(tr, list) or len(tr) != 3:
            problems.append('plural: needs a list of 3 forms (1, 2-4, 5+)')
    elif isinstance(tr, list):
        problems.append('not plural: needs a single string')

    for form in forms:
        if not isinstance(form, str) or (not form.strip() and src.strip()):
            problems.append('empty translation')
            continue
        src_ph = multiset(p for p in PLACEHOLDER.findall(src) if p != '%n')
        tr_ph = multiset(p for p in PLACEHOLDER.findall(form) if p != '%n')
        if src_ph != tr_ph:
            problems.append(f'placeholders {src_ph} != {tr_ph}')
        if ('%n' in src) != ('%n' in form):
            problems.append('%n must be kept')
        if multiset(t.lower() for t in TAG.findall(src)) != multiset(t.lower() for t in TAG.findall(form)):
            problems.append('HTML tags differ')
        if src.count('\n') != form.count('\n'):
            problems.append('line breaks differ')
        if src.endswith('...') and not form.endswith('...'):
            problems.append('trailing "..." missing')
        if src.endswith(':') and not form.endswith(':'):
            problems.append('trailing ":" missing')
        if src[:1].isspace() != form[:1].isspace() or src[-1:].isspace() != form[-1:].isspace():
            problems.append('leading/trailing whitespace differs')
        # An accelerator is "&" before a character, "&&" and "& " are literal.
        # The official translation often drops them ("B&W" -> "ч/б"), so only
        # added ones are reported.
        accelerator = re.compile(r'&(?=[^&\s])')
        amp = len(accelerator.findall(src.replace('&&', '')))
        if len(accelerator.findall(form.replace('&&', ''))) > amp:
            problems.append('"&" accelerator count differs')
        if CYRILLIC.search(src) is None and re.search(r'[A-Za-z]{3}', src) and not CYRILLIC.search(form):
            # Untranslated is fine for names and codes only, the reviewer
            # decides, so it's only reported.
            problems.append('note: kept in Latin')
    return problems


def check_file(out_path):
    name = os.path.basename(out_path)
    batch = json.load(open(os.path.join(ROOT, 'work', 'batches', name), encoding='utf-8'))
    out = json.load(open(out_path, encoding='utf-8'))
    errors, notes = [], []
    # Batches of logged strings (rNNN) are keyed by context + source text.
    for item in batch:
        src = item['src']
        key = item.get('key', src)
        if key not in out:
            errors.append(f'missing: {key!r}')
            continue
        for p in check_one(src, out[key], item.get('plural', False)):
            (notes if p.startswith('note:') else errors).append(f'{src!r}: {p}')
    extra = set(out) - {i.get('key', i['src']) for i in batch}
    for src in extra:
        errors.append(f'not in the batch: {src!r}')
    return errors, notes


def main():
    paths = sorted(glob.glob(os.path.join(ROOT, 'work', 'out', '[br]*.json'))) \
        if '--all' in sys.argv else sys.argv[1:]
    failed = False
    for path in paths:
        errors, notes = check_file(path)
        status = 'OK' if not errors else f'{len(errors)} errors'
        print(f'{os.path.basename(path)}: {status}, {len(notes)} kept in Latin')
        for e in errors[:50]:
            print('  ' + e)
        failed |= bool(errors)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
