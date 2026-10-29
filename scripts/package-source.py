#!/usr/bin/env python3
"""Package source without local signing identities, device evidence or build caches."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent.parent
artifacts = root / 'artifacts'
artifacts.mkdir(exist_ok=True)
version = json.loads((root / 'AppScope/app.json5').read_text())['app']['versionName']
destination = artifacts / f'Qinglu-{version}-source.zip'
excluded = {'.device', '.idea', '.hvigor', '.git', 'artifacts', 'build', 'oh_modules', 'node_modules', '__pycache__'}
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if not path.is_file() or any(part in excluded for part in relative.parts):
            continue
        if path.name == 'local.properties' or path.suffix in {'.p12', '.p7b', '.csr', '.cer', '.log', '.pyc'}:
            continue
        data = path.read_bytes()
        if relative.as_posix() == 'build-profile.json5':
            # The checked build profile is strict JSON until DevEco edits it. JSON5 is loaded via its bundled parser.
            import os
            import subprocess
            deveco = Path(os.environ.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
            parser = deveco / 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5'
            code = 'const f=require("fs"),j=require(process.argv[1]);process.stdout.write(JSON.stringify(j.parse(f.readFileSync(process.argv[2],"utf8"))));'
            result = subprocess.run([str(deveco / 'tools/node/bin/node'), '-e', code, str(parser), str(path)],
                                    check=True, capture_output=True, text=True)
            profile = json.loads(result.stdout)
            profile.get('app', {}).pop('signingConfigs', None)
            for product in profile.get('app', {}).get('products', []):
                product.pop('signingConfig', None)
            data = (json.dumps(profile, indent=2) + '\n').encode()
        archive.writestr('harmony-desktop-recorder/' + relative.as_posix(), data)
digest = hashlib.sha256(destination.read_bytes()).hexdigest()
print(json.dumps({'path': str(destination), 'sha256': digest}, indent=2))
