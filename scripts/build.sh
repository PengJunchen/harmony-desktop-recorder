#!/bin/bash
set -euo pipefail
RECORDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDER_DEVECO="${RECORDER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
RECORDER_BUILD_MODE="${RECORDER_BUILD_MODE:-debug}"
case "$RECORDER_BUILD_MODE" in
  debug|release) ;;
  *) echo "RECORDER_BUILD_MODE must be debug or release" >&2; exit 2 ;;
esac
export PATH="$RECORDER_DEVECO/tools/node/bin:$RECORDER_DEVECO/tools/ohpm/bin:$PATH"
export JAVA_HOME="$RECORDER_DEVECO/jbr/Contents/Home"
export DEVECO_SDK_HOME="$RECORDER_DEVECO/sdk"
export OHOS_SDK_HOME="${OHOS_SDK_HOME:-$HOME/Library/OpenHarmony/Sdk}"
cd "$RECORDER_ROOT"
if [ ! -f build-profile.json5 ]; then
  cp build-profile.template.json5 build-profile.json5
fi
node -e 'const fs=require("fs"),path=require("path");const json5=require(path.join(process.env.RECORDER_DEVECO || "/Applications/DevEco-Studio.app/Contents", "tools/hvigor/hvigor-ohos-plugin/node_modules/json5"));const manifest=json5.parse(fs.readFileSync("entry/src/main/module.json5","utf8"));if(JSON.stringify(manifest.module.deviceTypes)!==JSON.stringify(["2in1"]))throw Error("Desktop recorder must target only 2in1; check whether IDE sync changed deviceTypes");'
exec node "$RECORDER_DEVECO/tools/hvigor/bin/hvigorw.js" --mode module -p product=default -p module=entry@default -p buildMode="$RECORDER_BUILD_MODE" assembleHap --no-daemon "$@"
