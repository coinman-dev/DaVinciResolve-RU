"""Extracts the translations embedded in Resolve.exe and lists the strings
missing from the Russian one.

Usage: python -I tools/extract.py "E:/DaVinci Resolve/Resolve.exe"

Writes to work/:
  extracted/<offset>.qm   every embedded .qm file
  ru_existing.json        the Russian translation shipped with Resolve
  missing.json            strings other languages have and Russian doesn't
  extract_info.json       the Resolve version and per-file statistics
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import qmlib  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'work')


def detect_script(messages):
    sample = ' '.join(t for m in messages[:2000] for t in m['tr'] if t)
    counts = {
        'cyrillic': len(re.findall(r'[а-яё]', sample, re.I)),
        'ukrainian': len(re.findall(r'[іїєґ]', sample, re.I)),
        'cjk': len(re.findall(r'[\u3040-\u30ff\u4e00-\u9fff\uac00-\ud7af]', sample)),
        'thai': len(re.findall(r'[\u0e00-\u0e7f]', sample)),
    }
    if counts['cyrillic'] > 1000:
        return 'uk' if counts['ukrainian'] > 50 else 'ru'
    return max(counts, key=counts.get) if max(counts.values()) > 1000 else 'latin'


def key(m):
    return (m['ctx'], m['src'], m['cmt'])


def main():
    exe = sys.argv[1]
    data = open(exe, 'rb').read()
    os.makedirs(os.path.join(WORK, 'extracted'), exist_ok=True)

    files = []
    for offset, qm in qmlib.find_compressed_qm(data):
        parsed = qmlib.read_messages(qm)
        name = f'{offset:x}.qm'
        open(os.path.join(WORK, 'extracted', name), 'wb').write(qm)
        files.append({
            'file': name,
            'language_tag': parsed['language'],
            'script': detect_script(parsed['messages']),
            'messages': len(parsed['messages']),
            'parsed': parsed,
        })

    # The main UI translations are the large files, the small ones belong to
    # other components.
    main_files = [f for f in files if f['messages'] > 10000]
    ru = [f for f in main_files if f['script'] == 'ru']
    if len(ru) != 1:
        sys.exit(f'expected one Russian translation, found {len(ru)}')
    ru = ru[0]

    ru_keys = {key(m) for m in ru['parsed']['messages']}

    # Translations that weren't updated for a while still contain strings
    # removed from Resolve, so only the up to date ones list the strings.
    largest = max(f['messages'] for f in main_files)
    current_files = [f for f in main_files
                     if f is not ru and f['messages'] > largest * 0.85]

    all_messages = {}
    plural = set()
    for f in main_files:
        for m in f['parsed']['messages']:
            if len(m['tr']) > 1:
                plural.add(key(m))
    for f in current_files:
        for m in f['parsed']['messages']:
            all_messages.setdefault(key(m), m)

    missing = []
    for k in sorted(all_messages.keys() - ru_keys):
        ctx, src, cmt = k
        item = {'id': len(missing), 'ctx': ctx, 'src': src}
        if cmt:
            item['cmt'] = cmt
        if k in plural or '%n' in src:
            item['plural'] = True
        missing.append(item)

    existing = [
        {'ctx': m['ctx'], 'src': m['src'], 'cmt': m['cmt'], 'tr': m['tr']}
        for m in ru['parsed']['messages']
    ]

    json.dump(existing, open(os.path.join(WORK, 'ru_existing.json'), 'w',
                             encoding='utf-8'), ensure_ascii=False, indent=0)
    json.dump(missing, open(os.path.join(WORK, 'missing.json'), 'w',
                            encoding='utf-8'), ensure_ascii=False, indent=0)
    info = {
        'resolve_exe': exe,
        'resolve_size': len(data),
        'ru_file': ru['file'],
        'current_files': [f['file'] for f in current_files],
        'ru_numerus_rules': ru['parsed']['numerus_rules'].hex(),
        'all_keys': len(all_messages),
        'ru_keys': len(ru_keys),
        'missing': len(missing),
        'files': [{k: v for k, v in f.items() if k != 'parsed'} for f in files],
    }
    json.dump(info, open(os.path.join(WORK, 'extract_info.json'), 'w',
                         encoding='utf-8'), ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in info.items() if k != 'files'},
                     ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
