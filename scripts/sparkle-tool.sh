#!/bin/sh
# Runs one of the tools that come with Sparkle: generate_keys, sign_update, generate_appcast.
#   scripts/sparkle-tool.sh generate_keys      makes the key that signs updates, once
#   scripts/sparkle-tool.sh generate_keys -p   prints its public half
set -eu
cd "$(dirname "$0")/.."

tool=${1:?usage: scripts/sparkle-tool.sh <tool> [arguments]}
shift

bin=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
if [ ! -x "$bin/$tool" ]; then
  xcodegen generate --spec App/project.yml --quiet
  xcodebuild -resolvePackageDependencies \
    -project App/AgentActivityMonitor.xcodeproj \
    -scheme AgentActivityMonitor \
    -derivedDataPath build/DerivedData >/dev/null
fi
[ -x "$bin/$tool" ] || { echo "sparkle-tool: $tool is not among Sparkle's tools." >&2; exit 1; }
exec "$bin/$tool" "$@"
