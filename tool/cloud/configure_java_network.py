#!/usr/bin/env python3
"""Configure existing cloud proxy and public CA trust for Java/Gradle."""
import os
import fcntl
from pathlib import Path
import re
import shlex
import shutil
import subprocess
from urllib.parse import urlparse

tools = Path(os.environ.get('NEXAPOS_TOOLCHAIN_ROOT', '/workspace/.toolchains'))
trust_dir = tools / 'java-trust'
trust_dir.mkdir(parents=True, exist_ok=True)
# Setup and build can be invoked from separate shells. Serialize all managed
# trust/proxy writes so a second process cannot replace another's staging file.
configuration_lock = (trust_dir / '.configure.lock').open('a')
fcntl.flock(configuration_lock.fileno(), fcntl.LOCK_EX)
gradle_dir = tools / 'gradle-cache'
gradle_dir.mkdir(parents=True, exist_ok=True)
proxy = urlparse(os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy') or os.environ.get('HTTP_PROXY') or '')
if not proxy.hostname:
    raise RuntimeError('No injected proxy configuration found')
if proxy.username or proxy.password:
    raise RuntimeError('Proxy authentication is present; refusing to serialize credentials')
if proxy.scheme != 'http' or not re.fullmatch(r'[a-zA-Z0-9._-]+', proxy.hostname):
    raise RuntimeError('Unsupported proxy format for JVM HTTP proxy settings')
proxy_port = proxy.port or 80

cert_value = os.environ.get('CODEX_PROXY_CERT')
if not cert_value:
    raise RuntimeError('Platform proxy certificate binding is unavailable')
cert_pem = cert_value if 'BEGIN CERTIFICATE' in cert_value else Path(cert_value).read_text()
certificates = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', cert_pem, re.S)
if not certificates:
    raise RuntimeError('Platform proxy certificate binding contains no PEM certificates')
standard_trust = tools / 'jdk' / 'lib' / 'security' / 'cacerts'
staging_trust = trust_dir / 'cacerts.staging'
truststore = trust_dir / 'cacerts'
shutil.copyfile(standard_trust, staging_trust)
keytool = tools / 'jdk' / 'bin' / 'keytool'
for index, certificate in enumerate(certificates):
    certificate_file = trust_dir / f'platform-proxy-{index}.pem'
    certificate_file.write_text(certificate + '\n')
    result = subprocess.run([
        str(keytool), '-importcert', '-noprompt', '-trustcacerts',
        '-alias', f'nexapos-platform-proxy-{index}', '-keystore', str(staging_trust),
        '-storepass', 'changeit', '-file', str(certificate_file),
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError('Platform certificate import failed; diagnostic output withheld to avoid exposing environment values')
staging_trust.replace(truststore)
properties = {
    'http.proxyHost': proxy.hostname,
    'http.proxyPort': str(proxy_port),
    'https.proxyHost': proxy.hostname,
    'https.proxyPort': str(proxy_port),
    'javax.net.ssl.trustStore': str(truststore),
    'javax.net.ssl.trustStorePassword': 'changeit',
    'user.home': str(tools / 'config' / 'java'),
    'java.util.prefs.userRoot': str(tools / 'config' / 'java-prefs'),
}
for directory in [tools / 'config' / 'java', tools / 'config' / 'java-prefs']:
    directory.mkdir(parents=True, exist_ok=True)
properties_file = gradle_dir / 'gradle.properties'
begin = '# NexaPOS cloud Java network BEGIN'
end = '# NexaPOS cloud Java network END'
existing = properties_file.read_text() if properties_file.exists() else ''
existing = re.sub(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', existing, flags=re.S).rstrip()
managed = begin + '\n' + '\n'.join('systemProp.' + key + '=' + value for key, value in properties.items()) + '\n' + end + '\n'
properties_file.write_text((existing + '\n\n' if existing else '') + managed)
options = ' '.join('-D' + key + '=' + value for key, value in properties.items())
env_script = trust_dir / 'network-env.sh'
env_script.write_text('export JAVA_OPTS="${JAVA_OPTS:+$JAVA_OPTS }"' + shlex.quote(options) + '\n')
print(f'Configured JVM/Gradle proxy and imported {len(certificates)} platform certificate(s); TLS verification remains enabled.')
print('Runtime configuration written outside the checkout; no proxy values or credentials were printed.')
configuration_lock.close()
