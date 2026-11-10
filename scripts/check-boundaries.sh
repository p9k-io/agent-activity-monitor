#!/bin/sh
# Enforces docs/adr/0001: only the app ends processes.
#   1. The module that sends signals is imported by nothing but the app and its own tests.
#   2. No source outside that module sends a signal to a process.
set -eu
cd "$(dirname "$0")/.."

failed=0

importers=$(
  grep -rlE '^[[:space:]]*import AAMCleanup' Sources Tests App/Sources \
    | grep -v -e '^App/Sources/' -e '^Tests/AAMCleanupTests/' || true
)
if [ -n "$importers" ]; then
  echo "AAMCleanup may be imported only by the app and by its own tests:"
  echo "$importers"
  failed=1
fi

signals=$(
  grep -rnE '(^|[^[:alnum:]_])(kill|killpg)\(|SIGKILL|SIGTERM|SIGINT|SIGHUP|\.terminate\(\)' \
    Sources App/Sources | grep -v '^Sources/AAMCleanup/' || true
)
if [ -n "$signals" ]; then
  echo "Only Sources/AAMCleanup may send a signal to a process:"
  echo "$signals"
  failed=1
fi

exit $failed
