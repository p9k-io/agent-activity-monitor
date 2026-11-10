#!/bin/sh
# Every gate CI runs, cheapest first.
set -eu
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests App/Sources
scripts/check-file-length.sh
scripts/check-boundaries.sh
swift test --enable-code-coverage
scripts/check-coverage.sh
swift build -c release
xcodegen generate --spec App/project.yml --quiet
xcodebuild build \
  -project App/AgentActivityMonitor.xcodeproj \
  -scheme AgentActivityMonitor \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -quiet \
  CODE_SIGNING_ALLOWED=NO
