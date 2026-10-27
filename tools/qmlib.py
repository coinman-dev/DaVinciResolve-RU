"""Reading and writing Qt 5 translation files (.qm).

Only the parts used by DaVinci Resolve are supported: messages with a
context, a source text, an optional comment and one or more translations
(several for plural forms), the hash table, the language and the numerus
rules.
"""

import re
import struct
import zlib

MAGIC = bytes([0x3C, 0xB8, 0x64, 0x18, 0xCA, 0xEF, 0x9C, 0x95,
               0xCD, 0x21, 0x1C, 0xBF, 0x60, 0xA1, 0xBD, 0xDD])

# Section tags.
TAG_CONTEXTS = 0x2F
TAG_HASHES = 0x42
TAG_MESSAGES = 0x69
TAG_NUMERUS_RULES = 0x88
TAG_DEPENDENCIES = 0x96
TAG_LANGUAGE = 0xA7

# Message tags.
MSG_END = 1
MSG_SOURCE_TEXT16 = 2
MSG_TRANSLATION = 3
MSG_CONTEXT16 = 4
MSG_OBSOLETE1 = 5
MSG_SOURCE_TEXT = 6
MSG_CONTEXT = 7
MSG_COMMENT = 8
MSG_OBSOLETE2 = 9


def elf_hash(data: bytes) -> int:
    """The hash Qt uses for the hash table, of the source text + comment."""
    h = 0
    for c in data:
        h = ((h << 4) + c) & 0xFFFFFFFF
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xFFFFFFFF
    return h or 1


def read_sections(qm: bytes) -> dict:
    if not qm.startswith(MAGIC):
        raise ValueError('not a .qm file')
    sections = {}
    p = len(MAGIC)
    while p + 5 <= len(qm):
        tag = qm[p]
        (length,) = struct.unpack('>I', qm[p + 1:p + 5])
        sections[tag] = qm[p + 5:p + 5 + length]
        p += 5 + length
    return sections


def read_messages(qm: bytes) -> dict:
    """Returns {'language', 'numerus_rules', 'messages': [...]}, each message
    a dict with ctx, src, cmt and tr (list of translations)."""
    sections = read_sections(qm)
    data = sections.get(TAG_MESSAGES, b'')
    messages = []
    cur = {}
    q = 0
    while q < len(data):
        tag = data[q]
        q += 1
        if tag == MSG_END:
            messages.append({
                'ctx': cur.get('ctx', ''),
                'src': cur.get('src', ''),
                'cmt': cur.get('cmt', ''),
                'tr': cur.get('tr', []),
            })
            cur = {}
        elif tag == MSG_TRANSLATION:
            (length,) = struct.unpack('>I', data[q:q + 4])
            q += 4
            if length == 0xFFFFFFFF:
                cur.setdefault('tr', []).append(None)
            else:
                cur.setdefault('tr', []).append(
                    data[q:q + length].decode('utf-16-be', 'replace'))
                q += length
        elif tag in (MSG_SOURCE_TEXT, MSG_CONTEXT, MSG_COMMENT):
            (length,) = struct.unpack('>I', data[q:q + 4])
            q += 4
            key = {MSG_SOURCE_TEXT: 'src', MSG_CONTEXT: 'ctx',
                   MSG_COMMENT: 'cmt'}[tag]
            cur[key] = data[q:q + length].decode('utf-8', 'replace')
            q += length
        elif tag in (MSG_SOURCE_TEXT16, MSG_CONTEXT16):
            (length,) = struct.unpack('>I', data[q:q + 4])
            q += 4 + length
        elif tag == MSG_OBSOLETE1:
            q += 4
        elif tag == MSG_OBSOLETE2:
            pass
        else:
            raise ValueError(f'unknown message tag {tag:#x} at {q - 1}')
    language = sections.get(TAG_LANGUAGE, b'').decode('latin1')
    return {
        'language': language,
        'numerus_rules': sections.get(TAG_NUMERUS_RULES, b''),
        'messages': messages,
    }


def _block(tag: int, body: bytes) -> bytes:
    return bytes([tag]) + struct.pack('>I', len(body)) + body


def write_qm(messages, language='ru_RU', numerus_rules=b'') -> bytes:
    """Builds a .qm file. messages: iterable of dicts with ctx, src, cmt and
    tr (a list of one or more translations)."""
    entries = []
    for m in messages:
        src = m['src'].encode('utf-8')
        cmt = m.get('cmt', '').encode('utf-8')
        entries.append((elf_hash(src + cmt), m))
    # The table is searched by hash, entries with equal hashes are adjacent.
    entries.sort(key=lambda e: e[0])

    msg_data = bytearray()
    hashes = bytearray()
    for h, m in entries:
        hashes += struct.pack('>II', h, len(msg_data))
        for tr in m['tr']:
            body = tr.encode('utf-16-be')
            msg_data += bytes([MSG_TRANSLATION]) + struct.pack('>I', len(body)) + body
        ctx = m['ctx'].encode('utf-8')
        msg_data += bytes([MSG_CONTEXT]) + struct.pack('>I', len(ctx)) + ctx
        src = m['src'].encode('utf-8')
        msg_data += bytes([MSG_SOURCE_TEXT]) + struct.pack('>I', len(src)) + src
        cmt = m.get('cmt', '').encode('utf-8')
        if cmt:
            msg_data += bytes([MSG_COMMENT]) + struct.pack('>I', len(cmt)) + cmt
        msg_data += bytes([MSG_END])

    out = bytearray(MAGIC)
    out += _block(TAG_LANGUAGE, language.encode('latin1'))
    if numerus_rules:
        out += _block(TAG_NUMERUS_RULES, numerus_rules)
    out += _block(TAG_HASHES, bytes(hashes))
    out += _block(TAG_MESSAGES, bytes(msg_data))
    return bytes(out)


def find_compressed_qm(data: bytes):
    """Yields (offset, qm bytes) for the qCompress'ed .qm files embedded in a
    binary: a 4-byte big-endian size followed by a zlib stream."""
    for m in re.finditer(rb'\x78[\x01\x5e\x9c\xda]', data):
        i = m.start()
        try:
            head = zlib.decompressobj().decompress(data[i:i + 256], 32)
        except zlib.error:
            continue
        if not head.startswith(MAGIC[:8]):
            continue
        size = int.from_bytes(data[i - 4:i], 'big')
        yield i, zlib.decompressobj().decompress(data[i:i + size + 1_000_000])
