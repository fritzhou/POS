#!/usr/bin/env python3
"""Install checksum-verified Android command-line tools and Temurin JDK 21."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

TOOLS = Path(os.environ.get('NEXAPOS_TOOLCHAIN_ROOT', '/workspace/.toolchains'))
DOWNLOADS = Path('/tmp/nexapos-toolchain-downloads')
DOWNLOADS.mkdir(parents=True, exist_ok=True)
TOOLS.mkdir(parents=True, exist_ok=True)


def read_url(url):
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def download_verified(url, destination, algorithm, expected, size=None):
    def verify():
        digest = hashlib.new(algorithm)
        with destination.open('rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(chunk)
        return digest.hexdigest() == expected and (size is None or destination.stat().st_size == size)
    if not destination.exists() or not verify():
        print('Downloading:', url, flush=True)
        temporary = destination.with_suffix(destination.suffix + '.partial')
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
        temporary.replace(destination)
    if not verify():
        destination.unlink()
        raise RuntimeError(f'{algorithm} or size verification failed for {destination.name}')
    print(f'Verified {algorithm}: {expected} ({destination.stat().st_size} bytes)', flush=True)


android_path = TOOLS / 'android-sdk' / 'cmdline-tools' / 'latest'
if not (android_path / 'bin' / 'sdkmanager').exists():
    metadata = ET.fromstring(read_url('https://dl.google.com/android/repository/repository2-1.xml'))
    package = next(item for item in metadata if item.get('path') == 'cmdline-tools;latest')
    revision = next(item for item in package if item.tag.split('}')[-1] == 'revision')
    version = '.'.join(part.text for part in revision if part.tag.split('}')[-1] in ['major', 'minor', 'micro'])
    archives = next(item for item in package if item.tag.split('}')[-1] == 'archives')
    linux = next(archive for archive in archives if any(child.tag.split('}')[-1] == 'host-os' and child.text == 'linux' for child in archive))
    complete = next(child for child in linux if child.tag.split('}')[-1] == 'complete')
    data = {child.tag.split('}')[-1]: child.text for child in complete}
    checksum = next(child for child in complete if child.tag.split('}')[-1] == 'checksum')
    algorithm = checksum.get('type', 'sha1')
    if algorithm not in ['sha1', 'sha256']:
        raise RuntimeError('Unsupported publisher checksum algorithm')
    archive = DOWNLOADS / data['url']
    download_verified('https://dl.google.com/android/repository/' + data['url'], archive, algorithm, data['checksum'], int(data['size']))
    staging = DOWNLOADS / 'android-extract'
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            target = (staging / entry.filename).resolve()
            if not target.is_relative_to(staging.resolve()):
                raise RuntimeError('Unsafe path in Android tools archive')
        source.extractall(staging)
        for entry in source.infolist():
            mode = (entry.external_attr >> 16) & 0o777
            if mode and not entry.is_dir():
                (staging / entry.filename).chmod(mode)
    android_path.parent.mkdir(parents=True, exist_ok=True)
    if android_path.exists():
        raise RuntimeError('Refusing to overwrite incomplete existing Android tools directory')
    shutil.move(str(staging / 'cmdline-tools'), str(android_path))
    shutil.rmtree(staging)
    print('Android command-line tools installed:', version, flush=True)

jdk_path = TOOLS / 'jdk'
if not (jdk_path / 'bin' / 'javac').exists():
    release = 'jdk-21.0.12.1%2B1'
    filename = 'OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz'
    url = f'https://github.com/adoptium/temurin21-binaries/releases/download/{release}/{filename}'
    checksum_text = read_url(url + '.sha256.txt').decode()
    expected = checksum_text.split()[0]
    if not re.fullmatch('[a-fA-F0-9]{64}', expected):
        raise RuntimeError('Invalid publisher JDK checksum')
    archive = DOWNLOADS / filename
    download_verified(url, archive, 'sha256', expected.lower())
    staging = DOWNLOADS / 'jdk-extract'
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    with tarfile.open(archive) as source:
        source.extractall(staging, filter='data')
    children = list(staging.iterdir())
    if len(children) != 1 or not (children[0] / 'bin' / 'javac').exists():
        raise RuntimeError('Unexpected JDK archive structure')
    if jdk_path.exists():
        raise RuntimeError('Refusing to overwrite incomplete existing JDK directory')
    shutil.move(str(children[0]), str(jdk_path))
    shutil.rmtree(staging)
    print('Temurin JDK installed: 21.0.12.1+1', flush=True)

print(json.dumps({'android_sdk': str(TOOLS / 'android-sdk'), 'jdk': str(jdk_path)}, indent=2), flush=True)
