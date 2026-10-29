#!/usr/bin/env python3
"""Sign with the SDK's public OpenHarmony development keys (never a production identity)."""
import json
import hashlib
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

root = Path(__file__).resolve().parent.parent
deveco = Path(os.environ.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
sdk = Path(os.environ.get('RECORDER_SIGNING_SDK', str(Path.home() / 'Library/OpenHarmony/Sdk/26.0.0')))
java = deveco / 'jbr/Contents/Home/bin/java'
keytool = deveco / 'jbr/Contents/Home/bin/keytool'
lib = sdk / 'toolchains/lib'
unsigned = root / 'entry/build/default/outputs/default/entry-default-unsigned.hap'
artifacts = root / 'artifacts'
signing = artifacts / 'openharmony-test-signing'
signing.mkdir(parents=True, exist_ok=True)
keystore = lib / 'OpenHarmony.p12'

# This password is deliberately public: it belongs to the SDK test keystore.
def certificate(alias):
    result = subprocess.run([str(keytool), '-list', '-rfc', '-alias', alias,
                             '-keystore', str(keystore), '-storepass', '123456'],
                            check=True, capture_output=True, text=True)
    certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', result.stdout, re.S)
    if not certs:
        raise RuntimeError('SDK OpenHarmony test certificate missing')
    return certs[0]

chain_path = root / 'scripts/openharmony-test-chain.pem'
origin = json.loads((root / 'scripts/openharmony-test-chain-origin.json').read_text())
if hashlib.sha256(chain_path.read_bytes()).hexdigest() != origin['sha256']:
    raise RuntimeError('Public OpenHarmony test certificate chain checksum mismatch')
# Upstream ships root -> intermediate -> leaf; hap-sign-tool expects leaf first.
certs = list(reversed(re.findall(
    r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', chain_path.read_text(), re.S)))
def public_key(cert):
    return subprocess.run(['openssl', 'x509', '-pubkey', '-noout'], input=cert,
                          text=True, capture_output=True, check=True).stdout

if len(certs) != 3 or public_key(certs[0]) != public_key(certificate('openharmony application release')):
    raise RuntimeError('SDK test signing identity does not match the pinned upstream public certificate')
app_cert = signing / 'test-app-chain.pem'
app_cert.write_text('\n'.join(certs) + '\n')
now = int(time.time())
profile = {
    'version-name': '2.0.0', 'version-code': 2,
    'app-distribution-type': 'os_integration', 'uuid': str(uuid.uuid4()),
    'validity': {'not-before': now - 60, 'not-after': now + 30 * 86400},
    'type': 'release',
    'bundle-info': {
        'developer-id': 'OpenHarmony', 'distribution-certificate': certs[0] + '\n',
        'bundle-name': 'com.personal.desktoprecorder', 'apl': 'normal', 'app-feature': 'hos_normal_app'
    },
    'acls': {'allowed-acls': []}, 'permissions': {'restricted-permissions': []}, 'issuer': 'pki_internal'
}
profile_json = signing / 'test-profile.json'
profile_json.write_text(json.dumps(profile, indent=2) + '\n')
profile_signed = signing / 'test-profile.p7b'

def run(*args):
    subprocess.run([str(java), '-jar', str(lib / 'hap-sign-tool.jar'), *map(str, args)], check=True)

run('sign-profile', '-mode', 'localSign', '-keyAlias', 'openharmony application profile release',
    '-signAlg', 'SHA256withECDSA', '-profileCertFile', lib / 'OpenHarmonyProfileRelease.pem',
    '-inFile', profile_json, '-keystoreFile', keystore, '-keyPwd', '123456', '-keystorePwd', '123456',
    '-outFile', profile_signed)
signed = artifacts / 'Qinglu-0.1.0-openharmony-test-signed.hap'
run('sign-app', '-mode', 'localSign', '-keyAlias', 'openharmony application release',
    '-signAlg', 'SHA256withECDSA', '-appCertFile', app_cert, '-profileFile', profile_signed,
    '-inFile', unsigned, '-keystoreFile', keystore, '-keyPwd', '123456', '-keystorePwd', '123456',
    '-compatibleVersion', '24', '-signCode', '1', '-outFile', signed)
run('verify-app', '-inFile', signed, '-outCertChain', signing / 'verified-chain.cer',
    '-outProfile', signing / 'verified-profile.p7b')
print(f'OpenHarmony test-key signed and verified: {signed}')
print('Target device must trust the standard OpenHarmony test certificate. This is not a production signature.')
