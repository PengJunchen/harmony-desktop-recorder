#!/usr/bin/env python3
"""Verify a debug HAP locally without persisting certificate or device reports."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--hap', type=Path, required=True)
parser.add_argument('--target', help='Optional exact HDC target to check against the debug Profile')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
deveco = Path(os.environ.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
java = deveco / 'jbr/Contents/Home/bin/java'
sdk = deveco / 'sdk/default/openharmony'
tool = sdk / 'toolchains/lib/hap-sign-tool.jar'

def run(*arguments):
    result = subprocess.run([str(java), '-jar', str(tool), *map(str, arguments)],
                            text=True, capture_output=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f'{arguments[0]} failed. Rebuild with the matching DevEco debug signing configuration.')
    return result

def read_project_app():
    source = root / 'AppScope/app.json5'
    try:
        return json.loads(source.read_text())['app']
    except json.JSONDecodeError:
        json5 = deveco / 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5'
        code = 'const f=require("fs"),j=require(process.argv[1]);process.stdout.write(JSON.stringify(j.parse(f.readFileSync(process.argv[2],"utf8")).app));'
        result = subprocess.run([str(deveco / 'tools/node/bin/node'), '-e', code, str(json5), str(source)],
                                check=True, text=True, capture_output=True)
        return json.loads(result.stdout)

try:
    if not args.hap.is_file():
        raise RuntimeError('Signed HAP does not exist. Run bash scripts/build.sh after configuring debug signing.')
    with zipfile.ZipFile(args.hap) as archive:
        app = json.loads(archive.read('module.json'))['app']
    expected = read_project_app()['bundleName']
    if app.get('bundleName') != expected:
        raise RuntimeError('HAP bundle name does not match AppScope/app.json5.')
    with tempfile.TemporaryDirectory(prefix='qinglu-signature-') as temporary:
        directory = Path(temporary)
        profile = directory / 'profile.p7b'
        checked = run('verify-app', '-inFile', args.hap.resolve(), '-outCertChain', directory / 'chain.cer', '-outProfile', profile)
        if 'verify-app success' not in checked.stdout.lower():
            raise RuntimeError('HAP verification did not report success.')
        output = directory / 'profile.json'
        run('verify-profile', '-inFile', profile, '-outFile', output)
        verification = json.loads(output.read_text())
        if verification.get('verifiedPassed') is not True:
            raise RuntimeError('Profile signature verification did not pass.')
        content = verification['content']
        if content.get('type') != 'debug':
            raise RuntimeError('This HAP does not contain a debug Profile.')
        if content.get('bundle-info', {}).get('bundle-name') != expected:
            raise RuntimeError('Debug Profile bundle name does not match this application.')
        validity = content.get('validity', {})
        now = time.time()
        if not validity.get('not-before', now + 1) <= now < validity.get('not-after', 0):
            raise RuntimeError('Debug Profile is expired or not yet valid. Regenerate it in DevEco.')
        device_matched = None
        if args.target:
            result = subprocess.run([str(sdk / 'toolchains/hdc'), '-t', args.target, 'shell', 'bm', 'get', '-u'],
                                    text=True, capture_output=True, timeout=15, check=True)
            identifiers = re.findall(r'\b[0-9a-fA-F]{64}\b', result.stdout)
            allowed = content.get('debug-info', {}).get('device-ids', [])
            device_matched = any(a.lower() == b.lower() for a in identifiers for b in allowed)
            if not device_matched:
                raise RuntimeError('Connected device is not included in this debug Profile. Add it and regenerate the Profile.')
        print(f'Debug signature verified: {expected} {app.get("versionName", "")}')
        print('HAP integrity, Profile signature, bundle name, debug type and validity: OK')
        if device_matched:
            print('Connected HDC device matches the debug Profile: OK')
        else:
            print('Device binding not checked; supply --target to verify it before installation.')
except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
    raise SystemExit(f'Debug signature check failed: {error}')
