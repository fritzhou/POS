#!/usr/bin/env python3
"""Install the pinned official Linux x86_64 Deno test runner with SHA-256."""
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import urllib.request
import zipfile

VERSION = '2.9.7'
SHA256 = 'c6527f24f4b16031d3ae4fa9f658d5f11534c8d84ce7dc8502420280919c3490'
URL = f'https://github.com/denoland/deno/releases/download/v{VERSION}/deno-x86_64-unknown-linux-gnu.zip'
root = Path(os.environ.get('NEXAPOS_TOOLCHAIN_ROOT', '/workspace/.toolchains'))
binary = root / 'deno' / 'deno'
if platform.system() != 'Linux' or platform.machine() != 'x86_64':
    raise SystemExit('This helper supports Linux x86_64 only; install official Deno on other platforms.')
if binary.exists():
    version = subprocess.check_output([str(binary), '--version'], text=True).splitlines()[0]
    if version.split()[1] == VERSION:
        print(f'Deno {VERSION} is already installed.')
        raise SystemExit(0)
    raise SystemExit('A different Deno version exists; review it before replacing the toolchain.')
archive = Path('/tmp/nexapos-deno-verified.zip')
with urllib.request.urlopen(URL, timeout=60) as response, archive.open('wb') as output:
    shutil.copyfileobj(response, output)
if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    archive.unlink()
    raise SystemExit('Deno archive SHA-256 mismatch; installation stopped.')
binary.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive) as source:
    with source.open('deno') as input_file, binary.open('wb') as output:
        shutil.copyfileobj(input_file, output)
binary.chmod(0o755)
print(f'Installed Deno {VERSION}; official archive SHA-256 verified.')
