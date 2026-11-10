#!/bin/sh
# Builds the app and runs it from the build folder. Arguments are passed on to the app:
#   scripts/run-app.sh -showWindow YES -section stale
set -eu
cd "$(dirname "$0")/.."

xcodegen generate --spec App/project.yml --quiet
xcodebuild build \
  -project App/AgentActivityMonitor.xcodeproj \
  -scheme AgentActivityMonitor \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -quiet
exec "build/DerivedData/Build/Products/Debug/Agent Activity Monitor.app/Contents/MacOS/Agent Activity Monitor" "$@"
