"""Extracts the Fusion page translations embedded in fusionsystem.dll and lists
the strings missing from the Russian one.

Usage: python -I tools/extract_fusion.py "E:/DaVinci Resolve/fusionsystem.dll"

The DLL has two sets of .qm files, both with language tags: the large Fusion
application translations (about 18,000 strings) and a small one, which is
complete in Russian. Some are qCompress'ed, some aren't.

Writes to work/:
  fusion_ru_existing.json   the Russian Fusion translation
  fusion_missing.json       strings the up to date languages have and Russian
                            doesn't
  fusion_extract_info.json  per-file statistics
"""

import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
import qmlib  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'work')
SECTION_TAGS = (qmlib.TAG_CONTEXTS, qmlib.TAG_HASHES, qmlib.TAG_MESSAGES,
                qmlib.TAG_NUMERUS_RULES, qmlib.TAG_DEPENDENCIES,
                qmlib.TAG_LANGUAGE)


def find_plain_qm(data):
    pos = 0
    while (pos := data.find(qmlib.MAGIC, pos)) != -1:
        p = pos + len(qmlib.MAGIC)
        while p + 5 <= len(data) and data[p] in SECTION_TAGS:
            p += 5 + struct.unpack('>I', data[p + 1:p + 5])[0]
        yield pos, data[pos:p]
        pos += len(qmlib.MAGIC)


def key(m):
    return (m['ctx'], m['src'], m['cmt'])


def main():
    dll = sys.argv[1]
    data = open(dll, 'rb').read()

    files = []
    for offset, qm in [*find_plain_qm(data), *qmlib.find_compressed_qm(data)]:
        parsed = qmlib.read_messages(qm)
        files.append({'offset': f'{offset:x}', 'language': parsed['language'],
                      'messages': len(parsed['messages']), 'parsed': parsed})

    main_files = [f for f in files if f['messages'] > 5000]
    ru = [f for f in files
          if f['language'].split('_')[0] == 'ru' and f['messages']]
    if not ru:
        sys.exit('no Russian Fusion translation found')
    ru_keys = {key(m) for f in ru for m in f['parsed']['messages']}

    largest = max(f['messages'] for f in main_files)
    current = [f for f in main_files
               if f not in ru and f['messages'] > largest * 0.85]
    main_files = main_files + [f for f in ru if f not in main_files]

    all_messages = {}
    plural = set()
    for f in main_files:
        for m in f['parsed']['messages']:
            if len(m['tr']) > 1:
                plural.add(key(m))
    for f in current:
        for m in f['parsed']['messages']:
            all_messages.setdefault(key(m), m)

    missing = []
    for k in sorted(all_messages.keys() - ru_keys):
        ctx, src, cmt = k
        if not src.strip():
            continue
        item = {'id': len(missing), 'ctx': ctx, 'src': src}
        if cmt:
            item['cmt'] = cmt
        if k in plural or '%n' in src:
            item['plural'] = True
        missing.append(item)

    existing = [{'ctx': m['ctx'], 'src': m['src'], 'cmt': m['cmt'], 'tr': m['tr']}
                for f in ru for m in f['parsed']['messages']]

    def dump(name, obj, indent=0):
        with open(os.path.join(WORK, name), 'w', encoding='utf-8') as f:
            json.dump(obj, f, ensure_ascii=False, indent=indent)

    dump('fusion_ru_existing.json', existing)
    dump('fusion_missing.json', missing)
    info = {
        'dll': dll,
        'ru_files': [f['offset'] for f in ru],
        'current_files': [f['offset'] for f in current],
        'all_keys': len(all_messages),
        'ru_keys': len(ru_keys),
        'missing': len(missing),
        'files': [{k: v for k, v in f.items() if k != 'parsed'} for f in files],
    }
    dump('fusion_extract_info.json', info, 1)
    print(json.dumps({k: v for k, v in info.items() if k != 'files'}, indent=1))


if __name__ == '__main__':
    main()
