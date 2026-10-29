#!/usr/bin/env python3
"""Install a device-signed HAP and verify HDC's text result, not only its exit code."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--target', required=True, help='An exact target from hdc list targets')
parser.add_argument('--hap', required=True, type=Path)
args = parser.parse_args()
deveco = Path(os.environ.get('RECORDER_DEVECO', '/Applications/DevEco-Studio.app/Contents'))
hdc = deveco / 'sdk/default/openharmony/toolchains/hdc'
if not args.hap.is_file():
    parser.error('Signed HAP does not exist')
result = subprocess.run([str(hdc), '-t', args.target, 'install', '-r', str(args.hap.resolve())],
                        text=True, capture_output=True, timeout=120)
output = result.stdout + result.stderr
print(output)
if result.returncode or 'install bundle successfully' not in output.lower():
    raise SystemExit('INSTALL_FAILED: HDC did not report successful installation')
result = subprocess.run([str(hdc), '-t', args.target, 'shell', 'aa', 'start',
                         '-a', 'EntryAbility', '-b', 'com.personal.desktoprecorder'],
                        text=True, capture_output=True, timeout=30)
output = result.stdout + result.stderr
print(output)
if result.returncode or 'start ability successfully' not in output.lower():
    raise SystemExit('LAUNCH_FAILED: device did not report successful launch')
print('INSTALL_AND_LAUNCH_CONFIRMED; recording still requires the system authorization and sample validation.')
