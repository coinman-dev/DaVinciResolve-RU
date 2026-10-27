"""Lists the exported names of a PE file that match a regex."""
import re, struct, sys

def exports(path):
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3C)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsz = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    ddir = opt + (112 if magic == 0x20B else 96)
    exp_rva = struct.unpack_from('<I', d, ddir)[0]
    secs = []
    for i in range(nsec):
        s = opt + optsz + i * 40
        va, vs, raw = struct.unpack_from('<III', d, s + 12)[0], struct.unpack_from('<I', d, s + 8)[0], struct.unpack_from('<I', d, s + 20)[0]
        secs.append((va, vs, raw))
    def off(rva):
        for va, vs, raw in secs:
            if va <= rva < va + max(vs, 1):
                return rva - va + raw
        raise ValueError(rva)
    e = off(exp_rva)
    n_names, names_rva = struct.unpack_from('<I', d, e + 24)[0], struct.unpack_from('<I', d, e + 32)[0]
    for i in range(n_names):
        r = struct.unpack_from('<I', d, off(names_rva) + i * 4)[0]
        o = off(r)
        yield d[o:d.index(b'\0', o)].decode('latin1')

if __name__ == '__main__':
    rx = re.compile(sys.argv[2])
    for n in exports(sys.argv[1]):
        if rx.search(n):
            print(n)
