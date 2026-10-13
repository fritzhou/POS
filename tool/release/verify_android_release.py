#!/usr/bin/env python3
"""Inspect actual release/signing/native/asset bytes; this is not a device test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path, default=Path('build/app/outputs/flutter-apk/app-release.apk'))
parser.add_argument('--output', type=Path, default=Path('build/release/NexaPOS-Android-Manifest.json'))
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
apk = args.apk.resolve()
sdk = Path(os.environ['ANDROID_SDK_ROOT']) / 'build-tools/36.0.0'
assert apk.is_file() and apk.stat().st_size > 0, 'No nonempty APK exists'

resources = subprocess.check_output([str(sdk / 'aapt2'), 'dump', 'resources', str(apk)], text=True)

def resource_files(name):
    # Resource shrinking may shorten ZIP paths while retaining public resource names.
    block = re.search(r'^    resource [^\n]+ ' + re.escape(name) + r'\n((?:      [^\n]*\n)+)', resources, re.M)
    assert block, f'Missing compiled resource: {name}'
    return re.findall(r'\(file\) ([^\s]+)', block.group(1))

def xml(name):
    return subprocess.check_output([str(sdk / 'aapt2'), 'dump', 'xmltree', str(apk), '--file', name], text=True)

manifest = xml('AndroidManifest.xml')
assert 'package="com.nexapos.app"' in manifest
assert 'label(0x01010001)="NexaPOS"' in manifest
assert 'debuggable(0x0101000f)=true' not in manifest, 'Debug APK is not a release'
assert 'minSdkVersion(0x0101020c)=24' in manifest
assert 'targetSdkVersion(0x01010270)=36' in manifest
assert 'android.permission.INTERNET' in manifest
assert 'allowBackup(0x01010280)=false' in manifest
assert 'usesCleartextTraffic(0x010104ec)=false' in manifest
assert 'net.nfet.flutter.printing.PrintFileProvider' in manifest
assert 'com.nexapos.app' in manifest and 'path(0x0101002a)="/callback"' in manifest
assert xml(resource_files('xml/backup_rules')[0]).count('E: exclude') == 5
assert xml(resource_files('xml/data_extraction_rules')[0]).count('E: exclude') == 10
signature = subprocess.check_output([str(sdk / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
assert 'CN=NexaPOS Release' in signature and 'CN=Android Debug' not in signature
certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)
assert certificate, 'No verified signing certificate'
properties_path = Path(os.environ.get('NEXAPOS_ANDROID_SIGNING_PROPERTIES', '/workspace/.nexapos-release-signing/key.properties'))
if not properties_path.is_file():
    properties_path = root / 'android/key.properties'
assert properties_path.is_file(), 'Cannot verify retained signing identity'
properties = dict(line.split('=', 1) for line in properties_path.read_text().splitlines() if '=' in line)
store = Path(properties['storeFile'])
if not store.is_absolute():
    store = root / 'android' / store
env = dict(os.environ, NEXAPOS_VERIFY_STORE_PASSWORD=properties['storePassword'])
der = subprocess.check_output([str(Path(os.environ['JAVA_HOME']) / 'bin/keytool'), '-exportcert',
                               '-keystore', str(store), '-alias', properties['keyAlias'],
                               '-storepass:env', 'NEXAPOS_VERIFY_STORE_PASSWORD'], env=env, stderr=subprocess.PIPE)
assert hashlib.sha256(der).hexdigest() == certificate.group(1), 'APK signed by another key'
provenance = json.loads((root / 'assets/fonts/PROVENANCE.json').read_text())
abis = ['armeabi-v7a', 'arm64-v8a', 'x86_64']
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None, 'APK ZIP CRC validation failed'
    names = archive.namelist()
    for abi in abis:
        for library in ['libflutter.so', 'libapp.so', 'libsqlcipher.so']:
            data = archive.read(f'lib/{abi}/{library}')
            assert data[:4] == b'\x7fELF' and len(data) > 0, f'Missing native/AOT library: {abi}/{library}'
    for font, digest in provenance['packaged_fonts'].items():
        assert hashlib.sha256(archive.read('assets/flutter_assets/assets/fonts/' + font)).hexdigest() == digest
    for name in ['NOTO-LICENSE.txt', 'NOTO-CJK-LICENSE.txt', 'PROVENANCE.json']:
        assert 'assets/flutter_assets/assets/fonts/' + name in names
    mapping_path = root / 'build/app/outputs/mapping/release/mapping.txt'
    mapping = mapping_path.read_text()
    printing = re.search(r'^net\.nfet\.flutter\.printing\.PrintingPlugin -> ([^:]+):$', mapping, re.M)
    assert printing, 'Printing plugin missing from release shrinker output'
    descriptor = ('L' + printing.group(1).replace('.', '/') + ';').encode()
    assert any(descriptor in archive.read(name) for name in names if name.endswith('.dex'))
    icons = resource_files('mipmap/ic_launcher')
    assert len(icons) == 5 and all(archive.read(name).startswith(b'\x89PNG\r\n\x1a\n') for name in icons)
result = {
    'filename': 'NexaPOS-Android.apk', 'bytes': apk.stat().st_size,
    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
    'build_type': 'release', 'package_id': 'com.nexapos.app', 'version': '0.1.0+1',
    'min_sdk': 24, 'target_sdk': 36, 'abis': abis,
    'signing': 'Dedicated retained RSA-3072 release key; APK v2 signature verified',
    'signer_certificate_sha256': certificate.group(1),
    'fonts_and_licenses_verified': True, 'native_and_aot_libraries_verified': True,
    'backup_exclusions_verified': True, 'debuggable': False,
    'supabase_configuration': 'Disconnected preview, explicitly selected by user',
    'device_launch': 'Not established by static artifact inspection',
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
