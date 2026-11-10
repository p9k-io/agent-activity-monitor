#!/bin/sh
# Enforces docs/adr/0001: only the app ends processes.
#   1. The module that sends signals is imported by nothing but the app and its own tests.
#   2. No source outside that module sends a signal to a process, or starts a tool that does.
#   3. Nothing the command line tool is built from depends on that module.
set -eu
cd "$(dirname "$0")/.."

failed=0

# Any form of import: with attributes, with an access level, or of a single declaration.
importers=$(
  grep -rlE '^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((struct|class|enum|protocol|func|var|let|typealias)[[:space:]]+)?AAMCleanup' \
    Sources Tests App/Sources \
    | grep -v -e '^App/Sources/' -e '^Tests/AAMCleanupTests/' || true
)
if [ -n "$importers" ]; then
  echo "AAMCleanup may be imported only by the app and by its own tests:"
  echo "$importers"
  failed=1
fi

signals=$(
  grep -rnE '(^|[^[:alnum:]_])(kill|killpg|proc_terminate)\(|SIGKILL|SIGTERM|SIGINT|SIGHUP|\.terminate\(\)|\.interrupt\(\)|forceTerminate|"(/bin/|/usr/bin/)?(kill|pkill|killall)"' \
    Sources App/Sources | grep -v '^Sources/AAMCleanup/' || true
)
if [ -n "$signals" ]; then
  echo "Only Sources/AAMCleanup may send a signal to a process:"
  echo "$signals"
  failed=1
fi

# The manifest is what really keeps the module out of the command line tool: neither the tool
# nor anything it is built from may depend on the module.
dependents=$(
  swift package describe --type json \
    | jq -r '.targets[]
        | select(.name == "aam" or .name == "AAMCore" or .name == "AAMPlatform")
        | select((.target_dependencies // []) | index("AAMCleanup"))
        | .name'
)
if [ -n "$dependents" ]; then
  echo "Package.swift: these targets must not depend on AAMCleanup:"
  echo "$dependents"
  failed=1
fi

exit $failed
