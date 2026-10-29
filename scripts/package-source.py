#!/usr/bin/env python3
"""Package source without local signing identities, device evidence or build caches."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
artifacts = root / 'artifacts'
artifacts.mkdir(exist_ok=True)
subprocess.run(['python3', str(root / 'scripts/check-repository.py')], check=True, cwd=root)
if subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--'], cwd=root).returncode != 0:
    raise SystemExit('Commit source changes before packaging; the archive is created from Git HEAD.')
app = subprocess.run(['git', 'show', 'HEAD:AppScope/app.json5'], cwd=root,
                     check=True, capture_output=True, text=True).stdout
version = json.loads(app)['app']['versionName']
destination = artifacts / f'Qinglu-{version}-source.zip'
subprocess.run(['git', 'archive', '--format=zip', '--prefix=harmony-desktop-recorder/',
                '--output', str(destination), 'HEAD'], cwd=root, check=True)
digest = hashlib.sha256(destination.read_bytes()).hexdigest()
print(json.dumps({'path': str(destination), 'sha256': digest}, indent=2))
