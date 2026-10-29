#!/usr/bin/env python3
"""Reject local signing material and generated reports in the tracked source tree."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
result = subprocess.run(['git', 'ls-files', '-z'], cwd=root, check=True, capture_output=True)
names = [name.decode() for name in result.stdout.split(b'\0') if name]
forbidden = []
for name in names:
    path = Path(name)
    lowered = name.lower()
    if (name in {'build-profile.json5', 'local.properties'} or
        path.suffix.lower() in {'.p12', '.p7b', '.csr', '.log', '.mp4', '.hap'} or
        any(part in {'.device', 'artifacts', '.idea', '.hvigor', 'reports', 'test-results', 'coverage'} for part in path.parts) or
        path.name.upper() in {'VALIDATION.MD', 'VERIFICATION.MD'} or
        path.name.upper().startswith('TEST_REPORT')):
        forbidden.append(name)
        continue
    file = root / path
    if not file.is_file():
        continue
    data = file.read_bytes()
    if re.search(rb'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----', data):
        forbidden.append(name)
    if path.name == 'build-profile.template.json5' and re.search(rb'"(?:signingConfigs|storePassword|keyPassword)"\s*:', data):
        forbidden.append(name)
if forbidden:
    raise SystemExit('Remove local material or generated reports from Git:\n' + '\n'.join(sorted(set(forbidden))))
print(f'Repository source check passed ({len(names)} tracked files).')
