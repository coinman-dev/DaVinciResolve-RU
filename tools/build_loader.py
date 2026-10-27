"""Builds dist/dxva2.dll, the loader of the translation without Windhawk
(loader/dxva2.c), with the clang of the Windhawk developer tools.

Usage: python -I tools/build_loader.py [path to clang.exe]
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLANG = r'C:\Program Files\Windhawk\Compiler\bin\clang++.exe'


def main():
    clang = sys.argv[1] if len(sys.argv) > 1 else CLANG
    os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
    out = os.path.join(ROOT, 'dist', 'dxva2.dll')
    cmd = [
        clang, '-x', 'c', '-std=c17', '-target', 'x86_64-w64-mingw32',
        '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter',
        '-DUNICODE', '-D_UNICODE', '-D_WIN32_WINNT=0x0A00',
        '-shared', '-static', '-s',
        os.path.join(ROOT, 'loader', 'dxva2.c'),
        '-x', 'none', os.path.join(ROOT, 'loader', 'dxva2.def'),
        '-o', out,
    ]
    subprocess.run(cmd, check=True)
    print(out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()
