"""Collects the release files in dist/release/: the ASCII copy of
Install-ResolveRU.ps1 (tools/ConvertTo-AsciiScript.ps1), dxva2.dll,
resolve_ru_extra.qm and SHA256SUMS.txt. Run tools/build.py and
tools/build_loader.py first.

Usage: python -I tools/package.py <tag, e.g. v1.0.0>
"""

import hashlib
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'coinman-dev/DaVinciResolve-RU'
FILES = ['dxva2.dll', 'resolve_ru_extra.qm']


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tag = sys.argv[1]
    out = os.path.join(ROOT, 'dist', 'release')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)

    subprocess.run([
        'pwsh', '-NoProfile', '-File',
        os.path.join(ROOT, 'tools', 'ConvertTo-AsciiScript.ps1'),
        '-Path', os.path.join(ROOT, 'Install-ResolveRU.ps1'),
        '-OutFile', os.path.join(out, 'Install-ResolveRU.ps1'),
        '-SourceUrl',
        f'https://github.com/{REPO}/blob/{tag}/Install-ResolveRU.ps1',
    ], check=True)
    for name in FILES:
        shutil.copyfile(os.path.join(ROOT, 'dist', name),
                        os.path.join(out, name))

    sums = []
    for name in ['Install-ResolveRU.ps1'] + FILES:
        with open(os.path.join(out, name), 'rb') as f:
            sums.append(f'{hashlib.sha256(f.read()).hexdigest()}  {name}\n')
    with open(os.path.join(out, 'SHA256SUMS.txt'), 'w', newline='\n') as f:
        f.writelines(sums)
    for name in sorted(os.listdir(out)):
        print(name, os.path.getsize(os.path.join(out, name)))


if __name__ == '__main__':
    main()
