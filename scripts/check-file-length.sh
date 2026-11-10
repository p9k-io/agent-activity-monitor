#!/bin/sh
# Fails when a tracked Swift file is longer than the limit.
set -eu

limit=500
over=$(
  git ls-files '*.swift' | while IFS= read -r file; do
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -gt "$limit" ]; then
      echo "$file: $lines lines (limit $limit)"
    fi
  done
)

if [ -n "$over" ]; then
  echo "$over"
  exit 1
fi
