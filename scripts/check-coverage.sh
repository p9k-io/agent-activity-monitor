#!/bin/sh
# Enforces the line-coverage floor of each module.
# Run after: swift test --enable-code-coverage
set -eu

report=$(swift test --show-codecov-path)
failed=0

check() {
  module=$1
  minimum=$2
  percent=$(
    jq -r --arg dir "/Sources/$module/" '
      [.data[0].files[] | select(.filename | contains($dir)) | .summary.lines]
      | (map(.count) | add // 0) as $count
      | (map(.covered) | add // 0) as $covered
      | if $count == 0 then 100 else ($covered * 100 / $count | floor) end
    ' "$report"
  )
  echo "$module: $percent % line coverage (floor $minimum %)"
  if [ "$percent" -lt "$minimum" ]; then
    failed=1
  fi
}

check AAMCore 90
check AAMPlatform 70
check AAMCleanup 90

exit $failed
