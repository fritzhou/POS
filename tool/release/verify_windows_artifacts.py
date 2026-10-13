#!/usr/bin/env python3
"""Independently inspect downloaded Windows CI artifacts without running them."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
directory = args.directory.resolve()
root = Path(__file__).resolve().parents[2]
package = directory / 'NexaPOS-Windows-Portable.zip'
manifest = json.loads((directory / 'NexaPOS-Windows-Manifest.json').read_text(encoding='utf-8-sig'))
assert isinstance(manifest, list) and manifest, 'No runtime file manifest'
expected = {}
for item in manifest:
    name = item['path']
    path = PurePosixPath(name)
    assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
    assert name not in expected and isinstance(item['bytes'], int) and item['bytes'] > 0
    expected[name] = item

def x64(data, name):
    assert data[:2] == b'MZ' and len(data) >= 64, f'Not a PE image: {name}'
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert offset + 6 <= len(data) and data[offset:offset+4] == b'PE\0\0', f'Invalid PE image: {name}'
    assert struct.unpack_from('<H', data, offset+4)[0] == 0x8664, f'Not Windows x64: {name}'

with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None, 'ZIP CRC failure'
    files = [item for item in archive.infolist() if not item.is_dir()]
    assert len(files) == len(expected) and {item.filename for item in files} == set(expected), 'Incomplete or extra ZIP files'
    for item in files:
        assert (item.external_attr >> 16) & 0o170000 != 0o120000, 'Unexpected symbolic link'
        data = archive.read(item)
        proof = expected[item.filename]
        assert len(data) == proof['bytes'] and hashlib.sha256(data).hexdigest() == proof['sha256'], item.filename
    required = ['NexaPOS.exe', 'flutter_windows.dll', 'app_links_plugin.dll',
                'flutter_secure_storage_windows_plugin.dll', 'printing_plugin.dll', 'pdfium.dll',
                'url_launcher_windows_plugin.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
                'data/icudtl.dat', 'data/app.so']
    for name in required:
        assert name in expected, f'Missing runtime: {name}'
        if name.endswith(('.exe', '.dll')):
            x64(archive.read(name), name)
    cipher = [name for name in expected if PurePosixPath(name).name.startswith('sqlcipher') and name.endswith('.dll')]
    assert len(cipher) == 1
    x64(archive.read(cipher[0]), cipher[0])
    assert hashlib.sha256(archive.read(cipher[0])).hexdigest() == '1a4b81f2027adf809bcb9a8a2cecae3506ec62ebc9a5391d2fd5f4bfbdda4f0c'
    fonts = json.loads((root / 'assets/fonts/PROVENANCE.json').read_text())['packaged_fonts']
    for name, digest in fonts.items():
        assert hashlib.sha256(archive.read('data/flutter_assets/assets/fonts/' + name)).hexdigest() == digest
    for name in ['NOTO-LICENSE.txt', 'NOTO-CJK-LICENSE.txt', 'PROVENANCE.json']:
        assert 'data/flutter_assets/assets/fonts/' + name in expected

report = (directory / 'NexaPOS-Windows-Build-Report.txt').read_text(encoding='utf-8-sig')
assert 'Build status: PASS' in report and 'Flutter: 3.44.0' in report
assert 'Startup/installer smoke: passed' in report
assert 'Public Supabase client configuration supplied: False' in report
smoke = (directory / 'NexaPOS-Windows-Smoke.txt').read_text(encoding='utf-8-sig')
assert 'Extracted portable release: PASS' in smoke
installer = directory / 'NexaPOS-Windows-Setup.exe'
if installer.exists():
    assert installer.stat().st_size > 0 and installer.read_bytes()[:2] == b'MZ'
    assert 'Installed release: PASS' in smoke and 'Installer: PASS' in smoke
result = {'architecture': 'Windows x64', 'build_type': 'release', 'runtime_files': len(expected),
          'zip_bytes': package.stat().st_size, 'zip_sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
          'installer_generated': installer.exists(), 'native_launch_smoke': 'passed',
          'all_runtime_hashes_and_fonts_verified': True, 'supabase': 'disconnected preview',
          'windows_authenticode': 'not configured; executable and installer unsigned'}
if installer.exists():
    result.update(installer_bytes=installer.stat().st_size,
                  installer_sha256=hashlib.sha256(installer.read_bytes()).hexdigest(),
                  installer_install_launch_uninstall='passed')
(directory / 'NexaPOS-Windows-Inspection.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
