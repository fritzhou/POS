#!/usr/bin/env python3
"""Create a first local release key only on explicit request; retain it for updates."""
import argparse
import os
from pathlib import Path
import secrets
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--create-local-key', action='store_true')
parser.add_argument('--directory', type=Path, default=Path('/workspace/.nexapos-release-signing'))
args = parser.parse_args()
directory = args.directory.resolve()
properties = directory / 'key.properties'
keystore = directory / 'nexapos-release.p12'
existing = Path(__file__).resolve().parents[2] / 'android/key.properties'
if existing.is_file() or os.environ.get('NEXAPOS_ANDROID_SIGNING_PROPERTIES'):
    raise SystemExit('Existing release signing configuration found. Use it; local key creation refused.')
if directory.exists():
    if properties.is_file() and keystore.is_file():
        print('Retained local release signing files exist; no key was created or changed.')
        raise SystemExit(0)
    raise SystemExit('Partial or unknown signing directory found. Preserve it and recover the original key; refusing regeneration.')
if not args.create_local_key:
    raise SystemExit('No retained key found. Use --create-local-key only for a first signing identity.')
java = Path(os.environ.get('JAVA_HOME', '')) / 'bin/keytool'
if not java.is_file():
    raise SystemExit('Source tool/dev_env.sh before preparing release signing.')
directory.mkdir(mode=0o700, parents=True)
password = secrets.token_hex(32)
env = dict(os.environ, NEXAPOS_KEY_STORE_PASSWORD=password, NEXAPOS_KEY_PASSWORD=password)
command = [str(java), '-genkeypair', '-keystore', str(keystore), '-storetype', 'PKCS12',
           '-alias', 'nexapos', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
           '-dname', 'CN=NexaPOS Release, OU=Application Signing, O=NexaPOS',
           '-storepass:env', 'NEXAPOS_KEY_STORE_PASSWORD', '-keypass:env', 'NEXAPOS_KEY_PASSWORD']
result = subprocess.run(command, env=env, capture_output=True, text=True)
if result.returncode:
    raise SystemExit('Key creation failed. Signing directory retained for inspection; no credentials were printed.')
keystore.chmod(0o600)
content = f'storeFile={keystore}\nstorePassword={password}\nkeyAlias=nexapos\nkeyPassword={password}\n'
fd = os.open(properties, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as out:
    out.write(content)
print('Created a dedicated RSA-3072 release key and private configuration outside the checkout.')
print('Preserve both files and back them up securely for future updates; neither is a distributable artifact.')
