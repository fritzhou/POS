#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlparse

tools = Path(os.environ.get('NEXAPOS_TOOLCHAIN_ROOT', '/workspace/.toolchains'))
sdk_root = str(tools / 'android-sdk')
manager = sdk_root + '/cmdline-tools/latest/bin/sdkmanager'
os.environ.update({
    'JAVA_HOME': str(tools / 'jdk'),
    'ANDROID_HOME': sdk_root,
    'ANDROID_SDK_ROOT': sdk_root,
    'ANDROID_USER_HOME': str(tools / 'config/android'),
    'GRADLE_USER_HOME': str(tools / 'gradle-cache'),
    'JAVA_OPTS': os.environ.get('JAVA_OPTS', '') + ' -Duser.home=' + str(tools / 'config/java'),
})
for path in ['ANDROID_USER_HOME', 'GRADLE_USER_HOME']:
    Path(os.environ[path]).mkdir(parents=True, exist_ok=True)
(tools / 'config/java').mkdir(parents=True, exist_ok=True)
if os.environ.get('CODEX_PROXY_CERT') and any(os.environ.get(name) for name in ['HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY']):
    subprocess.run([sys.executable, str(Path(__file__).with_name('configure_java_network.py'))], check=True)
    os.environ['JAVA_OPTS'] += ' -Djavax.net.ssl.trustStore=' + str(tools / 'java-trust/cacerts') + ' -Djavax.net.ssl.trustStorePassword=changeit'
args = [manager, '--sdk_root=' + sdk_root]
proxy = urlparse(os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy') or '')
if proxy.hostname:
    if proxy.username or proxy.password:
        raise RuntimeError('Configured proxy requires authentication not supported by SDK manager flags')
    args.extend(['--proxy=http', '--proxy_host=' + proxy.hostname, '--proxy_port=' + str(proxy.port or 80)])

licenses_log = Path('/tmp/nexapos-android-licenses.log')
with licenses_log.open('w') as output:
    result = subprocess.run(args + ['--licenses'], input='y\n' * 100, text=True, stdout=output, stderr=subprocess.STDOUT)
print('License acceptance exit code:', result.returncode, flush=True)
print('\n'.join(licenses_log.read_text().splitlines()[-8:]), flush=True)
if result.returncode:
    raise SystemExit(result.returncode)
packages = ['platform-tools', 'platforms;android-35', 'platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358', 'cmake;3.22.1']
print('Installing SDK packages:', ', '.join(packages), flush=True)
packages_log = Path('/tmp/nexapos-android-packages.log')
with packages_log.open('w') as output:
    result = subprocess.run(args + packages, stdout=output, stderr=subprocess.STDOUT)
print('Package installation exit code:', result.returncode, flush=True)
print('\n'.join(packages_log.read_text().splitlines()[-15:]), flush=True)
raise SystemExit(result.returncode)
