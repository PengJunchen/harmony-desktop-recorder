#!/bin/bash
set -euo pipefail
RECORDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDER_DEVECO="${RECORDER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
exec "$RECORDER_DEVECO/tools/node/bin/node" --test "$RECORDER_ROOT/tests/recorder.test.cjs"
