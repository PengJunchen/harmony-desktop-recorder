#!/usr/bin/env python3
"""Build unsigned release assets from a clean, committed source snapshot."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    subprocess.run(['python3', 'scripts/check-repository.py'], cwd=ROOT, check=True)
    if git('status', '--porcelain').strip():
        raise SystemExit('Commit all source changes before packaging a release.')
    revision = git('rev-parse', 'HEAD').decode().strip()
    app = json.loads(git('show', 'HEAD:AppScope/app.json5'))['app']
    version = app['versionName']
    tag = f'v{version}'
    tagged = subprocess.run(['git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}'],
                            cwd=ROOT, capture_output=True, text=True)
    if tagged.returncode == 0 and tagged.stdout.strip() != revision:
        raise SystemExit(f'{tag} already refers to another commit; do not replace published versions.')
    destination = ROOT / 'artifacts' / f'release-{version}'
    if destination.exists():
        raise SystemExit(f'{destination.name} already exists. Keep it or move it aside before rebuilding.')
    source = git('archive', '--format=zip', '--prefix=harmony-desktop-recorder/', 'HEAD')
    with tempfile.TemporaryDirectory(prefix='qinglu-release-') as temporary:
        workspace = Path(temporary)
        with zipfile.ZipFile(io.BytesIO(source)) as archive:
            archive.extractall(workspace)
        project = workspace / 'harmony-desktop-recorder'
        # The private build-profile.json5 and all ignored files are absent from git archive.
        env = dict(os.environ, RECORDER_BUILD_MODE='release')
        subprocess.run(['bash', 'scripts/build.sh'], cwd=project, env=env, check=True)
        outputs = project / 'entry/build/default/outputs/default'
        hap = outputs / 'entry-default-unsigned.hap'
        if not hap.is_file() or (outputs / 'entry-default-signed.hap').exists():
            raise SystemExit('Expected only an unsigned HAP from the clean source snapshot.')
        with zipfile.ZipFile(hap) as archive:
            if archive.testzip():
                raise SystemExit('HAP ZIP integrity check failed.')
            manifest = json.loads(archive.read('module.json'))
            built, module = manifest['app'], manifest['module']
            if (built['bundleName'] != app['bundleName'] or
                built['versionName'] != version or built['versionCode'] != app['versionCode'] or
                built.get('buildMode') != 'release' or built.get('debug') is not False or
                module.get('deviceTypes') != ['2in1'] or module.get('dependencies')):
                raise SystemExit('HAP metadata does not match the standalone desktop release.')
            forbidden = {'.p12', '.p7b', '.csr', '.cer', '.log', '.mp4'}
            if any(Path(name).suffix.lower() in forbidden or 'sourceMaps' in name for name in archive.namelist()):
                raise SystemExit('HAP unexpectedly contains signing material, logs or source maps.')
        # Official verification must reject this file as unsigned, even though it is a valid HAP ZIP.
        deveco = Path(env.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
        check = subprocess.run([str(deveco / 'jbr/Contents/Home/bin/java'), '-jar',
                                str(deveco / 'sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar'),
                                'verify-app', '-inFile', str(hap), '-outCertChain', str(workspace / 'check.cer'),
                                '-outProfile', str(workspace / 'check.p7b')], capture_output=True, text=True)
        if 'verify-app success' in (check.stdout + check.stderr).lower():
            raise SystemExit('Refusing to publish a signed HAP as unsigned.')
        unsigned_output = (check.stdout + check.stderr).lower()
        if not any(reason in unsigned_output for reason in ('no signature', 'not signed', 'signature not found', 'signature block')):
            raise SystemExit('Could not establish that the HAP is unsigned with hap-sign-tool.')
        staged = workspace / 'assets'
        staged.mkdir()
        shutil.copyfile(hap, staged / f'Qinglu-{version}-2in1-api24-unsigned.hap')
        (staged / f'Qinglu-{version}-source.zip').write_bytes(source)
        shutil.copyfile(project / 'docs/INSTALL.md', staged / 'INSTALL.md')
        assets = [{'name': path.name, 'size': path.stat().st_size, 'sha256': digest(path)}
                  for path in sorted(staged.iterdir())]
        release = {'version': version, 'versionCode': app['versionCode'], 'tag': tag, 'sourceCommit': revision,
                   'bundleName': app['bundleName'], 'deviceTypes': ['2in1'], 'minApi': 24,
                   'buildMode': 'release', 'debug': False, 'signed': False,
                   'compileSdkVersion': built['compileSdkVersion'], 'assets': assets}
        (staged / 'release-manifest.json').write_text(json.dumps(release, indent=2, ensure_ascii=False) + '\n')
        (staged / 'SHA256SUMS').write_text(''.join(f'{digest(path)}  {path.name}\n'
                                               for path in sorted(staged.iterdir())))
        destination.parent.mkdir(exist_ok=True)
        shutil.copytree(staged, destination)
    print(f'Release assets: {destination}')
    print(f'Source commit: {revision}; tag: {tag}; release mode; unsigned; 2in1 / API 24')
    for path in sorted(destination.iterdir()):
        print(f'{path.name}: {path.stat().st_size} bytes')


if __name__ == '__main__':
    main()
