#!/bin/bash
set -euo pipefail
RECORDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDER_DEVECO="${RECORDER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
if [ -x "$RECORDER_DEVECO/tools/node/bin/node" ]; then
  RECORDER_NODE="$RECORDER_DEVECO/tools/node/bin/node"
else
  RECORDER_NODE="$(command -v node)"
fi
exec "$RECORDER_NODE" --test "$RECORDER_ROOT/tests/recorder.test.cjs"
