#!/bin/sh
# Fake codex fixture: writes every argv element, one per line, prefixed
# "ARG:[...]", into the "-o" output file itself (instead of only to stdout).
# This lets a test drive the adapter's own chat_completion/2 argv-building
# code end to end and assert on the exact argv it produced, via the text the
# adapter returns — rather than reconstructing argv by hand in the test.
output_file=""
prev=""
argv_dump=""
for arg in "$@"; do
  argv_dump="${argv_dump}ARG:[$arg]
"
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

if [ -n "$output_file" ]; then
  printf '%s' "$argv_dump" > "$output_file"
fi

exit 0
