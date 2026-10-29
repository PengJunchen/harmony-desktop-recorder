#!/usr/bin/env python3
"""Prepare an isolated unsigned APP; official release signing and market review remain separate."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engineering-only', action='store_true', help='Allow a staged draft for local build validation; never submit it')
args = parser.parse_args()


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT)


def main():
    if git('diff', '--name-only').strip():
        raise SystemExit('Stage the intended source changes before building a draft, or commit them for submission preparation.')
    if not args.engineering_only and git('status', '--porcelain').strip():
        raise SystemExit('Commit the completed market source before preparing submission assets.')
    source = (ROOT / 'entry/src/main/ets/recording/AppMetadata.ts').read_text()
    contact = re.search(r"PRIVACY_CONTACT: string = '([^']*)'", source)
    version = json.loads((ROOT / 'AppScope/app.json5').read_text())['app']['versionName']
    if not args.engineering_only and (not contact or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', contact[1])):
        raise SystemExit('An explicitly approved public privacy/support email is required before market packaging.')
    if f"APP_VERSION: string = '{version}'" not in source:
        raise SystemExit('Application and About-page versions differ.')
    tree = git('write-tree').decode().strip()
    archive = git('archive', '--format=zip', tree)
    deveco = Path(os.environ.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
    kind = 'internal' if args.engineering_only else 'market'
    destination = ROOT / 'artifacts' / f'market-{version}-{kind}'
    if destination.exists():
        raise SystemExit('Output already exists; preserve or move it aside before rebuilding.')
    with tempfile.TemporaryDirectory(prefix='qinglu-market-') as temporary:
        project = Path(temporary) / 'source'
        project.mkdir()
        with zipfile.ZipFile(io.BytesIO(archive)) as contents:
            contents.extractall(project)
        env = dict(os.environ, RECORDER_BUILD_MODE='release', RECORDER_PACKAGE_KIND='app')
        subprocess.run(['bash', 'scripts/build.sh'], cwd=project, env=env, check=True)
        apps = list((project / 'build').glob('**/outputs/**/*.app'))
        if len(apps) != 1:
            raise SystemExit(f'Expected one clean APP output, found {len(apps)}.')
        app = apps[0]
        with zipfile.ZipFile(app) as package:
            nested = [name for name in package.namelist() if name.endswith('.hap')]
            if len(nested) != 1 or 'pack.info' not in package.namelist():
                raise SystemExit('APP must contain pack.info and exactly one HAP.')
            with zipfile.ZipFile(io.BytesIO(package.read(nested[0]))) as hap:
                info = json.loads(hap.read('module.json'))
                if (info['app']['versionName'] != version or info['app'].get('debug') is not False or
                    info['app'].get('buildMode') != 'release' or info['module']['deviceTypes'] != ['2in1']):
                    raise SystemExit('Invalid market package metadata.')
        destination.mkdir(parents=True)
        output = destination / f'Qinglu-{version}-2in1-{kind}-unsigned.app'
        shutil.copyfile(app, output)
        # This is a build manifest, not a market approval or a test report.
        manifest = {'version': version, 'sourceTree': tree, 'sourceCommit': git('rev-parse', 'HEAD').decode().strip(),
                    'engineeringOnly': args.engineering_only, 'signed': False, 'marketSubmitted': False,
                    'file': output.name, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
        (destination / 'package-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps(manifest, indent=2))
        print(f'APP prepared in {destination}; official release signing and market submission are still required.')


if __name__ == '__main__':
    main()
