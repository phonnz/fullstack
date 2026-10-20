#!/bin/sh
# Fake codex fixture: parses "-o <path>" out of argv, writes plain text to it,
# and exits 0. Mirrors real `codex exec ... -o <file> <prompt>` behaviour for
# text-mode responses.
output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

if [ -n "$output_file" ]; then
  printf 'PONG\n' > "$output_file"
fi

echo "codex exec: done"
exit 0
