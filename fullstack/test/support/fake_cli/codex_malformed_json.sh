#!/bin/sh
# Fake codex fixture: writes unparseable JSON (truncated) to the "-o" output
# file and exits 0.
output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

if [ -n "$output_file" ]; then
  printf '{"country": "Argentina", "city":' > "$output_file"
fi

exit 0
